//
//  Web3HttpProvider.swift
//  THAT
//
//  Created by Bailey Nahi on 11/08/2025.
//


import BigInt
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Web3Core

/// The default http provider.
///
/// PAYMENT-CONNECTIONS-PLAN.md N1: the session is injected, or the process's installed one
/// (`Web3ClientService.installSession` — iOS's payment pool, so every provider shares one connection pool),
/// or, when neither, a session of the provider's own with the 15 s timeout — what every provider had before,
/// and what Android still has. Its credentials go on each request (`requestHeaders`, R-C5), never on the
/// session, which may be shared.
public class Web3HttpProvider: Web3Provider {
    public var url: URL
    public var network: Network
    public var policies: Policies = .auto
    public var attachedKeystoreManager: KeystoreManager?
    public var session: URLSession
    /// The endpoint's basic-auth credentials, if any: `Authorization` on each request this provider sends.
    public let credentials: BasicAuthCredentials?
    
    public init(
        url: URL,
        network: Network,
        keystoreManager: KeystoreManager? = nil,
        credentials: BasicAuthCredentials? = nil,
        session: URLSession? = nil
    ) {
        self.url = url
        self.network = network
        self.attachedKeystoreManager = keystoreManager
        self.credentials = credentials
        if let session {
            self.session = session
        } else if let installed = Web3ClientService.installedSession {
            self.session = installed
        } else {
            self.session = Self.ownSession()
            #if DEBUG
            Web3ClientService.noteProviderWithOwnSession()
            #endif
        }
    }

    public var requestHeaders: [String: String] {
        credentials.map { ["Authorization": $0.authorizationHeader] } ?? [:]
    }

    /// A session of this provider's own — the shape every provider had before N1, and the one a process that
    /// installs no session (Android) still gets.
    public static func ownSession() -> URLSession {
        let config = URLSessionConfiguration.default
        // 15s per RPC call (down from the URLSession default of 60s).
        //
        // A single rewards payment makes ~10 sequential RPC calls
        // (preview, EIP-2612 permit reads, estimateGas, nonce, fees,
        // broadcast). With the default 60s timeout, a single stalled
        // call under poor reception could leave the user staring at
        // the loader for a full minute before failure. 15s is long
        // enough that a healthy Polygon RPC always completes (typical
        // p99 << 2s) but short enough that a flaky connection fails
        // fast and the retry+endpoint-fallback layers above
        // (`RetryPolicy.exponentialPreset` × `performWithRPCFallback`)
        // can recover within the user's patience window.
        //
        // If you bump this back up, also revisit the rewards payment
        // path's overall budget — a 60s/call ceiling × 10 calls × 3
        // retry attempts is well beyond what a checkout user will
        // wait for.
        config.timeoutIntervalForRequest = 15
        return URLSession(configuration: config)
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
