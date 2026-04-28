//
//  Web3SessionResolver.swift
//  web3swift
//

import Web3Core

public final class Web3SessionResolver: Sendable {
    public static let shared = Web3SessionResolver()
    private init() {}

    public func resolve(
        for network: Network,
        keystoreManager: KeystoreManager? = nil,
        task: @Sendable (Web3) async throws -> Void = { _ in }
    ) async throws -> Web3Session {
        let result = try await Web3ClientService.shared.performWithRPCFallback(for: network, keystoreManager: keystoreManager, task: task)
        let web3 = try await Web3ClientService.shared.web3Client(for: network, endpoint: result.endpointUsed, keystoreManager: keystoreManager)
        return Web3Session(web3: web3, endpoint: result.endpointUsed, network: network)
    }
}

public struct Web3Session: Sendable {
    public let web3: Web3
    public let endpoint: String
    public let network: Network

    public init(web3: Web3, endpoint: String, network: Network) {
        self.web3 = web3
        self.endpoint = endpoint
        self.network = network
    }
}
