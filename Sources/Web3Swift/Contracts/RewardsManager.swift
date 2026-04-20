//
//  RewardsManager.swift
//  Web3Swift
//
//  Created by Claude on 17/04/2026.
//

import BigInt
import Foundation
import Web3Core

// MARK: - Return Types

/// Payment preview returned by `previewPayment`.
public struct PaymentPreview: Codable, Sendable {
    public let fromWallet: BigUInt
    public let fromRewards: BigUInt
    public let estimatedCashback: BigUInt
    public let cashbackActive: Bool
    public let cashbackInactiveReason: CashbackInactiveReason

    public init(fromWallet: BigUInt, fromRewards: BigUInt, estimatedCashback: BigUInt, cashbackActive: Bool, cashbackInactiveReason: CashbackInactiveReason) {
        self.fromWallet = fromWallet
        self.fromRewards = fromRewards
        self.estimatedCashback = estimatedCashback
        self.cashbackActive = cashbackActive
        self.cashbackInactiveReason = cashbackInactiveReason
    }
}

/// User reward balances returned by `getUserBalances`.
public struct UserRewardBalances: Codable, Sendable {
    public let spendable: BigUInt
    public let pending: BigUInt
    public let nextVesting: UInt64

    public init(spendable: BigUInt, pending: BigUInt, nextVesting: UInt64) {
        self.spendable = spendable
        self.pending = pending
        self.nextVesting = nextVesting
    }
}

/// System configuration parameters and flags returned by `getSystemConfig`.
public struct RewardsSystemConfig: Codable, Sendable {
    public let baseRateBps: UInt16
    public let rateCapBps: UInt16
    public let rateScalingEnabled: Bool
    public let rewardsBaseline: BigUInt
    public let cooldownSeconds: UInt64
    public let vestingDuration: UInt64
    public let epochLength: UInt64
    public let inactivityThreshold: UInt64
    public let cashbackPaused: Bool
    public let emergencyPaused: Bool
    public let defaultMaxPerTx: BigUInt
    public let defaultUserDailyCap: BigUInt
    public let defaultMerchantDailyCap: BigUInt
    public let defaultPairDailyCap: BigUInt
    public let globalDailyCap: BigUInt
    public let defaultMinPayment: BigUInt
}

/// Live system metrics returned by `getSystemMetrics`.
public struct RewardsSystemMetrics: Codable, Sendable {
    public let totalCashbackDistributed: BigUInt
    public let totalEligibleVolume: BigUInt
    public let totalPaymentCount: BigUInt
    public let rewardsBucket: BigUInt
    public let totalAllocatedRewards: BigUInt
}

/// Batch merchant overrides returned by `getMerchantOverridesBatch`.
public struct MerchantOverridesBatch: Codable, Sendable {
    public let customRate: [BigUInt]
    public let maxPerTx: [BigUInt]
    public let dailyCap: [BigUInt]
    public let pairDailyCap: [BigUInt]
    public let minPayment: [BigUInt]
}

/// User status enum matching the Solidity `UserStatus` enum.
public enum RewardsUserStatus: UInt8, Codable, Sendable {
    case ok = 0
    case cashbackPaused = 1
    case frozen = 2
    case blacklisted = 3
    case emergencyPaused = 4

    public init(rawValue: UInt8) {
        switch rawValue {
        case 0: self = .ok
        case 1: self = .cashbackPaused
        case 2: self = .frozen
        case 3: self = .blacklisted
        case 4: self = .emergencyPaused
        default: self = .ok
        }
    }
}

/// Cashback inactive reason enum matching the Solidity `CashbackInactiveReason` enum.
public enum CashbackInactiveReason: UInt8, Codable, Sendable {
    case none = 0
    case recipientNotMerchant = 1
    case notEarnEligible = 2
    case cooldownActive = 3
    case capsExceeded = 4
    case userBlacklisted = 5
    case userFrozen = 6
    case cashbackPaused = 7
    case poolEmpty = 8

    public init(rawValue: UInt8) {
        switch rawValue {
        case 0: self = .none
        case 1: self = .recipientNotMerchant
        case 2: self = .notEarnEligible
        case 3: self = .cooldownActive
        case 4: self = .capsExceeded
        case 5: self = .userBlacklisted
        case 6: self = .userFrozen
        case 7: self = .cashbackPaused
        case 8: self = .poolEmpty
        default: self = .none
        }
    }
}

