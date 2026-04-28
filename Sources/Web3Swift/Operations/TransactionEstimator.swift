//
//  TransactionEstimator.swift
//  web3swift
//

import BigInt
import Foundation
import Web3Core

public struct GasEstimateResult: Sendable {
    public let cost: BigUInt
    public let gasLimit: BigUInt
    public let maxFeePerGas: BigUInt
    public let maxPriorityFeePerGas: BigUInt

    public init(cost: BigUInt, gasLimit: BigUInt, maxFeePerGas: BigUInt, maxPriorityFeePerGas: BigUInt) {
        self.cost = cost
        self.gasLimit = gasLimit
        self.maxFeePerGas = maxFeePerGas
        self.maxPriorityFeePerGas = maxPriorityFeePerGas
    }
}

public struct GasEstimation: Sendable {
    public let gasLimit: BigUInt
    public let gasPrice: BigUInt
    public let estimatedGasCost: BigUInt

    public init(gasLimit: BigUInt, gasPrice: BigUInt) {
        self.gasLimit = gasLimit
        self.gasPrice = gasPrice
        self.estimatedGasCost = gasLimit * gasPrice
    }

    public init(_ gasLimit: BigUInt, _ gasPrice: BigUInt) {
        self.init(gasLimit: gasLimit, gasPrice: gasPrice)
    }
}

public enum TransactionEstimator {

    public static func gasRequirement(for transaction: CodableTransaction, network: Network) async throws -> BigUInt {
        try await gasRequirementDetailed(for: transaction, network: network).cost
    }

    public static func gasRequirementDetailed(for transaction: CodableTransaction, network: Network) async throws -> GasEstimateResult {
        try await Web3ClientService.shared.performWithRPCFallback(for: network) { web3 in
            let oracle = Oracle(web3.provider, percentiles: [50, 75, 95])

            guard
                let maxBase = (await oracle.baseFeePercentiles()).max(),
                let maxTip = (await oracle.tipFeePercentiles()).max()
            else {
                throw Web3Error.inputError(desc: "Oracle returned nil for max base fee or tip (fee history may be unavailable).")
            }

            let maxFeePerGas = (maxBase * 2) + maxTip
            let gasLimit = try await web3.eth.estimateGas(for: transaction)

            return GasEstimateResult(
                cost: gasLimit * maxFeePerGas,
                gasLimit: gasLimit,
                maxFeePerGas: maxFeePerGas,
                maxPriorityFeePerGas: maxTip
            )
        }.result
    }

    public static func estimateGas(
        for transaction: inout CodableTransaction,
        policies: Policies = .auto,
        using web3: Web3
    ) async throws -> GasEstimation {
        try await PolicyResolver.resolveAllMissing(for: &transaction, policies: policies, using: web3.provider)

        let gasLimit = transaction.gasLimit
        let gasPrice: BigUInt

        if let txGasPrice = transaction.gasPrice {
            gasPrice = txGasPrice
        } else {
            gasPrice = try await web3.eth.gasPrice()
            transaction.gasPrice = gasPrice
        }

        return GasEstimation(gasLimit: gasLimit, gasPrice: gasPrice)
    }
}
