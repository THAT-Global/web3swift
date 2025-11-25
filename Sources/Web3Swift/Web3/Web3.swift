//
//  Web3.swift
//  THAT
//
//  Created by Bailey Nahi on 11/08/2025.
//

import BigInt
import Foundation
import Web3Core

/// A web3 instance bound to provider. All further functionality is provided under web3.*. namespaces.
public final class Web3: Sendable {
    public let provider: Web3Provider
    public init(provider: Web3Provider) { self.provider = provider }
    
    // MARK: Namespaces (provider-only)
    
    // Stateless namespaces: computed (cheap, no cache needed)
    public var eth: IEth { Eth(provider: provider) }
    public var personal: Personal { Personal(provider: provider) }
    public var txPool: TxPool { TxPool(provider: provider) }
    public var wallet: Web3Wallet { Web3Wallet(provider: provider) }
    public var browserFunctions: BrowserFunctions { BrowserFunctions(provider: provider) }
    
    // Stateful namespace: lazy (keeps the timer & lists)
    // public lazy var eventLoop: EventLoop = EventLoop(provider: provider)
    public func makeEventLoop() -> EventLoop { EventLoop(provider: provider) }
}

/// An arbitrary Web3 object. Is used only to construct provider bound fully functional object by either supplying provider URL
/// or using pre-coded Infura nodes
extension Web3 {
    /// Initialized provider-bound Web3 instance using a provider's URL. Under the hood it performs a synchronous call to get
    /// the Network ID for EIP155 purposes
    public static func new(_ providerURL: URL, network: Network) -> Web3 {
        let provider = Web3HttpProvider(url: providerURL, network: network)
        return Web3(provider: provider)
    }

    /// Initialized Web3 instance bound to Infura's mainnet provider.
    public static func InfuraWeb3(network: Network, accessToken: String? = nil) async throws -> Web3 {
        let infura = try await InfuraProvider(net: network, accessToken: accessToken)
        return Web3(provider: infura)
    }
}
