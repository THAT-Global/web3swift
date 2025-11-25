//
//  TokenMinter.swift
//  CrossifyPro
//
//  Created by Bailey Nahi on 17/04/2025.
//

import BigInt
import Foundation
import Web3Core

// MARK: - Protocol
protocol ITokenMinter {
    func mintTokens(token: EthereumAddress, to: EthereumAddress, amount: BigUInt, transactionHash: String) throws -> CodableTransaction // convenience
    func mintTokens(token: EthereumAddress, to: EthereumAddress, amount: BigUInt, transactionHash: Data) throws -> CodableTransaction

    func sendTokens(token: EthereumAddress, to: EthereumAddress, amount: BigUInt) throws -> CodableTransaction
    func withdraw(to: EthereumAddress, amount: BigUInt) throws -> CodableTransaction

    func isTransactionHashUsed(_ txHash: String, using web3: Web3) async throws -> Bool // convenience
    func isTransactionHashUsed(_ txHash: Data, using web3: Web3) async throws -> Bool

    func tokenBalance(token: EthereumAddress, using web3: Web3) async throws -> BigUInt
    func balance(using web3: Web3) async throws -> BigUInt
}

// MARK: - Implementation
public final class TokenMinter: ITokenMinter {
    public let contract: Contract
    public let contractAddress: EthereumAddress

    public init(contractAddress: EthereumAddress, chainId: BigUInt, abiString: String = Web3.Utils.tokenMinterABI) throws {
        self.contract = try Contract(abiString: abiString, address: contractAddress, chainId: chainId)
        self.contractAddress = contractAddress
    }

    // MARK: - Write Functions

    public func mintTokens(token: EthereumAddress, to: EthereumAddress, amount: BigUInt, transactionHash: String) throws -> CodableTransaction {
        guard transactionHash.isValidTransactionHash, let hashData = Data.fromHex(transactionHash) else {
            throw ValidationError.invalidTransactionHash
        }
        return try mintTokens(token: token, to: to, amount: amount, transactionHash: hashData)
    }

    public func mintTokens(token: EthereumAddress, to: EthereumAddress, amount: BigUInt, transactionHash: Data) throws -> CodableTransaction {
        try contract.createWriteTransaction(method: "mintTokens", parameters: [token, to, amount, transactionHash])
    }

    public func sendTokens(token: EthereumAddress, to: EthereumAddress, amount: BigUInt) throws -> CodableTransaction {
        try contract.createWriteTransaction(method: "sendTokens", parameters: [token, to, amount])
    }

    public func withdraw(to: EthereumAddress, amount: BigUInt) throws -> CodableTransaction {
        try contract.createWriteTransaction(method: "withdraw", parameters: [to, amount])
    }

    // MARK: - Read Functions

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

    public func tokenBalance(token: EthereumAddress, using web3: Web3) async throws -> BigUInt {
        let executor = ContractReadExecutor(contract: contract, web3: web3)
        return try await executor.call(method: "tokenBalance", parameters: [token])
    }

    public func balance(using web3: Web3) async throws -> BigUInt {
        let executor = ContractReadExecutor(contract: contract, web3: web3)
        return try await executor.call(method: "balance")
    }
}
