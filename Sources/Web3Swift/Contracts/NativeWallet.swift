//
//  NativeWallet.swift
//  CrossifyPro
//
//  Created by Bailey Nahi on 17/04/2025.
//

import BigInt
import Foundation
import Web3Core

// MARK: - Protocol
protocol INativeWallet {
    func withdraw(to: EthereumAddress, amount: BigUInt, transactionHash: String) throws -> CodableTransaction // convenience
    func withdraw(to: EthereumAddress, amount: BigUInt, transactionHash: Data) throws -> CodableTransaction

    func adminWithdraw(to: EthereumAddress, amount: BigUInt) throws -> CodableTransaction
    func setMaxWithdrawalAmount(_ newMaxAmount: BigUInt) throws -> CodableTransaction

    func isTransactionHashUsed(_ txHash: String, using web3: Web3) async throws -> Bool // convenience
    func isTransactionHashUsed(_ txHash: Data, using web3: Web3) async throws -> Bool

    func getBalance(using web3: Web3) async throws -> BigUInt
}

// MARK: - Implementation
public final class NativeWallet: INativeWallet {
    public let contract: Contract
    public let contractAddress: EthereumAddress
    
    public init(contractAddress: EthereumAddress, chainId: BigUInt, abiString: String = Web3.Utils.nativeWalletABI) throws {
        self.contract = try Contract(abiString: abiString, address: contractAddress, chainId: chainId)
        self.contractAddress = contractAddress
    }
    
    // MARK: - Write Functions
    
    /// Allows the Treasurer to withdraw a specific amount from the contract, ensuring that the provided
    /// transaction hash has not been used before. This prevents replay errors and ensures each withdrawal is unique.
    public func withdraw(to: EthereumAddress, amount: BigUInt, transactionHash: String) throws -> CodableTransaction {
        guard transactionHash.isValidTransactionHash, let hashData = Data.fromHex(transactionHash) else {
            throw ValidationError.invalidTransactionHash
        }
        return try withdraw(to: to, amount: amount, transactionHash: hashData)
    }
    
    public func withdraw(to: EthereumAddress, amount: BigUInt, transactionHash: Data) throws -> CodableTransaction {
        try contract.createWriteTransaction(method: "withdraw", parameters: [to, amount, transactionHash])
    }
    
    public func adminWithdraw(to: EthereumAddress, amount: BigUInt) throws -> CodableTransaction {
        try contract.createWriteTransaction(method: "adminWithdraw", parameters: [to, amount])
    }
    
    public func setMaxWithdrawalAmount(_ newMaxAmount: BigUInt) throws -> CodableTransaction {
        try contract.createWriteTransaction(method: "setMaxWithdrawalAmount", parameters: [newMaxAmount])
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