// MARK: - Implementation

public final class RewardsManager: AccessControlContract {
    public let contract: Contract
    public let contractAddress: EthereumAddress

    public init(contractAddress: EthereumAddress, chainId: BigUInt, abiString: String = Web3.Utils.rewardsManagerABI) throws {
        self.contract = try Contract(abiString: abiString, address: contractAddress, chainId: chainId)
        self.contractAddress = contractAddress
    }

    // ═══════════════════════════════════════════════════════════════
    //  MARK: - Write: Payment (Permissionless)
    // ═══════════════════════════════════════════════════════════════

    /// Pay a recipient with prior ERC-20 approval. Cashback accrues automatically.
    public func payWithCashback(recipient: EthereumAddress, totalAmount: BigUInt, useRewardsFirst: Bool, clientSig: Data) throws -> CodableTransaction {
        try contract.createWriteTransaction(method: "payWithCashback", parameters: [recipient, totalAmount, useRewardsFirst, clientSig])
    }

    /// Pay with EIP-2612 permit (single transaction — no separate approve needed).
    public func payWithCashbackWithPermit(
        recipient: EthereumAddress,
        totalAmount: BigUInt,
        useRewardsFirst: Bool,
        deadline: BigUInt,
        v: UInt8,
        r: Data,
        s: Data,
        clientSig: Data
    ) throws -> CodableTransaction {
        try contract.createWriteTransaction(method: "payWithCashbackWithPermit", parameters: [recipient, totalAmount, useRewardsFirst, deadline, v, r, s, clientSig])
    }

    /// Pay entirely from spendable rewards. Merchant must be spend-eligible.
    public func spendRewardsOnly(merchant: EthereumAddress, amount: BigUInt, clientSig: Data) throws -> CodableTransaction {
        try contract.createWriteTransaction(method: "spendRewardsOnly", parameters: [merchant, amount, clientSig])
    }

    // ═══════════════════════════════════════════════════════════════
    //  MARK: - Write: Settlement (Permissionless)
    // ═══════════════════════════════════════════════════════════════

    /// Manually trigger vesting settlement for the caller's own rewards.
    public func settleSelf() throws -> CodableTransaction {
        try contract.createWriteTransaction(method: "settleSelf")
    }

    /// Settle matured rewards for any user (permissionless).
    public func settle(user: EthereumAddress) throws -> CodableTransaction {
        try contract.createWriteTransaction(method: "settle", parameters: [user])
    }

    // ═══════════════════════════════════════════════════════════════
    //  MARK: - Write: Gifting (Permissionless)
    // ═══════════════════════════════════════════════════════════════

    /// Gift rewards to another user (sender-funded, requires prior approve).
    public func giftRewards(recipient: EthereumAddress, amount: BigUInt) throws -> CodableTransaction {
        try contract.createWriteTransaction(method: "giftRewards", parameters: [recipient, amount])
    }

    /// Gift rewards with EIP-2612 permit (single tx).
    public func giftRewardsWithPermit(
        recipient: EthereumAddress,
        amount: BigUInt,
        deadline: BigUInt,
        v: UInt8,
        r: Data,
        s: Data
    ) throws -> CodableTransaction {
        try contract.createWriteTransaction(method: "giftRewardsWithPermit", parameters: [recipient, amount, deadline, v, r, s])
    }

    // ═══════════════════════════════════════════════════════════════
    //  MARK: - Write: Refund (Merchant-only)
    // ═══════════════════════════════════════════════════════════════

    /// Merchant-initiated full refund for a recorded payment.
    public func refundPayment(paymentId: BigUInt) throws -> CodableTransaction {
        try contract.createWriteTransaction(method: "refundPayment", parameters: [paymentId])
    }

    // ═══════════════════════════════════════════════════════════════
    //  MARK: - Write: Expiry (Permissionless)
    // ═══════════════════════════════════════════════════════════════

    /// Expire an inactive user's rewards. Reverts if user is still active.
    public func expireInactive(user: EthereumAddress) throws -> CodableTransaction {
        try contract.createWriteTransaction(method: "expireInactive", parameters: [user])
    }

    /// Batch expiry — skips still-active users (no revert).
    public func expireInactiveBatch(users: [EthereumAddress]) throws -> CodableTransaction {
        try contract.createWriteTransaction(method: "expireInactiveBatch", parameters: [users])
    }

