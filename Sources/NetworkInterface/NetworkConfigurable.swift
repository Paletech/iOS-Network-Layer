//
//  File.swift
//  
//
//  Created by LEMIN DAHOVICH on 01.03.2023.

import Foundation

public protocol NetworkConfigurable {
    var baseURL: URL { get }
    var headers: [String: String] { get }
    var queryParameters: [String: String] { get }
}
