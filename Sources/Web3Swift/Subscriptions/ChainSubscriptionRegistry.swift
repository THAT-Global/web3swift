//
//  ChainSubscriptionRegistry.swift
//  web3swift
//
//  Registry of per-chain subscription centers, keyed by chain ID.
//

import Foundation

#if !os(Android)
@MainActor
public final class ChainSubscriptionRegistry {
    public static let shared = ChainSubscriptionRegistry()
    private var centers: [Int: ChainLiveCenter] = [:]
    private init() {}

    @discardableResult
    public func ensureConfigured(
        chainId: Int,
        wssURL: URL,
        hashesOnly: Bool = false,
        includeRemoved: Bool = false,
        onAffectedWallets: @escaping (Set<String>) -> Void,
        onMinedTx: ((MinedTx) -> Void)? = nil
    ) -> ChainLiveCenter {
        let c = ensure(chainId: chainId, wssURL: wssURL)
        c.hashesOnly = hashesOnly
        c.includeRemoved = includeRemoved
        c.onAffectedWallets = onAffectedWallets
        c.onMinedTx = onMinedTx
        c.start()
        return c
    }

    @discardableResult
    public func ensure(chainId: Int, wssURL: URL) -> ChainLiveCenter {
        if let center = centers[chainId] { return center }
        let center = ChainLiveCenter(chainId: chainId, wssURL: wssURL)
        centers[chainId] = center
        return center
    }

    @discardableResult
    public func ensureAndWatch(chainId: Int, wssURL: URL, from: [String], to: [String]) -> ChainLiveCenter {
        let center = ensure(chainId: chainId, wssURL: wssURL)
        center.setAddressWatch(from: from, to: to)
        center.start()
        return center
    }

    public func center(chainId: Int) -> ChainLiveCenter? { centers[chainId] }

    public func mirrorKeys() -> [Int] { Array(centers.keys) }

    public func remove(chainId: Int) {
        centers[chainId]?.stop()
        centers[chainId] = nil
    }
}
#endif // !os(Android)