    // ═══════════════════════════════════════════════════════════════
    //  MARK: - Write: Admin — SECURITY_ROLE
    // ═══════════════════════════════════════════════════════════════

    /// Pause/unpause cashback accrual system-wide.
    public func setCashbackPaused(_ paused: Bool) throws -> CodableTransaction {
        try contract.createWriteTransaction(method: "setCashbackPaused", parameters: [paused])
    }

    /// Emergency pause/unpause the entire contract.
    public func setEmergencyPaused(_ paused: Bool) throws -> CodableTransaction {
        try contract.createWriteTransaction(method: "setEmergencyPaused", parameters: [paused])
    }

    /// Freeze/unfreeze a user's rewards (can still pay with wallet, but no accrual/spend).
    public func setUserFrozen(user: EthereumAddress, frozen: Bool) throws -> CodableTransaction {
        try contract.createWriteTransaction(method: "setUserFrozen", parameters: [user, frozen])
    }

    /// Blacklist/unblacklist a user. Blacklisting implies freeze.
    public func setUserBlacklisted(user: EthereumAddress, blacklisted: Bool) throws -> CodableTransaction {
        try contract.createWriteTransaction(method: "setUserBlacklisted", parameters: [user, blacklisted])
    }

    /// Slash a user's rewards. Irreversible. Returns slashed tokens to rewardsBucket.
    public func slash(user: EthereumAddress, spendableAmount: BigUInt, pendingAmount: BigUInt) throws -> CodableTransaction {
        try contract.createWriteTransaction(method: "slash", parameters: [user, spendableAmount, pendingAmount])
    }

    // ═══════════════════════════════════════════════════════════════
    //  MARK: - Write: Admin — OPERATOR_ROLE: Rates
    // ═══════════════════════════════════════════════════════════════

    /// Set global base cashback rate in basis points (100 bps = 1%).
    public func setBaseRateBps(_ bps: BigUInt) throws -> CodableTransaction {
        try contract.createWriteTransaction(method: "setBaseRateBps", parameters: [bps])
    }

    /// Set per-merchant custom rate override (0 = use base rate).
    public func setMerchantCustomRate(merchant: EthereumAddress, bps: BigUInt) throws -> CodableTransaction {
        try contract.createWriteTransaction(method: "setMerchantCustomRate", parameters: [merchant, bps])
    }

    /// Enable/disable four-tier rate scaling based on pool health.
    public func toggleRateScaling(enabled: Bool) throws -> CodableTransaction {
        try contract.createWriteTransaction(method: "toggleRateScaling", parameters: [enabled])
    }

    /// Set the "fully funded" baseline for rate scaling.
    public func setRewardsBaseline(_ baseline: BigUInt) throws -> CodableTransaction {
        try contract.createWriteTransaction(method: "setRewardsBaseline", parameters: [baseline])
    }

    // ═══════════════════════════════════════════════════════════════
    //  MARK: - Write: Admin — OPERATOR_ROLE: Caps
    // ═══════════════════════════════════════════════════════════════

    /// Set default per-transaction cashback cap.
    public func setDefaultMaxPerTx(_ cap: BigUInt) throws -> CodableTransaction {
        try contract.createWriteTransaction(method: "setDefaultMaxPerTx", parameters: [cap])
    }

    /// Set per-merchant per-transaction cap override.
    public func setMerchantMaxPerTx(merchant: EthereumAddress, cap: BigUInt) throws -> CodableTransaction {
        try contract.createWriteTransaction(method: "setMerchantMaxPerTx", parameters: [merchant, cap])
    }

    /// Set default daily cap per user.
    public func setDefaultUserDailyCap(_ cap: BigUInt) throws -> CodableTransaction {
        try contract.createWriteTransaction(method: "setDefaultUserDailyCap", parameters: [cap])
    }

    /// Set per-user daily cap override.
    public func setUserDailyCap(user: EthereumAddress, cap: BigUInt) throws -> CodableTransaction {
        try contract.createWriteTransaction(method: "setUserDailyCap", parameters: [user, cap])
    }

    /// Set default daily cap per merchant.
    public func setDefaultMerchantDailyCap(_ cap: BigUInt) throws -> CodableTransaction {
        try contract.createWriteTransaction(method: "setDefaultMerchantDailyCap", parameters: [cap])
    }

