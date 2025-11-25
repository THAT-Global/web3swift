////
////  TransactionEstimator.swift
////  Created by Bailey Nahi on 26/11/2025.
////
//
//import BigInt
//import Foundation
//import Web3Core
//
//public enum TransactionEstimator {
//    /// Calculates the maximum possible cost of a transaction: `gasLimit × (maxBaseFee + maxTip)`.
//    /// Oracle caches percentile-based gas fee data: `try await web3.eth.feeHistory(blockCount: 20, block: .latest, percentiles: [25, 50, 75])`
//    /// - Throws: If chain ID or network is not found, or fee data is unavailable.
//    public static func gasRequirement(for transaction: CodableTransaction) async throws -> BigUInt {
//        guard let chainID = transaction.chainID else {
//            throw Web3Error.inputError(desc: "Transaction 'chainID' is not set.")
//        }
//        
//        guard let network = await NetworkService.getNetwork(chainID) else {
//            throw Web3Error.inputError(desc: "Unrecognized network ID: \(chainID)")
//        }
//        
//        return try await Web3ClientService.shared.performWithRPCFallback(for: network) { web3 in
//            let oracle = Oracle(web3.provider, blockCount: 20, percentiles: [25, 50, 75], cacheTimeout: 30)
//            
//            guard
//                let maxBase = (await oracle.baseFeePercentiles()).max(),    // 75th percentile
//                let maxTip = (await oracle.tipFeePercentiles()).max()       // 75th percentile
//            else {
//                throw Web3Error.inputError(desc: "Oracle returned nil for max base fee or tip (fee history may be unavailable).")
//            }
//            
//            let maxFeePerGas = maxBase + maxTip
//            let gasLimit = try await web3.eth.estimateGas(for: transaction)
//            
//            return gasLimit * maxFeePerGas
//        }.result
//    }
//    
//    /// Resolves any missing values (e.g. gas limit, gas price) and returns a simple gas cost estimate.
//    /// - Parameters:
//    ///   - transaction: Transaction to estimate for. Will be modified in-place.
//    ///   - web3: A Web3 instance for network interaction.
//    ///   - policies: Controls how missing values are resolved (e.g. nonce, gasLimit). Default is `.auto`.
//    /// - Returns: A `GasEstimation` containing gas limit and price.
//    public static func estimateGas(for transaction: inout CodableTransaction, policies: Policies = .auto, using web3: Web3) async throws -> GasEstimation {
//        try await PolicyResolver.resolveAllMissing(for: &transaction, policies: policies, using: web3.provider)
//        
//        let gasLimit = transaction.gasLimit
//        let gasPrice: BigUInt
//        
//        if let txGasPrice = transaction.gasPrice {
//            gasPrice = txGasPrice
//        } else {
//            gasPrice = try await web3.eth.gasPrice()
//            transaction.gasPrice = gasPrice
//        }
//        
//        return GasEstimation(gasLimit, gasPrice)
//    }
//}
