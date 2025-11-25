//
//  TokenVault.swift
//  CrossifyPro
//
//  Created by Bailey Nahi on 21/04/2025.
//

import BigInt
import Foundation
import Web3Core

// MARK: - Protocol
protocol ITokenVault {
    func withdrawToken(token: EthereumAddress, to: EthereumAddress, value: BigUInt, idempotencyKey: String) throws -> CodableTransaction
    func withdrawToken(token: EthereumAddress, to: EthereumAddress, value: BigUInt, idempotencyKey: Data) throws -> CodableTransaction
    
    func withdrawTokenAdmin(token: EthereumAddress, to: EthereumAddress, value: BigUInt, idempotencyKey: String) throws -> CodableTransaction
    func withdrawTokenAdmin(token: EthereumAddress, to: EthereumAddress, value: BigUInt, idempotencyKey: Data) throws -> CodableTransaction
    
    func withdrawFees(token: EthereumAddress, to: EthereumAddress) throws -> CodableTransaction
    func withdrawNative(to: EthereumAddress, value: BigUInt) throws -> CodableTransaction
    
    func setBaseFee(baseFee: BigUInt) throws -> CodableTransaction
    func setFeePercentage(feeBasisPoints: BigUInt) throws -> CodableTransaction
    func setMinAmount(minAmount: BigUInt) throws -> CodableTransaction
    func setMaxAmount(maxAmount: BigUInt) throws -> CodableTransaction
    
    func isIdempotencyKeyUsed(_ idempotencyKey: String, using web3: Web3) async throws -> Bool
    func isIdempotencyKeyUsed(_ idempotencyKey: Data, using web3: Web3) async throws -> Bool
    
    func tokenBalance(token: EthereumAddress, using web3: Web3) async throws -> BigUInt
    func balance(using web3: Web3) async throws -> BigUInt
}

// MARK: - Implementation
public final class TokenVault: ITokenVault {
    public let contract: Contract
    public let contractAddress: EthereumAddress
    
    public init(contractAddress: EthereumAddress, chainId: BigUInt, abiString: String = Web3.Utils.tokenVaultABI) throws {
        self.contract = try Contract(abiString: abiString, address: contractAddress, chainId: chainId)
        self.contractAddress = contractAddress
    }
    
    // MARK: - Write Functions
    
    public func withdrawToken(token: EthereumAddress, to: EthereumAddress, value: BigUInt, idempotencyKey: String) throws -> CodableTransaction {
        guard idempotencyKey.isValidTransactionHash, let hashData = Data.fromHex(idempotencyKey) else {
            throw ValidationError.invalidTransactionHash
        }
        return try withdrawToken(token: token, to: to, value: value, idempotencyKey: hashData)
    }
    
    public func withdrawToken(token: EthereumAddress, to: EthereumAddress, value: BigUInt, idempotencyKey: Data) throws -> CodableTransaction {
        try contract.createWriteTransaction(method: "withdrawToken", parameters: [token, to, value, idempotencyKey])
    }
    
    public func withdrawTokenAdmin(token: EthereumAddress, to: EthereumAddress, value: BigUInt, idempotencyKey: String) throws -> CodableTransaction {
        guard idempotencyKey.isValidTransactionHash, let hashData = Data.fromHex(idempotencyKey) else {
            throw ValidationError.invalidTransactionHash
        }
        return try withdrawTokenAdmin(token: token, to: to, value: value, idempotencyKey: hashData)
    }
    
    public func withdrawTokenAdmin(token: EthereumAddress, to: EthereumAddress, value: BigUInt, idempotencyKey: Data) throws -> CodableTransaction {
        try contract.createWriteTransaction(method: "withdrawTokenAdmin", parameters: [token, to, value, idempotencyKey])
    }
    
    public func withdrawFees(token: EthereumAddress, to: EthereumAddress) throws -> CodableTransaction {
        try contract.createWriteTransaction(method: "withdrawFees", parameters: [token, to])
    }
    
    public func withdrawNative(to: EthereumAddress, value: BigUInt) throws -> CodableTransaction {
        try contract.createWriteTransaction(method: "withdrawNative", parameters: [to, value])
    }
    
    public func setBaseFee(baseFee: BigUInt) throws -> CodableTransaction {
        try contract.createWriteTransaction(method: "setBaseFee", parameters: [baseFee])
    }
    
    public func setFeePercentage(feeBasisPoints: BigUInt) throws -> CodableTransaction {
        try contract.createWriteTransaction(method: "setFeePercentage", parameters: [feeBasisPoints])
    }
    
    public func setMinAmount(minAmount: BigUInt) throws -> CodableTransaction {
        try contract.createWriteTransaction(method: "setMinAmount", parameters: [minAmount])
    }
    
    public func setMaxAmount(maxAmount: BigUInt) throws -> CodableTransaction {
        try contract.createWriteTransaction(method: "setMaxAmount", parameters: [maxAmount])
    }
    
    // MARK: - Read Functions
    
    public func isIdempotencyKeyUsed(_ idempotencyKey: String, using web3: Web3) async throws -> Bool {
        guard idempotencyKey.isValidTransactionHash, let data = Data.fromHex(idempotencyKey) else {
            throw ValidationError.invalidTransactionHash
        }
        return try await isIdempotencyKeyUsed(data, using: web3)
    }
    
    public func isIdempotencyKeyUsed(_ idempotencyKey: Data, using web3: Web3) async throws -> Bool {
        let executor = ContractReadExecutor(contract: contract, web3: web3)
        return try await executor.call(method: "isIdempotencyKeyUsed", parameters: [idempotencyKey])
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
