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

    /// The endpoint to try first: the one that last succeeded, while it is still registered — a preference
    /// for an endpoint the list no longer holds (a rotated key) is ignored, as payments-core's send ladder
    /// ignores one (PAYMENT-CONNECTIONS-PLAN.md N3) — else the first registered.
    public func preferred(for network: Network) -> String? {
        let registered = registeredEndpoints[network.chainIDAsUInt] ?? []
        if let pref = preferredEndpoint[network.chainIDAsUInt], registered.contains(pref) { return pref }
        return registered.first
    }

    public func setPreferred(for network: Network, endpoint: String) {
        preferredEndpoint[network.chainIDAsUInt] = endpoint
    }

    func orderedEndpoints(for network: Network) -> [String] {
        let all = endpoints(for: network)
        if let pref = preferredEndpoint[network.chainIDAsUInt], all.contains(pref) {
            return [pref] + all.filter { $0 != pref }
        }
        return all
    }
}

public actor Web3ClientService {
    public static let shared = Web3ClientService()
    private init() {}

    private static let log = LogChannel(subsystem: "web3swift", category: "Web3ClientService")
    private let endpointManager = EndpointManager()
    private var cache: [String: (web3: Web3, timestamp: Date)] = [:]
    private var cacheOrder: [String] = []
    private let cacheExpiration: TimeInterval = 604_800
    private let cacheCapacity = 32

    // MARK: - The installed session (PAYMENT-CONNECTIONS-PLAN.md N1)

    /// One session for the process, which every client this service creates rides — and every
    /// `Web3HttpProvider` built with no session of its own. iOS installs its payment pool at launch, before any
    /// client is made, so a payment's requests share one connection pool; Android installs nothing and keeps a
    /// session per provider, as before. Synchronous and lock-guarded: the install happens in a synchronous
    /// bootstrap that cannot await this actor, and the read happens in every provider's init.
    private static let sessionLock = NSLock()
    nonisolated(unsafe) private static var _installedSession: URLSession?
    nonisolated(unsafe) private static var _providersWithOwnSession = 0

    public nonisolated static var installedSession: URLSession? {
        sessionLock.withLock { _installedSession }
    }

    public nonisolated static func installSession(_ session: URLSession) {
        sessionLock.withLock { _installedSession = session }
    }

    #if DEBUG
    /// Providers that built a session of their own because nothing was installed when they were made. On iOS
    /// that is a client created BEFORE the pool — the launch-order fault the app's T3 pins at zero; on a host
    /// that installs nothing (Android, the fork's own tests) it is every provider.
    public nonisolated static var providersWithOwnSession: Int {
        sessionLock.withLock { _providersWithOwnSession }
    }

    /// Tests only: nothing installed, nothing counted.
    public nonisolated static func resetInstalledSessionForTesting() {
        sessionLock.withLock { _installedSession = nil; _providersWithOwnSession = 0 }
    }
    #endif

    nonisolated static func noteProviderWithOwnSession() {
        sessionLock.withLock { _providersWithOwnSession += 1 }
    }

    // MARK: - Endpoints

    public func registerEndpoints(_ endpoints: [String], for network: Network) async {
        await endpointManager.register(for: network, endpoints: endpoints)
    }

    public func endpoints(for network: Network) async -> [String] {
        await endpointManager.endpoints(for: network)
    }

    /// N3 — the endpoint tried first for a network: the last success while it is registered, else the first.
    /// The app's send ladder reads and writes this same preference, so a read's success puts an endpoint
    /// first for the next send and a send's success does the same for the next read (one preference, not two).
    public func preferredEndpoint(for network: Network) async -> String? {
        await endpointManager.preferred(for: network)
    }

    public func setPreferredEndpoint(_ endpoint: String, for network: Network) async {
        await endpointManager.setPreferred(for: network, endpoint: endpoint)
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
        insertCache(key: key, web3: client)
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
            Self.log.debug("Trying endpoint[\(index)]: \(endpoint)")
            do {
                let web3 = try await web3Client(for: network, endpoint: endpoint, keystoreManager: keystoreManager, credentials: credentials)
                let result = try await task(web3)
                await endpointManager.setPreferred(for: network, endpoint: endpoint)
                return RPCExecutionResult(result: result, endpointUsed: endpoint, web3Used: web3)
            } catch {
                lastError = error
                if Self.isDeterministicError(error) {
                    Self.log.error("Deterministic failure on endpoint: \(endpoint). Error: \(error.localizedDescription)")
                    throw error
                }
                Self.log.warning("RPC call failed on endpoint: \(endpoint). Error: \(error.localizedDescription)")
                continue
            }
        }

        throw lastError
    }

    // MARK: - Cache

    private func insertCache(key: String, web3: Web3) {
        if cache[key] != nil {
            cacheOrder.removeAll { $0 == key }
        } else if cache.count >= cacheCapacity, let oldest = cacheOrder.first {
            cache.removeValue(forKey: oldest)
            cacheOrder.removeFirst()
        }
        cache[key] = (web3: web3, timestamp: Date())
        cacheOrder.append(key)
    }

    private func cacheKey(_ endpoint: String, _ keystoreManager: KeystoreManager?, _ credentials: BasicAuthCredentials?) -> String {
        let address = (keystoreManager?.addresses?.first?.address ?? "no_keystore").lowercased()
        let authHash = credentials.map { "\($0.username):\($0.password)".hashValue } ?? 0
        return "web3Client_\(endpoint)_\(address)_auth:\(authHash)"
    }

    // MARK: - Error classification

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
