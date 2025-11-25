//
//  Web3HttpProvider.swift
//  THAT
//
//  Created by Bailey Nahi on 11/08/2025.
//


import BigInt
import Foundation
import Web3Core

/// The default http provider.
public class Web3HttpProvider: Web3Provider {
    public var url: URL
    public var network: Network
    public var policies: Policies = .auto
    public var attachedKeystoreManager: KeystoreManager?
    public var session: URLSession
    
    public init(
        url: URL,
        network: Network,
        keystoreManager: KeystoreManager? = nil,
        credentials: BasicAuthCredentials? = nil
    ) {
        self.url = url
        self.network = network
        self.attachedKeystoreManager = keystoreManager
        self.session = {
            let config = URLSessionConfiguration.default
            if let credentials { config.httpAdditionalHeaders = ["Authorization": credentials.authorizationHeader] }
            return URLSession(configuration: config)
        }()
    }
    
    public convenience init(
        url: URL,
        keystoreManager: KeystoreManager? = nil,
        credentials: BasicAuthCredentials? = nil
    ) async throws {
        guard url.scheme == "http" || url.scheme == "https" else {
            throw Web3Error.inputError(desc: "Web3HttpProvider endpoint must have scheme http or https. Given scheme \(url.scheme ?? "none"). \(url.absoluteString)")
        }
        let session = URLSession(configuration: URLSessionConfiguration.default)
        let response: String = try await APIRequest.send(APIRequest.getNetwork.call, parameters: [], to: url, session: session).result
        let chainId: UInt
        if response.hasHexPrefix(), let num = BigUInt(response, radix: 16) {
            chainId = UInt(num)
        } else if let num = UInt(response) {
            chainId = num
        } else {
            // Get network succeeded but can't be parsed to a valid chain id.
            throw Web3Error.processingError(desc: "Invalid chain ID response.")
        }
        
        // TODO: Handle custom network creations here too
        guard let resolvedNetwork = Network.fromInt(chainId) else {
            throw Web3Error.processingError(desc: "Unrecognized network ID: \(chainId)")
        }
        
        self.init(url: url, network: resolvedNetwork, keystoreManager: keystoreManager, credentials: credentials)
    }
}