    /// Set per-merchant daily cap override.
    public func setMerchantDailyCap(merchant: EthereumAddress, cap: BigUInt) throws -> CodableTransaction {
        try contract.createWriteTransaction(method: "setMerchantDailyCap", parameters: [merchant, cap])
    }

    /// Set default daily cap per user-merchant pair.
    public func setDefaultPairDailyCap(_ cap: BigUInt) throws -> CodableTransaction {
        try contract.createWriteTransaction(method: "setDefaultPairDailyCap", parameters: [cap])
    }

    /// Set per-merchant pair daily cap override.
    public func setMerchantPairDailyCap(merchant: EthereumAddress, cap: BigUInt) throws -> CodableTransaction {
        try contract.createWriteTransaction(method: "setMerchantPairDailyCap", parameters: [merchant, cap])
    }

    /// Set per user-merchant pair daily cap override.
    public func setUserMerchantPairDailyCap(user: EthereumAddress, merchant: EthereumAddress, cap: BigUInt) throws -> CodableTransaction {
        try contract.createWriteTransaction(method: "setUserMerchantPairDailyCap", parameters: [user, merchant, cap])
    }

    /// Set global daily cashback ceiling.
    public func setGlobalDailyCap(_ cap: BigUInt) throws -> CodableTransaction {
        try contract.createWriteTransaction(method: "setGlobalDailyCap", parameters: [cap])
    }

    // ═══════════════════════════════════════════════════════════════
    //  MARK: - Write: Admin — OPERATOR_ROLE: Min Payment
    // ═══════════════════════════════════════════════════════════════

    /// Set default minimum payment amount for cashback eligibility.
    public func setDefaultMinPayment(_ amount: BigUInt) throws -> CodableTransaction {
        try contract.createWriteTransaction(method: "setDefaultMinPayment", parameters: [amount])
    }

    /// Set per-merchant minimum payment override.
    public func setMerchantMinPayment(merchant: EthereumAddress, amount: BigUInt) throws -> CodableTransaction {
        try contract.createWriteTransaction(method: "setMerchantMinPayment", parameters: [merchant, amount])
    }

    // ═══════════════════════════════════════════════════════════════
    //  MARK: - Write: Admin — OPERATOR_ROLE: Timing
    // ═══════════════════════════════════════════════════════════════

    /// Set cooldown duration between cashback-earning payments at the same merchant.
    public func setCooldownSeconds(_ secs: BigUInt) throws -> CodableTransaction {
        try contract.createWriteTransaction(method: "setCooldownSeconds", parameters: [secs])
    }

    /// Set vesting duration for newly accrued rewards.
    public func setVestingDuration(_ secs: BigUInt) throws -> CodableTransaction {
        try contract.createWriteTransaction(method: "setVestingDuration", parameters: [secs])
    }

    /// Set inactivity threshold for reward expiry (minimum 90 days enforced on-chain).
    public func setInactivityThreshold(_ secs: BigUInt) throws -> CodableTransaction {
        try contract.createWriteTransaction(method: "setInactivityThreshold", parameters: [secs])
    }

    // ═══════════════════════════════════════════════════════════════
    //  MARK: - Write: Admin — OPERATOR_ROLE: Client Key & Grants
    // ═══════════════════════════════════════════════════════════════

    /// Set/disable client key address for app-attestation verification.
    public func setClientKeyAddress(_ newKey: EthereumAddress) throws -> CodableTransaction {
        try contract.createWriteTransaction(method: "setClientKeyAddress", parameters: [newKey])
    }

    /// Admin grant rewards from pool to a user's spendable balance (immediate, no vesting).
    public func grantRewards(user: EthereumAddress, amount: BigUInt) throws -> CodableTransaction {
        try contract.createWriteTransaction(method: "grantRewards", parameters: [user, amount])
    }

    /// Batch admin grant.
    public func grantRewardsBatch(users: [EthereumAddress], amounts: [BigUInt]) throws -> CodableTransaction {
        try contract.createWriteTransaction(method: "grantRewardsBatch", parameters: [users, amounts])
    }

    // ═══════════════════════════════════════════════════════════════
    //  MARK: - Write: Admin — DEFAULT_ADMIN_ROLE (Owner)
    // ═══════════════════════════════════════════════════════════════

    /// Safety ceiling on effective rate — Owner-only.
    public func setRateCapBps(_ bps: BigUInt) throws -> CodableTransaction {
        try contract.createWriteTransaction(method: "setRateCapBps", parameters: [bps])
    }

