//
//  PolicyResolver.swift
//  THAT
//
//  Created by Bailey Nahi on 11/08/2025.
//

import BigInt
import Foundation
import Web3Core

public enum PolicyResolver {
    /// Resolves nonce & fees for a transaction. Skips pre-set values.
    /// Applies logic to ensure maxFeePerGas >= maxPriorityFeePerGas.
    public static func resolveAllMissing(
        for txn: inout CodableTransaction,
        policies: Policies = .auto,
        using provider: Web3Provider
    ) async throws {
        guard txn.from != nil || txn.sender != nil else {
            throw Web3Error.valueError(desc: "Missing msg.sender: cannot resolve nonce or estimate gas without 'from' or signed 'sender'.")
        }
        
        if txn.nonce == 0 {
            txn.nonce = try await resolveNonce(for: txn, policy: policies.noncePolicy, using: provider)
        }
        
        if txn.gasLimit == 0 {
            txn.gasLimit = try await resolveGasEstimate(for: txn, policy: policies.gasLimitPolicy, using: provider)
        }
        
        let oracle = Oracle(provider, percentiles: [50, 75, 95]) // Pull all fee data from one oracle (shared fee-history cache)
        if case .eip1559 = txn.type {
            if txn.maxFeePerGas == 0 || txn.maxPriorityFeePerGas == 0 {
                // When both fee policies are manual, use them as final values directly.
                // This lets callers pass exact maxFeePerGas/maxPriorityFeePerGas without
                // the values being reinterpreted through the (base × 2) + tip formula.
                if case .manual(let manualMaxFee) = policies.maxFeePerGasPolicy,
                   case .manual(let manualTip) = policies.maxPriorityFeePerGasPolicy {
                    txn.maxFeePerGas = manualMaxFee
                    txn.maxPriorityFeePerGas = manualTip
                } else {
                    let base = await resolveGasBaseFee(policy: policies.maxFeePerGasPolicy, using: oracle)
                    let tip = await resolveGasPriorityFee(policy: policies.maxPriorityFeePerGasPolicy, using: oracle)
                    txn.maxPriorityFeePerGas = tip
                    txn.maxFeePerGas = (base * 2) + tip
                }
            }
            if (txn.maxFeePerGas ?? 0) < (txn.maxPriorityFeePerGas ?? 0) {
                txn.maxFeePerGas = txn.maxPriorityFeePerGas
            }
        } else {
            if txn.gasPrice == 0 {
                txn.gasPrice = await resolveGasPrice(policy: policies.gasPricePolicy, using: oracle)
            }
            if txn.type == .legacy, txn.gasPrice == 0 {
                txn.gasPrice = try await fallbackGasPrice(using: provider) // Handle chains with limited legacy txn oracle data
            }
        }
    }
    
    public static func resolveGasBaseFee(policy: ValueResolutionPolicy, using oracle: Oracle) async -> BigUInt {
        switch policy {
            case .automatic:
                return await oracle.baseFeePercentiles().max() ?? 0
            case .manual(let value):
                return value
        }
    }
    
    public static func resolveGasEstimate(for transaction: CodableTransaction, policy: ValueResolutionPolicy, using provider: Web3Provider) async throws -> BigUInt {
        switch policy {
            case .automatic:
                return try await estimateGas(for: transaction, using: provider)
            case .manual(let value):
                return value
        }
    }
    
    public static func resolveGasPrice(policy: ValueResolutionPolicy, using oracle: Oracle) async -> BigUInt {
        switch policy {
            case .automatic:
                return await oracle.gasPriceLegacyPercentiles().max() ?? 0
            case .manual(let value):
                return value
        }
    }
    
    public static func resolveGasPriorityFee(policy: ValueResolutionPolicy, using oracle: Oracle) async -> BigUInt {
        switch policy {
            case .automatic:
                return await oracle.tipFeePercentiles().max() ?? 0
            case .manual(let value):
                return value
        }
    }
    
    public static func resolveNonce(for tx: CodableTransaction, policy: NoncePolicy, using provider: Web3Provider) async throws -> BigUInt {
        switch policy {
            case .exact(let value):
                return value
            case .pending, .latest, .earliest:
                guard let address = tx.from ?? tx.sender else { throw Web3Error.valueError() }
                // Honour the supplied policy as the block tag. The
                // previous implementation pattern-matched the policy
                // but then unconditionally resolved against `.latest`,
                // making the enum decorative. This fix is purely
                // code-correctness — the app-level default in
                // `Policies()` remains `.latest`, so the behavior
                // doesn't change for existing call sites. Callers that
                // genuinely want a mempool-aware read can now opt in
                // by constructing `Policies(noncePolicy: .pending, ...)`
                // or by setting `tx.callOnBlock = .pending` directly.
                // `tx.callOnBlock` still wins if explicitly set so
                // existing call sites that pin a block continue to do so.
                // (V202-RELEASE-AUDIT.md H-1.)
                let block: BlockNumber = tx.callOnBlock ?? policy
                let request: APIRequest = .getTransactionCount(address.address, block)
                let response: APIResponse<BigUInt> = try await APIRequest.sendRequest(with: provider, for: request)
                return response.result
        }
    }
    
    private static func estimateGas(for transaction: CodableTransaction, using provider: Web3Provider) async throws -> BigUInt {
        let request: APIRequest = .estimateGas(transaction, transaction.callOnBlock ?? .latest)
        return try await APIRequest.sendRequest(with: provider, for: request).result
    }
    
    private static func fallbackGasPrice(using provider: Web3Provider) async throws -> BigUInt {
        try await APIRequest.sendRequest(with: provider, for: .gasPrice).result
    }
}

/// Returns a modified copy of the transaction. Calls the `inout` variant internally.
extension PolicyResolver {
    public static func resolveAllMissing(
        for transaction: CodableTransaction,
        policies: Policies = .auto,
        using provider: Web3Provider
    ) async throws -> CodableTransaction {
        var txn = transaction
        try await resolveAllMissing(for: &txn, policies: policies, using: provider)
        return txn
    }
}
