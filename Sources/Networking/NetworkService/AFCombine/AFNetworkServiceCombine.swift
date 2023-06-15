import Alamofire
import Foundation
import NetworkInterface
import Combine

open class AFNetworkServiceCombine: AFNetworkServiceCombineProtocol {
    
    private let session: Session
    private let logger: Loger
    private let configuration: NetworkConfigurable

    public init(session: Session,
                logger: Loger = DEBUGLog(),
                configuration: NetworkConfigurable) {
        self.session = session
        self.logger = logger
        self.configuration = configuration
    }
    
    open func request(endpoint: Requestable) -> AnyPublisher<Data, Error> {
        do {
            let urlRequest = try endpoint.asURLRequest(config: configuration)
            return session
                .request(urlRequest)
                .publishData()
                .tryMap { [weak self] response -> Data in
                    self?.logger.log(response, endpoint)
                    guard let data = response.data,
                          let statusCode = response.response?.statusCode else {
                        throw NetworkError.notConnectedToInternet
                    }
                    
                    if let statusCode = response.response?.statusCode,
                       let networkStatusCode = NetworkStatusCode(rawValue: statusCode),
                       networkStatusCode.isAcceptable {
                        return data
                    } else {
                        throw NetworkError.error(statusCode: statusCode, data: data)
                    }
                }
                .mapError { error -> Error in
                    if let afError = error as? AFError {
                        return afError.underlyingError ?? NetworkError.generic(error)
                    } else if let networkError = error as? NetworkError {
                        return networkError
                    } else {
                        return NetworkError.generic(error)
                    }
                }
                .eraseToAnyPublisher()
        } catch {
            return Fail(error: NetworkError.urlGeneration).eraseToAnyPublisher()
        }
    }
    
    open func download(endpoint: Requestable) -> AnyPublisher<Data, Error> {
        do {
            let urlRequest = try endpoint.asURLRequest(config: configuration)
            return session
                .download(urlRequest)
                .publishData()
                .tryMap { [weak self] response -> Data in
                    self?.logger.log(response, endpoint)
                    guard let destinationURL = response.fileURL else {
                        throw DataTransferError.noResponse
                    }
                    let data = try Data(contentsOf: destinationURL)
                    guard let statusCode = response.response?.statusCode else {
                        throw NetworkError.notConnectedToInternet
                    }
                    if let statusCode = response.response?.statusCode,
                       let networkStatusCode = NetworkStatusCode(rawValue: statusCode),
                       networkStatusCode.isAcceptable {
                        return data
                    } else {
                        throw NetworkError.error(statusCode: statusCode, data: data)
                    }
                }
                .mapError { error -> Error in
                    if let afError = error as? AFError {
                        return afError.underlyingError ?? NetworkError.generic(error)
                    } else if let networkError = error as? NetworkError {
                        return networkError
                    } else {
                        return NetworkError.generic(error)
                    }
                }
                .eraseToAnyPublisher()
        } catch {
            return Fail(error: NetworkError.urlGeneration).eraseToAnyPublisher()
        }
    }
    
    open func upload(
        endpoint: Requestable,
        _ data: Data
    ) -> AnyPublisher<(Progress, Data?), Error> {
        return handleUpload(endpoint: endpoint) { urlRequest in
            session.upload(data, with: urlRequest)
        }
    }
    
    open func upload(
        endpoint: Requestable,
        multipartFormData: @escaping (MultipartFormData) -> Void
    ) -> AnyPublisher<(Progress, Data?), Error> {
        return handleUpload(endpoint: endpoint) { urlRequest in
            return session.upload(multipartFormData: multipartFormData, with: urlRequest)
        }
    }
}

// MARK: - Private

extension AFNetworkServiceCombine {
    private func handleUpload(
        endpoint: Requestable,
        uploadMethod: (URLRequest) throws -> UploadRequest
    ) -> AnyPublisher<(Progress, Data?), Error> {
        let progressDataSubject = PassthroughSubject<(Progress, Data?), Error>()
        
        do {
            let urlRequest = try endpoint.asURLRequest(config: configuration)
            let uploadRequest = try uploadMethod(urlRequest)
            
            uploadRequest
                .uploadProgress { progress in
                    progressDataSubject.send((progress, nil))
                }
                .response { response in
                    self.logger.log(response, endpoint)
                    switch response.result {
                    case .success(let data):
                        progressDataSubject.send((Progress(totalUnitCount: 1), data))
                        progressDataSubject.send(completion: .finished)
                    case .failure(let error):
                        if let underlyingError = error.underlyingError as? URLError,
                           underlyingError.code == .notConnectedToInternet {
                            progressDataSubject.send(completion: .failure(NetworkError.notConnectedToInternet))
                        } else {
                            let data = response.data ?? Data()
                            let statusCode = error.responseCode ?? 400
                            let networkError = NetworkError.error(statusCode: statusCode, data: data)
                            progressDataSubject.send(completion: .failure(networkError))
                        }
                    }
                }
        } catch {
            progressDataSubject.send(completion: .failure(NetworkError.urlGeneration))
        }
        
        return progressDataSubject.eraseToAnyPublisher()
    }
}