    /// Re-wire the vault address.
    public func setVault(_ newVault: EthereumAddress) throws -> CodableTransaction {
        try contract.createWriteTransaction(method: "setVault", parameters: [newVault])
    }

    /// Re-wire the registry address.
    public func setRegistry(_ newRegistry: EthereumAddress) throws -> CodableTransaction {
        try contract.createWriteTransaction(method: "setRegistry", parameters: [newRegistry])
    }

    /// Add a trusted ERC-2771 forwarder.
    public func addTrustedForwarder(_ forwarder: EthereumAddress) throws -> CodableTransaction {
        try contract.createWriteTransaction(method: "addTrustedForwarder", parameters: [forwarder])
    }

    /// Remove a trusted ERC-2771 forwarder.
    public func removeTrustedForwarder(_ forwarder: EthereumAddress) throws -> CodableTransaction {
        try contract.createWriteTransaction(method: "removeTrustedForwarder", parameters: [forwarder])
    }

    /// Set or disable the TierRegistry. address(0) disables the tier feature.
    public func setTierRegistry(_ newTierRegistry: EthereumAddress) throws -> CodableTransaction {
        try contract.createWriteTransaction(method: "setTierRegistry", parameters: [newTierRegistry])
    }

    // ═══════════════════════════════════════════════════════════════
    //  MARK: - Read: Payment Preview
    // ═══════════════════════════════════════════════════════════════

    /// Full payment preview — returns split, estimated cashback, and cashback status.
    public func previewPayment(
        user: EthereumAddress,
        recipient: EthereumAddress,
        totalAmount: BigUInt,
        useRewardsFirst: Bool,
        using web3: Web3
    ) async throws -> PaymentPreview {
        let executor = ContractReadExecutor(contract: contract, web3: web3)
        let result = try await executor.call(method: "previewPayment", parameters: [user, recipient, totalAmount, useRewardsFirst])

        guard let fromWallet = result["0"] as? BigUInt,
              let fromRewards = result["1"] as? BigUInt,
              let estimatedCashback = result["2"] as? BigUInt,
              let cashbackActive = result["3"] as? Bool,
              let reasonRaw = result["4"] as? BigUInt else {
            throw Web3Error.processingError(desc: "previewPayment returned unexpected format")
        }

        return PaymentPreview(
            fromWallet: fromWallet,
            fromRewards: fromRewards,
            estimatedCashback: estimatedCashback,
            cashbackActive: cashbackActive,
            cashbackInactiveReason: CashbackInactiveReason(rawValue: UInt8(reasonRaw))
        )
    }

    // ═══════════════════════════════════════════════════════════════
    //  MARK: - Read: User State
    // ═══════════════════════════════════════════════════════════════

    /// User status (severity-ordered — highest wins).
    public func getUserStatus(user: EthereumAddress, using web3: Web3) async throws -> RewardsUserStatus {
        let executor = ContractReadExecutor(contract: contract, web3: web3)
        let result: BigUInt = try await executor.call(method: "getUserStatus", parameters: [user])
        return RewardsUserStatus(rawValue: UInt8(result))
    }

    /// Aggregated balances: spendable, pending, and next vesting timestamp.
    public func getUserBalances(user: EthereumAddress, using web3: Web3) async throws -> UserRewardBalances {
        let executor = ContractReadExecutor(contract: contract, web3: web3)
        let result = try await executor.call(method: "getUserBalances", parameters: [user])

        guard let spendable = result["0"] as? BigUInt,
              let pending = result["1"] as? BigUInt,
              let nextVesting = result["2"] as? BigUInt else {
            throw Web3Error.processingError(desc: "getUserBalances returned unexpected format")
        }

        return UserRewardBalances(
            spendable: spendable,
            pending: pending,
            nextVesting: UInt64(nextVesting)
        )
    }

    /// Effective spendable balance (includes matured-but-unsettled).
    public func spendableOf(user: EthereumAddress, using web3: Web3) async throws -> BigUInt {
        let executor = ContractReadExecutor(contract: contract, web3: web3)
        return try await executor.call(method: "spendableOf", parameters: [user])
    }

    /// Truly unvested pending only.
    public func pendingOf(user: EthereumAddress, using web3: Web3) async throws -> BigUInt {
        let executor = ContractReadExecutor(contract: contract, web3: web3)
        return try await executor.call(method: "pendingOf", parameters: [user])
    }

