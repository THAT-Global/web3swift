//
//  Web3ClientService.swift
//  web3swift
//

import Foundation
import Web3Core

public actor EndpointManager {
    private var registeredEndpoints: [UInt: [String]] = [:]
    private var preferredEndpoint: [UInt: String] = [:]

    public func register(for network: Network, endpoints: [String]) {
        registeredEndpoints[network.chainIDAsUInt] = endpoints
    }

    public func endpoints(for network: Network) -> [String] {
        registeredEndpoints[network.chainIDAsUInt] ?? []
    }

    public func preferred(for network: Network) -> String? {
        preferredEndpoint[network.chainIDAsUInt] ?? registeredEndpoints[network.chainIDAsUInt]?.first
    }

    public func setPreferred(for network: Network, endpoint: String) {
        preferredEndpoint[network.chainIDAsUInt] = endpoint
    }

    func orderedEndpoints(for network: Network) -> [String] {
        let all = endpoints(for: network)
        if let pref = preferredEndpoint[network.chainIDAsUInt] {
            return [pref] + all.filter { $0 != pref }
        }
        return all
    }
}

public enum Web3ClientFactory {
    public static func make(
        network: Network,
        endpoint: String,
        keystoreManager: KeystoreManager? = nil,
        credentials: BasicAuthCredentials? = nil
    ) throws -> Web3 {
        guard let url = URL(string: endpoint) else { throw Web3ClientServiceError.invalidURLError }
        let provider = Web3HttpProvider(url: url, network: network, keystoreManager: keystoreManager, credentials: credentials)
        return Web3(provider: provider)
    }
}

public actor Web3ClientService {
    public static let shared = Web3ClientService()
    private init() {}

    public let endpointManager = EndpointManager()
    private var cache: [String: (web3: Web3, timestamp: Date)] = [:]
    private let cacheExpiration: TimeInterval = 604_800

    public func registerEndpoints(_ endpoints: [String], for network: Network) async {
        await endpointManager.register(for: network, endpoints: endpoints)
    }

    public func web3Client(
        for network: Network,
        keystoreManager: KeystoreManager? = nil,
        credentials: BasicAuthCredentials? = nil
    ) async throws -> Web3 {
        guard let endpoint = await endpointManager.preferred(for: network) else {
            throw Web3ClientServiceError.invalidURLError
        }
        return try await createWeb3(for: network, endpoint: endpoint, keystoreManager: keystoreManager, credentials: credentials)
    }

    public func web3Client(
        for network: Network,
        endpoint: String,
        keystoreManager: KeystoreManager? = nil,
        credentials: BasicAuthCredentials? = nil
    ) async throws -> Web3 {
        try await createWeb3(for: network, endpoint: endpoint, keystoreManager: keystoreManager, credentials: credentials)
    }

    private func createWeb3(
        for network: Network,
        endpoint: String,
        keystoreManager: KeystoreManager?,
        credentials: BasicAuthCredentials?
    ) async throws -> Web3 {
        let key = cacheKey(endpoint, keystoreManager, credentials)
        if let entry = cache[key], Date().timeIntervalSince(entry.timestamp) <= cacheExpiration {
            return entry.web3
        }

        guard let url = URL(string: endpoint) else {
            throw Web3ClientServiceError.invalidURLError
        }

        let provider = Web3HttpProvider(url: url, network: network, keystoreManager: keystoreManager, credentials: credentials)
        let client = Web3(provider: provider)
        cache[key] = (web3: client, timestamp: Date())
        return client
    }

    public func performWithRPCFallback<T: Sendable>(
        for network: Network,
        keystoreManager: KeystoreManager? = nil,
        credentials: BasicAuthCredentials? = nil,
        task: @Sendable (Web3) async throws -> T
    ) async throws -> RPCExecutionResult<T> {
        let endpoints = await endpointManager.orderedEndpoints(for: network)
        guard !endpoints.isEmpty else { throw Web3ClientServiceError.invalidURLError }

        var lastError: Error = Web3ClientServiceError.unrecoverableRPCError
        for (index, endpoint) in endpoints.enumerated() {
            print("Trying endpoint[\(index)]: \(endpoint)")
            do {
                let web3 = try await web3Client(for: network, endpoint: endpoint, keystoreManager: keystoreManager, credentials: credentials)
                let result = try await task(web3)
                await endpointManager.setPreferred(for: network, endpoint: endpoint)
                return RPCExecutionResult(result: result, endpointUsed: endpoint, web3Used: web3)
            } catch {
                lastError = error
                if Self.isDeterministicError(error) {
                    print("RPC deterministic failure on endpoint: \(endpoint). Error: \(error.localizedDescription)")
                    throw error
                }
                print("RPC call failed on endpoint: \(endpoint). Error: \(error.localizedDescription)")
                continue
            }
        }

        throw lastError
    }

    private static func isDeterministicError(_ error: Error) -> Bool {
        if let web3Error = error as? Web3Error {
            switch web3Error {
            case .rpcError(let rpcError):
                let msg = rpcError.message.lowercased()
                if msg.contains("revert") || msg.contains("execution reverted") { return true }
                if msg.contains("insufficient") { return true }
                if msg.contains("nonce") { return true }
                if msg.contains("gas") && (msg.contains("low") || msg.contains("underpriced") || msg.contains("exceeds")) { return true }
                if msg.contains("already known") || msg.contains("replacement") { return true }
                return false
            case .nodeError(let desc):
                let msg = desc.lowercased()
                if msg.contains("revert") || msg.contains("execution reverted") { return true }
                if msg.contains("insufficient") { return true }
                if msg.contains("nonce") { return true }
                if msg.contains("gas") && (msg.contains("low") || msg.contains("underpriced") || msg.contains("exceeds")) { return true }
                if msg.contains("already known") || msg.contains("replacement") { return true }
                return false
            case .revert, .revertCustom:
                return true
            case .inputError, .contractError:
                return true
            default:
                return false
            }
        }
        return false
    }

    private func cacheKey(_ endpoint: String, _ keystoreManager: KeystoreManager?, _ credentials: BasicAuthCredentials?) -> String {
        let address = keystoreManager?.addresses?.first?.address ?? "no_keystore"
        let authHash = credentials.map { "\($0.username):\($0.password)".hashValue } ?? 0
        return "web3Client_\(endpoint)_\(address)_auth:\(authHash)"
    }
}

public struct RPCExecutionResult<T: Sendable>: Sendable {
    public let result: T
    public let endpointUsed: String
    public let web3Used: Web3

    public init(result: T, endpointUsed: String, web3Used: Web3) {
        self.result = result
        self.endpointUsed = endpointUsed
        self.web3Used = web3Used
    }
}

public enum Web3ClientServiceError: Error {
    case invalidURLError
    case providerInitializationError
    case unrecoverableRPCError
}
