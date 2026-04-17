//
//  TierRegistry.swift
//  Web3Swift
//
//  Created by Claude on 18/04/2026.
//

import BigInt
import Foundation
import Web3Core

// MARK: - Return Types

/// Tier configuration returned by the `tierConfig()` public getter.
public struct TierConfiguration {
    public let maxTier: UInt8
    public let multiplier1: UInt16
    public let multiplier2: UInt16
    public let multiplier3: UInt16
    public let multiplier4: UInt16

    public init(maxTier: UInt8, multiplier1: UInt16, multiplier2: UInt16, multiplier3: UInt16, multiplier4: UInt16) {
        self.maxTier = maxTier
        self.multiplier1 = multiplier1
        self.multiplier2 = multiplier2
        self.multiplier3 = multiplier3
        self.multiplier4 = multiplier4
    }
}

/// Resolved tier and multiplier returned by `getUserTier`.
public struct UserTierInfo {
    public let tier: UInt8
    public let multiplierBps: UInt16

    public init(tier: UInt8, multiplierBps: UInt16) {
        self.tier = tier
        self.multiplierBps = multiplierBps
    }
}

// MARK: - Implementation

/// Wrapper for the TierRegistry contract — user loyalty tier directory for the THAT Cashback System.
public final class TierRegistry: AccessControlContract {
    public let contract: Contract
    public let contractAddress: EthereumAddress

    public init(contractAddress: EthereumAddress, chainId: BigUInt, abiString: String = Web3.Utils.tierRegistryABI) throws {
        self.contract = try Contract(abiString: abiString, address: contractAddress, chainId: chainId)
        self.contractAddress = contractAddress
    }

    // ═══════════════════════════════════════════════════════════════
    //  MARK: - Write: Admin — OPERATOR_ROLE
    // ═══════════════════════════════════════════════════════════════

    /// Set tier multiplier configuration. All multipliers must be >= 10000 and ascending.
    /// Set maxTier = 0 to disable the feature.
    public func setTierConfig(maxTier: UInt8, mult1: UInt16, mult2: UInt16, mult3: UInt16, mult4: UInt16) throws -> CodableTransaction {
        try contract.createWriteTransaction(method: "setTierConfig", parameters: [maxTier, mult1, mult2, mult3, mult4])
    }

    /// Set a single user's tier.
    public func setUserTier(user: EthereumAddress, tier: UInt8) throws -> CodableTransaction {
        try contract.createWriteTransaction(method: "setUserTier", parameters: [user, tier])
    }

    /// Batch-set user tiers.
    public func setUserTierBatch(users: [EthereumAddress], tiers: [UInt8]) throws -> CodableTransaction {
        try contract.createWriteTransaction(method: "setUserTierBatch", parameters: [users, tiers])
    }

    // ═══════════════════════════════════════════════════════════════
    //  MARK: - Read: Tier & Multiplier Resolution
    // ═══════════════════════════════════════════════════════════════

    /// Resolve a user's current tier and corresponding cashback multiplier.
    /// Returns (0, 10000) for tier 0, unset users, inactive feature, or stale tiers.
    public func getUserTier(user: EthereumAddress, using web3: Web3) async throws -> UserTierInfo {
        let executor = ContractReadExecutor(contract: contract, web3: web3)
        let result = try await executor.call(method: "getUserTier", parameters: [user])

        guard let tier = result["0"] as? BigUInt,
              let multiplierBps = result["1"] as? BigUInt else {
            throw Web3Error.processingError(desc: "getUserTier returned unexpected format")
        }

        return UserTierInfo(tier: UInt8(tier), multiplierBps: UInt16(multiplierBps))
    }

    /// Read a user's stored tier value (raw mapping value, not clamped).
    public func userTier(user: EthereumAddress, using web3: Web3) async throws -> UInt8 {
        let executor = ContractReadExecutor(contract: contract, web3: web3)
        let result: BigUInt = try await executor.call(method: "userTier", parameters: [user])
        return UInt8(result)
    }

    /// Current tier configuration (multipliers and max active tier).
    public func tierConfig(using web3: Web3) async throws -> TierConfiguration {
        let executor = ContractReadExecutor(contract: contract, web3: web3)
        let result = try await executor.call(method: "tierConfig")

        guard let maxTier = result["0"] as? BigUInt,
              let mult1 = result["1"] as? BigUInt,
              let mult2 = result["2"] as? BigUInt,
              let mult3 = result["3"] as? BigUInt,
              let mult4 = result["4"] as? BigUInt else {
            throw Web3Error.processingError(desc: "tierConfig returned unexpected format")
        }

        return TierConfiguration(
            maxTier: UInt8(maxTier),
            multiplier1: UInt16(mult1),
            multiplier2: UInt16(mult2),
            multiplier3: UInt16(mult3),
            multiplier4: UInt16(mult4)
        )
    }

    // ═══════════════════════════════════════════════════════════════
    //  MARK: - Read: Pagination
    // ═══════════════════════════════════════════════════════════════

    /// Total number of users who have ever been assigned a non-zero tier.
    public func tieredUserCount(using web3: Web3) async throws -> BigUInt {
        let executor = ContractReadExecutor(contract: contract, web3: web3)
        return try await executor.call(method: "tieredUserCount")
    }

    /// Paginated list of tiered user addresses.
    public func allTieredUsers(from: BigUInt, count: BigUInt, using web3: Web3) async throws -> [EthereumAddress] {
        let executor = ContractReadExecutor(contract: contract, web3: web3)
        let result = try await executor.call(method: "allTieredUsers", parameters: [from, count])
        guard let addresses = result["0"] as? [EthereumAddress] else {
            throw Web3Error.processingError(desc: "allTieredUsers returned unexpected format")
        }
        return addresses
    }

    // ═══════════════════════════════════════════════════════════════
    //  MARK: - Read: Batch
    // ═══════════════════════════════════════════════════════════════

    /// Bulk-read user tiers for a list of addresses.
    public func getUserTierBatch(users: [EthereumAddress], using web3: Web3) async throws -> [UInt8] {
        let executor = ContractReadExecutor(contract: contract, web3: web3)
        let result = try await executor.call(method: "getUserTierBatch", parameters: [users])
        guard let tiers = result["0"] as? [BigUInt] else {
            throw Web3Error.processingError(desc: "getUserTierBatch returned unexpected format")
        }
        return tiers.map { UInt8($0) }
    }
}
