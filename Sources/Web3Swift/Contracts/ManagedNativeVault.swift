//
//  ManagedNativeVault.swift
//  CrossifyPro
//
//  Created by Bailey Nahi on 17/04/2025.
//

import BigInt
import Foundation
import Web3Core

// MARK: – Protocol
protocol IManagedNativeVault {
    func withdraw(to: EthereumAddress, amount: BigUInt, transactionHash: String) throws -> CodableTransaction // convenience
    func withdraw(to: EthereumAddress, amount: BigUInt, transactionHash: Data) throws -> CodableTransaction
    func withdrawFees(to: EthereumAddress) throws -> CodableTransaction

    func setBaseFee(_ fee: BigUInt) throws -> CodableTransaction
    func setFeePercentage(_ percent: BigUInt) throws -> CodableTransaction
    func setMinAmount(_ min: BigUInt) throws -> CodableTransaction
    func setMaxAmount(_ max: BigUInt) throws -> CodableTransaction

    func pause() throws -> CodableTransaction
    func unpause() throws -> CodableTransaction

    func adminDeposit(amount: BigUInt) throws -> CodableTransaction

    func getBalance(using web3: Web3) async throws -> BigUInt
    func isTransactionHashUsed(_ txHash: String, using web3: Web3) async throws -> Bool // convenience
    func isTransactionHashUsed(_ txHash: Data, using web3: Web3) async throws -> Bool
}

// MARK: – Implementation
public final class ManagedNativeVault: IManagedNativeVault {
    public let contract: Contract
    public let contractAddress: EthereumAddress

    public init(contractAddress: EthereumAddress, chainId: BigUInt, abiString: String = Web3.Utils.managedNativeVaultABI) throws {
        self.contract = try Contract(abiString: abiString, address: contractAddress, chainId: chainId)
        self.contractAddress = contractAddress
    }

    // MARK: - Write Functions

    public func withdraw(to: EthereumAddress, amount: BigUInt, transactionHash: String) throws -> CodableTransaction {
        guard transactionHash.isValidTransactionHash, let hashData = Data.fromHex(transactionHash) else {
            throw ValidationError.invalidTransactionHash
        }
        return try withdraw(to: to, amount: amount, transactionHash: hashData)
    }
    
    public func withdraw(to: EthereumAddress, amount: BigUInt, transactionHash: Data) throws -> CodableTransaction {
        try contract.createWriteTransaction(method: "withdraw", parameters: [to, amount, transactionHash])
    }

    public func withdrawFees(to: EthereumAddress) throws -> CodableTransaction {
        try contract.createWriteTransaction(method: "withdrawFees", parameters: [to])
    }

    public func setBaseFee(_ fee: BigUInt) throws -> CodableTransaction {
        try contract.createWriteTransaction(method: "setBaseFee", parameters: [fee])
    }

    public func setFeePercentage(_ percent: BigUInt) throws -> CodableTransaction {
        try contract.createWriteTransaction(method: "setFeePercentage", parameters: [percent])
    }

    public func setMinAmount(_ min: BigUInt) throws -> CodableTransaction {
        try contract.createWriteTransaction(method: "setMinAmount", parameters: [min])
    }

    public func setMaxAmount(_ max: BigUInt) throws -> CodableTransaction {
        try contract.createWriteTransaction(method: "setMaxAmount", parameters: [max])
    }

    public func pause() throws -> CodableTransaction {
        try contract.createWriteTransaction(method: "pause")
    }

    public func unpause() throws -> CodableTransaction {
        try contract.createWriteTransaction(method: "unpause")
    }

    public func adminDeposit(amount: BigUInt) throws -> CodableTransaction {
        try contract.createWriteTransaction(method: "adminDeposit", value: amount)
    }

    // MARK: - Read Functions

    public func getBalance(using web3: Web3) async throws -> BigUInt {
        let executor = ContractReadExecutor(contract: contract, web3: web3)
        return try await executor.call(method: "getBalance")
    }

    public func isTransactionHashUsed(_ txHash: String, using web3: Web3) async throws -> Bool {
        guard txHash.isValidTransactionHash, let data = Data.fromHex(txHash) else {
            throw ValidationError.invalidTransactionHash
        }
        return try await isTransactionHashUsed(data, using: web3)
    }

    public func isTransactionHashUsed(_ txHash: Data, using web3: Web3) async throws -> Bool {
        let executor = ContractReadExecutor(contract: contract, web3: web3)
        return try await executor.call(method: "isTransactionHashUsed", parameters: [txHash])
    }
}
