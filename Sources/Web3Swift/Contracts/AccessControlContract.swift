//
//  AccessControlContract.swift
//  Web3Swift
//
//  Created by Claude on 17/04/2026.
//

import BigInt
import Foundation
import Web3Core

// MARK: - Well-Known Role Hashes

/// Pre-computed keccak256 hashes for OpenZeppelin AccessControl roles used across the THAT contracts.
public enum AccessControlRole {
    /// `keccak256("OPERATOR_ROLE")` — RewardsManager, WhitelistRegistry
    public static let operator_ = Data(hex: "97667070c54ef182b0f5858b034beac1b6f3089aa2d3188bb1e8929f4fa9b929")
    /// `keccak256("SECURITY_ROLE")` — RewardsManager, WhitelistRegistry
    public static let security = Data(hex: "4698baa05b306e3e5e3fa66d29891e203a1418ef5bee962e2c9b109f129e8920")
    /// `keccak256("TREASURY_ROLE")` — RewardsManager, CashbackRewardsVault
    public static let treasury = Data(hex: "e1dcbdb91df27212a29bc27177c840cf2f819ecf2187432e1fac86c2dd5dfca9")
    /// `bytes32(0)` — DEFAULT_ADMIN_ROLE (OpenZeppelin convention)
    public static let defaultAdmin = Data(repeating: 0, count: 32)
}

// MARK: - Protocol

/// Shared interface for any contract that inherits OpenZeppelin's `AccessControl`.
/// Provides `hasRole`, `getRoleAdmin`, `grantRole`, `revokeRole`, and `renounceRole`.
///
/// Conforming types must expose `contract` and `contractAddress`. The protocol
/// provides default implementations that call through to the underlying ABI.
public protocol AccessControlContract {
    var contract: Contract { get }
    var contractAddress: EthereumAddress { get }
}

// MARK: - Default Implementations

extension AccessControlContract {

    // ═══════════════════════════════════════════════════════════════
    //  Read
    // ═══════════════════════════════════════════════════════════════

    /// Check whether `account` holds `role` on this contract.
    public func hasRole(_ role: Data, account: EthereumAddress, using web3: Web3) async throws -> Bool {
        let executor = ContractReadExecutor(contract: contract, web3: web3)
        return try await executor.call(method: "hasRole", parameters: [role, account])
    }

    /// Return the admin role that governs `role`.
    public func getRoleAdmin(_ role: Data, using web3: Web3) async throws -> Data {
        let executor = ContractReadExecutor(contract: contract, web3: web3)
        return try await executor.call(method: "getRoleAdmin", parameters: [role])
    }

    // ═══════════════════════════════════════════════════════════════
    //  Write
    // ═══════════════════════════════════════════════════════════════

    /// Grant `role` to `account`. Caller must hold the admin role for `role`.
    public func grantRole(_ role: Data, account: EthereumAddress) throws -> CodableTransaction {
        try contract.createWriteTransaction(method: "grantRole", parameters: [role, account])
    }

    /// Revoke `role` from `account`. Caller must hold the admin role for `role`.
    public func revokeRole(_ role: Data, account: EthereumAddress) throws -> CodableTransaction {
        try contract.createWriteTransaction(method: "revokeRole", parameters: [role, account])
    }

    /// Renounce `role` for `callerConfirmation` (must equal msg.sender).
    public func renounceRole(_ role: Data, callerConfirmation: EthereumAddress) throws -> CodableTransaction {
        try contract.createWriteTransaction(method: "renounceRole", parameters: [role, callerConfirmation])
    }
}
