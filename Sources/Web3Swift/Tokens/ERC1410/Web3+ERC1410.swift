//
//  Web3+ERC1410.swift
//
//  Created by Anton Grigorev on 19/12/2018.
//  Major rewrite by Bailey Nahi on 08/08/2025.
//  Copyright © 2018 The Matter Inc. All rights reserved.
//

import BigInt
import Foundation
import Web3Core

// Partially Fungible Token Standard
public protocol IERC1410: IERC20, IERC777 {
    func balanceOfByPartition(partition: Data, tokenHolder: EthereumAddress, using web3: Web3) async throws -> BigUInt
    func partitionsOf(tokenHolder: EthereumAddress, using web3: Web3) async throws -> [Data]
    
    func transferByPartitionTxn(partition: Data, to: EthereumAddress, amount: String, data: [UInt8], from: EthereumAddress, using web3: Web3) async throws -> CodableTransaction
    func operatorTransferByPartitionTxn(partition: Data, from: EthereumAddress, to: EthereumAddress, amount: String, data: [UInt8], operatorData: [UInt8], using web3: Web3) async throws -> CodableTransaction
    func canTransferByPartition(originalOwner: EthereumAddress, to: EthereumAddress, partition: Data, amount: String, data: [UInt8], using web3: Web3) async throws -> ([UInt8], Data, Data)
    
    func authorizeOperatorByPartitionTxn(partition: Data, operator user: EthereumAddress, from: EthereumAddress) throws -> CodableTransaction
    func revokeOperatorByPartitionTxn(partition: Data, operator user: EthereumAddress, from: EthereumAddress) throws -> CodableTransaction
    func isOperatorForPartition(partition: Data, operator user: EthereumAddress, tokenHolder: EthereumAddress, using web3: Web3) async throws -> Bool
    
    func issueByPartitionTxn(partition: Data, tokenHolder: EthereumAddress, amount: String, data: [UInt8], from: EthereumAddress, using web3: Web3) async throws -> CodableTransaction
    func redeemByPartitionTxn(partition: Data, amount: String, data: [UInt8], from: EthereumAddress, using web3: Web3) async throws -> CodableTransaction
    func operatorRedeemByPartitionTxn(partition: Data, tokenHolder: EthereumAddress, amount: String, operatorData: [UInt8], from: EthereumAddress, using web3: Web3) async throws -> CodableTransaction
}

public final class ERC1410: ERC777, IERC1410 {
    public override init(address: EthereumAddress, chainId: BigUInt, abiString: String = Web3.Utils.erc1410ABI) throws {
        try super.init(address: address, chainId: chainId, abiString: abiString)
    }
    
    public func balanceOfByPartition(partition: Data, tokenHolder: EthereumAddress, using web3: Web3) async throws -> BigUInt {
        let executor = ContractReadExecutor(contract: contract, web3: web3)
        return try await executor.call(method: "balanceOfByPartition", parameters: [partition, tokenHolder])
    }
    
    public func partitionsOf(tokenHolder: EthereumAddress, using web3: Web3) async throws -> [Data] {
        let executor = ContractReadExecutor(contract: contract, web3: web3)
        return try await executor.call(method: "partitionsOf", parameters: [tokenHolder])
    }
    
    public func transferByPartitionTxn(partition: Data, to: EthereumAddress, amount: String, data: [UInt8], from: EthereumAddress, using web3: Web3) async throws -> CodableTransaction {
        let value = try await parseAmount(amount, using: web3)
        return try contract.createWriteTransaction(method: "transferByPartition", parameters: [partition, to, value, data], from: from)
    }
    
    public func operatorTransferByPartitionTxn(partition: Data, from: EthereumAddress, to: EthereumAddress, amount: String, data: [UInt8], operatorData: [UInt8], using web3: Web3) async throws -> CodableTransaction {
        let value = try await parseAmount(amount, using: web3)
        return try contract.createWriteTransaction(method: "operatorTransferByPartition", parameters: [partition, from, to, value, data, operatorData], from: from)
    }
    
    public func canTransferByPartition(originalOwner: EthereumAddress, to: EthereumAddress, partition: Data, amount: String, data: [UInt8], using web3: Web3) async throws -> ([UInt8], Data, Data) {
        let value = try await parseAmount(amount, using: web3)
        let executor = ContractReadExecutor(contract: contract, web3: web3)
        return try await executor.call(method: "canTransferByPartition", parameters: [partition, originalOwner, to, value, data])
    }
    
    public func isOperatorForPartition(partition: Data, operator user: EthereumAddress, tokenHolder: EthereumAddress, using web3: Web3) async throws -> Bool {
        let executor = ContractReadExecutor(contract: contract, web3: web3)
        return try await executor.call(method: "isOperatorForPartition", parameters: [partition, user, tokenHolder])
    }
    
    public func authorizeOperatorByPartitionTxn(partition: Data, operator user: EthereumAddress, from: EthereumAddress) throws -> CodableTransaction {
        try contract.createWriteTransaction(method: "authorizeOperatorByPartition", parameters: [partition, user], from: from)
    }
    
    public func revokeOperatorByPartitionTxn(partition: Data, operator user: EthereumAddress, from: EthereumAddress) throws -> CodableTransaction {
        try contract.createWriteTransaction(method: "revokeOperatorByPartition", parameters: [partition, user], from: from)
    }
    
    public func issueByPartitionTxn(partition: Data, tokenHolder: EthereumAddress, amount: String, data: [UInt8], from: EthereumAddress, using web3: Web3) async throws -> CodableTransaction {
        let value = try await parseAmount(amount, using: web3)
        return try contract.createWriteTransaction(method: "issueByPartition", parameters: [partition, tokenHolder, value, data], from: from)
    }
    
    public func redeemByPartitionTxn(partition: Data, amount: String, data: [UInt8], from: EthereumAddress, using web3: Web3) async throws -> CodableTransaction {
        let value = try await parseAmount(amount, using: web3)
        return try contract.createWriteTransaction(method: "redeemByPartition", parameters: [partition, value, data], from: from)
    }
    
    public func operatorRedeemByPartitionTxn(partition: Data, tokenHolder: EthereumAddress, amount: String, operatorData: [UInt8], from: EthereumAddress, using web3: Web3) async throws -> CodableTransaction {
        let value = try await parseAmount(amount, using: web3)
        return try contract.createWriteTransaction(method: "operatorRedeemByPartition", parameters: [partition, tokenHolder, value, operatorData], from: from)
    }
}
