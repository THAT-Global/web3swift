//
//  CashbackRewardsVault.swift
//  Web3Swift
//
//  Created by Claude on 17/04/2026.
//

import BigInt
import Foundation
import Web3Core

// MARK: - Implementation

/// Wrapper for the RewardsVault contract — token custody for the THAT Cashback System.
/// Includes both read-only pool queries and admin (TREASURY_ROLE / Owner) write functions.
public final class CashbackRewardsVault: AccessControlContract, @unchecked Sendable {
    public let contract: Contract
    public let contractAddress: EthereumAddress

    public init(contractAddress: EthereumAddress, chainId: BigUInt, abiString: String = Web3.Utils.cashbackRewardsVaultABI) throws {
        self.contract = try Contract(abiString: abiString, address: contractAddress, chainId: chainId)
        self.contractAddress = contractAddress
    }

    // ═══════════════════════════════════════════════════════════════
    //  MARK: - Write: Admin — TREASURY_ROLE
    // ═══════════════════════════════════════════════════════════════

    /// Deposit tokens into the vault. Requires prior token.approve().
    /// If `toRewardsBucket` is true, also increases the rewards pool.
    public func fund(amount: BigUInt, toRewardsBucket: Bool) throws -> CodableTransaction {
        try contract.createWriteTransaction(method: "fund", parameters: [amount, toRewardsBucket])
    }

    /// Deposit tokens with EIP-2612 permit (single tx).
    public func fundWithPermit(
        amount: BigUInt,
        toRewardsBucket: Bool,
        deadline: BigUInt,
        v: UInt8,
        r: Data,
        s: Data
    ) throws -> CodableTransaction {
        try contract.createWriteTransaction(method: "fundWithPermit", parameters: [amount, toRewardsBucket, deadline, v, r, s])
    }

    /// Sweep excess tokens from the vault. Cannot violate solvency invariant.
    public func sweep(to: EthereumAddress, amount: BigUInt) throws -> CodableTransaction {
        try contract.createWriteTransaction(method: "sweep", parameters: [to, amount])
    }

    /// Manually adjust rewardsBucket (positive or negative delta). Solvency-checked.
    public func adjustRewardsBucket(delta: BigInt) throws -> CodableTransaction {
        try contract.createWriteTransaction(method: "adjustRewardsBucket", parameters: [delta])
    }

    // ═══════════════════════════════════════════════════════════════
    //  MARK: - Write: Admin — DEFAULT_ADMIN_ROLE (Owner)
    // ═══════════════════════════════════════════════════════════════

    /// Set the authorized RewardsManager address.
    public func setManager(_ newManager: EthereumAddress) throws -> CodableTransaction {
        try contract.createWriteTransaction(method: "setManager", parameters: [newManager])
    }

    // ═══════════════════════════════════════════════════════════════
    //  MARK: - Read: Pool State
    // ═══════════════════════════════════════════════════════════════

    /// Unallocated rewards pool — tokens available for new cashback accruals and grants.
    public func rewardsBucket(using web3: Web3) async throws -> BigUInt {
        let executor = ContractReadExecutor(contract: contract, web3: web3)
        return try await executor.call(method: "rewardsBucket")
    }

    /// Sum of all user pending + spendable balances across the system.
    public func totalAllocatedRewards(using web3: Web3) async throws -> BigUInt {
        let executor = ContractReadExecutor(contract: contract, web3: web3)
        return try await executor.call(method: "totalAllocatedRewards")
    }

    /// Convenience alias for `rewardsBucket`.
    public func availableForRewards(using web3: Web3) async throws -> BigUInt {
        let executor = ContractReadExecutor(contract: contract, web3: web3)
        return try await executor.call(method: "availableForRewards")
    }

    /// Current authorized manager address.
    public func manager(using web3: Web3) async throws -> EthereumAddress {
        let executor = ContractReadExecutor(contract: contract, web3: web3)
        return try await executor.call(method: "manager")
    }
}
