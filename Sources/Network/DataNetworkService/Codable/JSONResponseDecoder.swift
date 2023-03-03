//
//  File.swift
//
//
//  Created by LEMIN DAHOVICH on 19.01.2023.
//

import Foundation
import NetworkInterface

public class JSONResponseDecoder: ResponseDecoder {
    
    private let jsonDecoder = JSONDecoder()
    
    public init() {}
    
    public func decode<T: Decodable>(_ data: Data) throws -> T {
            return try jsonDecoder.decode(T.self, from: data)
    }
    
    public func decode<T: Decodable>(_ data: Data, keyPath: String) throws -> T {
        let keyPathDecoder = KeyPathDecoder(keyPath)
        return try keyPathDecoder.decode(T.self, from: data)
    }
}