    /// Seconds remaining in cooldown for a user-merchant pair (0 if none).
    public func cooldownRemaining(user: EthereumAddress, merchant: EthereumAddress, using web3: Web3) async throws -> BigUInt {
        let executor = ContractReadExecutor(contract: contract, web3: web3)
        return try await executor.call(method: "cooldownRemaining", parameters: [user, merchant])
    }

    /// Timestamp of next vesting event.
    public func nextVestingAt(user: EthereumAddress, using web3: Web3) async throws -> BigUInt {
        let executor = ContractReadExecutor(contract: contract, web3: web3)
        return try await executor.call(method: "nextVestingAt", parameters: [user])
    }

    /// Per-epoch pending breakdown.
    public func getPendingBreakdown(user: EthereumAddress, using web3: Web3) async throws -> (amounts: [BigUInt], maturesAt: [BigUInt]) {
        let executor = ContractReadExecutor(contract: contract, web3: web3)
        let result = try await executor.call(method: "getPendingBreakdown", parameters: [user])

        guard let amounts = result["0"] as? [BigUInt],
              let maturesAt = result["1"] as? [BigUInt] else {
            throw Web3Error.processingError(desc: "getPendingBreakdown returned unexpected format")
        }

        return (amounts: amounts, maturesAt: maturesAt)
    }

    /// Whether a user is frozen.
    public func userFrozen(user: EthereumAddress, using web3: Web3) async throws -> Bool {
        let executor = ContractReadExecutor(contract: contract, web3: web3)
        return try await executor.call(method: "userFrozen", parameters: [user])
    }

    /// Whether a user is blacklisted.
    public func userBlacklisted(user: EthereumAddress, using web3: Web3) async throws -> Bool {
        let executor = ContractReadExecutor(contract: contract, web3: web3)
        return try await executor.call(method: "userBlacklisted", parameters: [user])
    }

    // ═══════════════════════════════════════════════════════════════
    //  MARK: - Read: Cap & Rate Info
    // ═══════════════════════════════════════════════════════════════

    /// Effective per-tx cap for a merchant.
    public func effectiveMaxPerTx(merchant: EthereumAddress, using web3: Web3) async throws -> BigUInt {
        let executor = ContractReadExecutor(contract: contract, web3: web3)
        return try await executor.call(method: "effectiveMaxPerTx", parameters: [merchant])
    }

    /// Effective minimum payment for a merchant.
    public func effectiveMinPayment(merchant: EthereumAddress, using web3: Web3) async throws -> BigUInt {
        let executor = ContractReadExecutor(contract: contract, web3: web3)
        return try await executor.call(method: "effectiveMinPayment", parameters: [merchant])
    }

    /// Effective daily cap for a user.
    public func effectiveUserDailyCap(user: EthereumAddress, using web3: Web3) async throws -> BigUInt {
        let executor = ContractReadExecutor(contract: contract, web3: web3)
        return try await executor.call(method: "effectiveUserDailyCap", parameters: [user])
    }

    /// Effective daily cap for a merchant.
    public func effectiveMerchantDailyCap(merchant: EthereumAddress, using web3: Web3) async throws -> BigUInt {
        let executor = ContractReadExecutor(contract: contract, web3: web3)
        return try await executor.call(method: "effectiveMerchantDailyCap", parameters: [merchant])
    }

    /// Effective daily cap for a user-merchant pair (3-tier resolution).
    public func effectivePairDailyCap(user: EthereumAddress, merchant: EthereumAddress, using web3: Web3) async throws -> BigUInt {
        let executor = ContractReadExecutor(contract: contract, web3: web3)
        return try await executor.call(method: "effectivePairDailyCap", parameters: [user, merchant])
    }

    /// Global effective base rate (scaled, no merchant context).
    public func effectiveBaseRateBps(using web3: Web3) async throws -> BigUInt {
        let executor = ContractReadExecutor(contract: contract, web3: web3)
        return try await executor.call(method: "effectiveBaseRateBps")
    }

