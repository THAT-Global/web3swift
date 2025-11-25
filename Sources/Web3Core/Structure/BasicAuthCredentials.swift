//
//  BasicAuthCredentials.swift
//  THAT
//
//  Created by Bailey Nahi on 06/08/2025.
//

/// Can be used to add basic auth headers to custom networks, e.g.:
/// let provider = try? Web3HttpProvider(network: .Polygon, credentials: .init(username: "", password: ""))
public struct BasicAuthCredentials {
    public let username: String
    public let password: String
    
    public init(username: String, password: String) {
        self.username = username
        self.password = password
    }
    
    public var authorizationHeader: String {
        let credential = "\(username):\(password)"
        guard let data = credential.data(using: .utf8) else { return "" }
        return "Basic \(data.base64EncodedString())"
    }
}
