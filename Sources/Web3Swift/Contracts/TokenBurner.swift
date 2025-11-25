//
//  TokenBurner.swift
//  CrossifyPro
//
//  Created by Bailey Nahi on 17/04/2025.
//

import BigInt
import Foundation
import Web3Core

// MARK: - Protocol
protocol ITokenBurner {
    func burnTokens(token: EthereumAddress, amount: BigUInt) throws -> CodableTransaction
    func sendTokens(token: EthereumAddress, to: EthereumAddress, amount: BigUInt) throws -> CodableTransaction
    func withdraw(to: EthereumAddress, amount: BigUInt) throws -> CodableTransaction

    func tokenBalance(token: EthereumAddress, using web3: Web3) async throws -> BigUInt
    func balance(using web3: Web3) async throws -> BigUInt
}

// MARK: - Implementation
public final class TokenBurner: ITokenBurner {
    public let contract: Contract
    public let contractAddress: EthereumAddress
    
    public init(contractAddress: EthereumAddress, chainId: BigUInt, abiString: String = Web3.Utils.tokenBurnerABI) throws {
        self.contract = try Contract(abiString: abiString, address: contractAddress, chainId: chainId)
        self.contractAddress = contractAddress
    }
    
    // MARK: - Write Functions
    
    public func burnTokens(token: EthereumAddress, amount: BigUInt) throws -> CodableTransaction {
        try contract.createWriteTransaction(method: "burnTokens", parameters: [token, amount])
    }
    
    public func sendTokens(token: EthereumAddress, to: EthereumAddress, amount: BigUInt) throws -> CodableTransaction {
        try contract.createWriteTransaction(method: "sendTokens", parameters: [token, to, amount])
    }
    
    public func withdraw(to: EthereumAddress, amount: BigUInt) throws -> CodableTransaction {
        try contract.createWriteTransaction(method: "withdraw", parameters: [to, amount])
    }
    
    // MARK: - Read Functions
    
    /// Check the balance of ERC20 tokens owned by this contract
    public func tokenBalance(token: EthereumAddress, using web3: Web3) async throws -> BigUInt {
        let executor = ContractReadExecutor(contract: contract, web3: web3)
        return try await executor.call(method: "tokenBalance", parameters: [token])
    }
    
    public func balance(using web3: Web3) async throws -> BigUInt {
        let executor = ContractReadExecutor(contract: contract, web3: web3)
        return try await executor.call(method: "balance")
    }
}