    /// Batch merchant overrides for admin sync.
    public func getMerchantOverridesBatch(merchants: [EthereumAddress], using web3: Web3) async throws -> MerchantOverridesBatch {
        let executor = ContractReadExecutor(contract: contract, web3: web3)
        let result = try await executor.call(method: "getMerchantOverridesBatch", parameters: [merchants])

        guard let customRate = result["0"] as? [BigUInt],
              let maxPerTx = result["1"] as? [BigUInt],
              let dailyCap = result["2"] as? [BigUInt],
              let pairDailyCap = result["3"] as? [BigUInt],
              let minPayment = result["4"] as? [BigUInt] else {
            throw Web3Error.processingError(desc: "getMerchantOverridesBatch returned unexpected format")
        }

        return MerchantOverridesBatch(
            customRate: customRate,
            maxPerTx: maxPerTx,
            dailyCap: dailyCap,
            pairDailyCap: pairDailyCap,
            minPayment: minPayment
        )
    }

    // ═══════════════════════════════════════════════════════════════
    //  MARK: - Read: System Config
    // ═══════════════════════════════════════════════════════════════

    /// Whether the system is emergency-paused.
    public func emergencyPaused(using web3: Web3) async throws -> Bool {
        let executor = ContractReadExecutor(contract: contract, web3: web3)
        return try await executor.call(method: "emergencyPaused")
    }

    /// Whether cashback accrual is paused.
    public func cashbackPaused(using web3: Web3) async throws -> Bool {
        let executor = ContractReadExecutor(contract: contract, web3: web3)
        return try await executor.call(method: "cashbackPaused")
    }

    /// Current client-key address used for app-attestation verification.
    public func clientKeyAddress(using web3: Web3) async throws -> EthereumAddress {
        let executor = ContractReadExecutor(contract: contract, web3: web3)
        return try await executor.call(method: "clientKeyAddress")
    }

    /// System config parameters and flags in one call. See also `getSystemMetrics()` for live counters.
    public func getSystemConfig(using web3: Web3) async throws -> RewardsSystemConfig {
        let executor = ContractReadExecutor(contract: contract, web3: web3)
        let r = try await executor.call(method: "getSystemConfig")

        guard let v0 = r["0"] as? BigUInt, let v1 = r["1"] as? BigUInt,
              let v2 = r["2"] as? Bool, let v3 = r["3"] as? BigUInt,
              let v4 = r["4"] as? BigUInt, let v5 = r["5"] as? BigUInt,
              let v6 = r["6"] as? BigUInt, let v7 = r["7"] as? BigUInt,
              let v8 = r["8"] as? Bool, let v9 = r["9"] as? Bool,
              let v10 = r["10"] as? BigUInt, let v11 = r["11"] as? BigUInt,
              let v12 = r["12"] as? BigUInt, let v13 = r["13"] as? BigUInt,
              let v14 = r["14"] as? BigUInt, let v15 = r["15"] as? BigUInt else {
            throw Web3Error.processingError(desc: "getSystemConfig returned unexpected format")
        }

        return RewardsSystemConfig(
            baseRateBps: UInt16(v0), rateCapBps: UInt16(v1),
            rateScalingEnabled: v2, rewardsBaseline: v3,
            cooldownSeconds: UInt64(v4), vestingDuration: UInt64(v5),
            epochLength: UInt64(v6), inactivityThreshold: UInt64(v7),
            cashbackPaused: v8, emergencyPaused: v9,
            defaultMaxPerTx: v10, defaultUserDailyCap: v11,
            defaultMerchantDailyCap: v12, defaultPairDailyCap: v13,
            globalDailyCap: v14, defaultMinPayment: v15
        )
    }

    /// Live system metrics — counters and pool state.
    public func getSystemMetrics(using web3: Web3) async throws -> RewardsSystemMetrics {
        let executor = ContractReadExecutor(contract: contract, web3: web3)
        let r = try await executor.call(method: "getSystemMetrics")

        guard let v0 = r["0"] as? BigUInt, let v1 = r["1"] as? BigUInt,
              let v2 = r["2"] as? BigUInt, let v3 = r["3"] as? BigUInt,
              let v4 = r["4"] as? BigUInt else {
            throw Web3Error.processingError(desc: "getSystemMetrics returned unexpected format")
        }

        return RewardsSystemMetrics(
            totalCashbackDistributed: v0,
            totalEligibleVolume: v1,
            totalPaymentCount: v2,
            rewardsBucket: v3,
            totalAllocatedRewards: v4
        )
    }

    /// Current TierRegistry address (address(0) if disabled).
    public func tierRegistry(using web3: Web3) async throws -> EthereumAddress {
        let executor = ContractReadExecutor(contract: contract, web3: web3)
        return try await executor.call(method: "tierRegistry")
    }
}
