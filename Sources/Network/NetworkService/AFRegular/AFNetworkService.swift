
import Alamofire
import Foundation
import NetworkInterface

open class AFNetworkService: AFNetworkServiceProtocol {
    
    private let session: Session
    private let logger: Log
    private let configuration: NetworkConfigurable
    
    public init(session: Session,
                logger: Log = DEBUGLog(),
                configuration: NetworkConfigurable) {
        self.session = session
        self.logger = logger
        self.configuration = configuration
    }
    
    public func request(endpoint: Requestable) async throws -> Data {
        let urlRequest = try endpoint.asURLRequest(config: configuration)
        let response = session.request(urlRequest).serializingData()
        await logger.log(response.response, endpoint)
        
        switch await response.result {
        case .success(let data):
            return data
        case .failure(let error):
            if error.isExplicitlyCancelledError {
                throw NetworkError.cancelled
            } else if error.isSessionTaskError || error.isResponseValidationError {
                throw NetworkError.generic(error)
            } else {
                let statusCode = await response.response.response?.statusCode ?? -1
                let data = try await response.value
                throw NetworkError.error(statusCode: statusCode, data: data)
            }
        }
    }
    
    public func download(endpoint: Requestable) async throws -> Data {
        let urlRequest = try endpoint.asURLRequest(config: configuration)
        let response = session.download(urlRequest).serializingData()
        await logger.log(response.response, endpoint)
        
        switch await response.result {
        case .success(let data):
            return data
        case .failure(let error):
            if error.isExplicitlyCancelledError {
                throw NetworkError.cancelled
            } else if error.isSessionTaskError || error.isResponseValidationError {
                throw NetworkError.generic(error)
            } else {
                let statusCode = await response.response.response?.statusCode ?? -1
                let data = try await response.value
                throw NetworkError.error(statusCode: statusCode, data: data)
            }
        }
    }
    
    public func upload(_ data: Data, to url: URL) async throws -> Progress {
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Progress, Error>) in
            self.session.upload(data, to: url).uploadProgress(closure: { progress in
                continuation.resume(returning: progress)
            }).response { response in
                self.logger.log(response, nil)
                switch response.result {
                case .success:
                    break
                case .failure(let error):
                        if let statusCode = error.responseCode {
                            let data = error.downloadResumeData ?? Data()
                            let networkError = NetworkError.error(statusCode: statusCode, data: data)
                            continuation.resume(throwing: networkError)
                        } else {
                            continuation.resume(throwing: NetworkError.generic(error))
                        }
                }
            }
        }
    }
    
    public func upload(multipartFormData: @escaping (MultipartFormData) -> Void,
                       to url: URL) async throws -> Progress {
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Progress, Error>) in
            self.session.upload(multipartFormData: multipartFormData, to: url).uploadProgress(closure: { progress in
                continuation.resume(returning: progress)
            }).response { response in
                switch response.result {
                case .success(_):
                    if let error = response.error {
                        switch true {
                        case error.isExplicitlyCancelledError:
                            continuation.resume(throwing: NetworkError.cancelled)
                        case error.isSessionTaskError || error.isResponseValidationError:
                            continuation.resume(throwing: NetworkError.generic(error))
                        default:
                            let statusCode = response.response?.statusCode ?? -1
                            let data = response.data ?? Data()
                            continuation.resume(throwing: NetworkError.error(statusCode: statusCode, data: data))
                        }
                    }
                case .failure(let error):
                    switch true {
                    case error.isExplicitlyCancelledError:
                        continuation.resume(throwing: NetworkError.cancelled)
                    case error.isSessionTaskError || error.isResponseValidationError:
                        continuation.resume(throwing: NetworkError.generic(error))
                    default:
                        let statusCode = response.response?.statusCode ?? -1
                        let data = response.data ?? Data()
                        continuation.resume(throwing: NetworkError.error(statusCode: statusCode, data: data))
                    }
                }
            }
        }
    }
}
