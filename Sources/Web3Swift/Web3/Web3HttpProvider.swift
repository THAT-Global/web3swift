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
