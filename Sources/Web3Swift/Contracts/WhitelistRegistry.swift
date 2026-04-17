//
//  WhitelistRegistry.swift
//  Web3Swift
//
//  Created by Claude on 17/04/2026.
//

import BigInt
import Foundation
import Web3Core

// MARK: - Return Types

/// Batch merchant state returned by `getMerchantStateBatch`.
public struct MerchantStateBatch {
    public let earnEligible: [Bool]
    public let spendEligible: [Bool]
    public let blacklisted: [Bool]

    public init(earnEligible: [Bool], spendEligible: [Bool], blacklisted: [Bool]) {
        self.earnEligible = earnEligible
        self.spendEligible = spendEligible
        self.blacklisted = blacklisted
    }
}

// MARK: - Implementation

public final class WhitelistRegistry: AccessControlContract {
    public let contract: Contract
    public let contractAddress: EthereumAddress

    public init(contractAddress: EthereumAddress, chainId: BigUInt, abiString: String = Web3.Utils.whitelistRegistryABI) throws {
        self.contract = try Contract(abiString: abiString, address: contractAddress, chainId: chainId)
        self.contractAddress = contractAddress
    }

    // ═══════════════════════════════════════════════════════════════
    //  MARK: - Write: Admin — OPERATOR_ROLE
    // ═══════════════════════════════════════════════════════════════

    /// Enroll or update a merchant's eligibility flags.
    public func setMerchant(merchant: EthereumAddress, earnEligible: Bool, spendEligible: Bool) throws -> CodableTransaction {
        try contract.createWriteTransaction(method: "setMerchant", parameters: [merchant, earnEligible, spendEligible])
    }

    /// Batch-enroll or update merchants.
    public func setMerchantBatch(merchants: [EthereumAddress], earnEligible: [Bool], spendEligible: [Bool]) throws -> CodableTransaction {
        try contract.createWriteTransaction(method: "setMerchantBatch", parameters: [merchants, earnEligible, spendEligible])
    }

    // ═══════════════════════════════════════════════════════════════
    //  MARK: - Write: Admin — SECURITY_ROLE
    // ═══════════════════════════════════════════════════════════════

    /// Blacklist or un-blacklist a merchant. Blacklisting auto-disables earn + spend.
    public func setMerchantBlacklist(merchant: EthereumAddress, blacklisted: Bool) throws -> CodableTransaction {
        try contract.createWriteTransaction(method: "setMerchantBlacklist", parameters: [merchant, blacklisted])
    }

    // ═══════════════════════════════════════════════════════════════
    //  MARK: - Read: Single Merchant
    // ═══════════════════════════════════════════════════════════════

    /// Whether customers earn cashback at this merchant.
    public func isMerchantEarnEligible(merchant: EthereumAddress, using web3: Web3) async throws -> Bool {
        let executor = ContractReadExecutor(contract: contract, web3: web3)
        return try await executor.call(method: "isMerchantEarnEligible", parameters: [merchant])
    }

    /// Whether customers can spend rewards at this merchant.
    public func isMerchantSpendEligible(merchant: EthereumAddress, using web3: Web3) async throws -> Bool {
        let executor = ContractReadExecutor(contract: contract, web3: web3)
        return try await executor.call(method: "isMerchantSpendEligible", parameters: [merchant])
    }

    /// Whether this merchant is blacklisted.
    public func isMerchantBlacklisted(merchant: EthereumAddress, using web3: Web3) async throws -> Bool {
        let executor = ContractReadExecutor(contract: contract, web3: web3)
        return try await executor.call(method: "isMerchantBlacklisted", parameters: [merchant])
    }

    /// Whether this address has ever been registered as a merchant.
    public func isMerchantRegistered(merchant: EthereumAddress, using web3: Web3) async throws -> Bool {
        let executor = ContractReadExecutor(contract: contract, web3: web3)
        return try await executor.call(method: "isMerchantRegistered", parameters: [merchant])
    }

    // ═══════════════════════════════════════════════════════════════
    //  MARK: - Read: Pagination
    // ═══════════════════════════════════════════════════════════════

    /// Total number of registered merchants.
    public func merchantCount(using web3: Web3) async throws -> BigUInt {
        let executor = ContractReadExecutor(contract: contract, web3: web3)
        return try await executor.call(method: "merchantCount")
    }

    /// Paginated merchant address list.
    public func allMerchants(from: BigUInt, count: BigUInt, using web3: Web3) async throws -> [EthereumAddress] {
        let executor = ContractReadExecutor(contract: contract, web3: web3)
        let result = try await executor.call(method: "allMerchants", parameters: [from, count])
        guard let addresses = result["0"] as? [EthereumAddress] else {
            throw Web3Error.processingError(desc: "allMerchants returned unexpected format")
        }
        return addresses
    }

    // ═══════════════════════════════════════════════════════════════
    //  MARK: - Read: Batch
    // ═══════════════════════════════════════════════════════════════

    /// Bulk-read merchant eligibility for a list of addresses.
    public func getMerchantStateBatch(merchants: [EthereumAddress], using web3: Web3) async throws -> MerchantStateBatch {
        let executor = ContractReadExecutor(contract: contract, web3: web3)
        let result = try await executor.call(method: "getMerchantStateBatch", parameters: [merchants])

        guard let earnEligible = result["0"] as? [Bool],
              let spendEligible = result["1"] as? [Bool],
              let blacklisted = result["2"] as? [Bool] else {
            throw Web3Error.processingError(desc: "getMerchantStateBatch returned unexpected format")
        }

        return MerchantStateBatch(
            earnEligible: earnEligible,
            spendEligible: spendEligible,
            blacklisted: blacklisted
        )
    }
}
