//
//  Web3+ERC1400.swift
//
//  Created by Anton Grigorev on 14/12/2018.
//  Major rewrite by Bailey Nahi on 08/08/2025.
//  Copyright © 2018 The Matter Inc. All rights reserved.
//

import BigInt
import Foundation
import Web3Core

// Security Token Standard
public protocol IERC1400: IERC20, IERC777 {
    // Document Management
    func getDocument(name: Data, using web3: Web3) async throws -> (String, Data)
    func setDocumentTxn(from: EthereumAddress, name: Data, uri: String, documentHash: Data) throws -> CodableTransaction
    
    // Token Information
    func balanceOfByPartition(partition: Data, tokenHolder: EthereumAddress, using web3: Web3) async throws -> BigUInt
    func partitionsOf(tokenHolder: EthereumAddress, using web3: Web3) async throws -> [Data]
    
    // Transfers
    func transferWithDataTxn(from: EthereumAddress, to: EthereumAddress, amount: String, data: [UInt8], using web3: Web3) async throws -> CodableTransaction
    func transferFromWithDataTxn(from: EthereumAddress, to: EthereumAddress, originalOwner: EthereumAddress, amount: String, data: [UInt8], using web3: Web3) async throws -> CodableTransaction
    
    // Partition Token Transfers
    func transferByPartitionTxn(partition: Data, from: EthereumAddress, to: EthereumAddress, amount: String, data: [UInt8], using web3: Web3) async throws -> CodableTransaction
    func operatorTransferByPartitionTxn(partition: Data, from: EthereumAddress, to: EthereumAddress, originalOwner: EthereumAddress, amount: String, data: [UInt8], operatorData: [UInt8], using web3: Web3) async throws -> CodableTransaction
    
    // Controller Operations
    func isControllable(using web3: Web3) async throws -> Bool
    func controllerTransferTxn(from: EthereumAddress, to: EthereumAddress, originalOwner: EthereumAddress, amount: String, data: [UInt8], operatorData: [UInt8], using web3: Web3) async throws -> CodableTransaction
    func controllerRedeemTxn(from: EthereumAddress, tokenHolder: EthereumAddress, amount: String, data: [UInt8], operatorData: [UInt8], using web3: Web3) async throws -> CodableTransaction
    
    // Operator Management
    func authorizeOperatorTxn(from: EthereumAddress, operator user: EthereumAddress) throws -> CodableTransaction
    func revokeOperatorTxn(from: EthereumAddress, operator user: EthereumAddress) throws -> CodableTransaction
    func authorizeOperatorByPartitionTxn(from: EthereumAddress, partition: Data, operator user: EthereumAddress) throws -> CodableTransaction
    func revokeOperatorByPartitionTxn(from: EthereumAddress, partition: Data, operator user: EthereumAddress) throws -> CodableTransaction
    
    // Operator Info
    func isOperator(operator user: EthereumAddress, tokenHolder: EthereumAddress, using web3: Web3) async throws -> Bool
    func isOperatorForPartition(partition: Data, operator user: EthereumAddress, tokenHolder: EthereumAddress, using web3: Web3) async throws -> Bool
    
    // Issuance
    func isIssuable(using web3: Web3) async throws -> Bool
    func issueTxn(from: EthereumAddress, tokenHolder: EthereumAddress, amount: String, data: [UInt8], using web3: Web3) async throws -> CodableTransaction
    func issueByPartitionTxn(from: EthereumAddress, partition: Data, tokenHolder: EthereumAddress, amount: String, data: [UInt8], using web3: Web3) async throws -> CodableTransaction
    
    // Redemption
    func redeemTxn(from: EthereumAddress, amount: String, data: [UInt8], using web3: Web3) async throws -> CodableTransaction
    func redeemFromTxn(from: EthereumAddress, tokenHolder: EthereumAddress, amount: String, data: [UInt8], using web3: Web3) async throws -> CodableTransaction
    func redeemByPartitionTxn(from: EthereumAddress, partition: Data, amount: String, data: [UInt8], using web3: Web3) async throws -> CodableTransaction
    func operatorRedeemByPartitionTxn(from: EthereumAddress, partition: Data, tokenHolder: EthereumAddress, amount: String, operatorData: [UInt8], using web3: Web3) async throws -> CodableTransaction
    
    // Transfer Validity
    func canTransfer(to: EthereumAddress, amount: String, data: [UInt8], using web3: Web3) async throws -> ([UInt8], Data)
    func canTransferFrom(originalOwner: EthereumAddress, to: EthereumAddress, amount: String, data: [UInt8], using web3: Web3) async throws -> ([UInt8], Data)
    func canTransferByPartition(originalOwner: EthereumAddress, to: EthereumAddress, partition: Data, amount: String, data: [UInt8], using web3: Web3) async throws -> ([UInt8], Data, Data)
}
// This namespace contains functions to work with ERC1400 tokens.
public final class ERC1400: ERC777, IERC1400 {
    public override init(address: EthereumAddress, chainId: BigUInt, abiString: String = Web3.Utils.erc1400ABI) throws {
        try super.init(address: address, chainId: chainId, abiString: abiString)
    }

    public func getDocument(name: Data, using web3: Web3) async throws -> (String, Data) {
        let executor = ContractReadExecutor(contract: contract, web3: web3)
        return try await executor.call(method: "getDocument", parameters: [name])
    }

    public func setDocumentTxn(from: EthereumAddress, name: Data, uri: String, documentHash: Data) throws -> CodableTransaction {
        try contract.createWriteTransaction(method: "setDocument", parameters: [name, uri, documentHash], from: from)
    }

    public func balanceOfByPartition(partition: Data, tokenHolder: EthereumAddress, using web3: Web3) async throws -> BigUInt {
        let executor = ContractReadExecutor(contract: contract, web3: web3)
        return try await executor.call(method: "balanceOfByPartition", parameters: [partition, tokenHolder])
    }

    public func partitionsOf(tokenHolder: EthereumAddress, using web3: Web3) async throws -> [Data] {
        let executor = ContractReadExecutor(contract: contract, web3: web3)
        return try await executor.call(method: "partitionsOf", parameters: [tokenHolder])
    }

    public func transferWithDataTxn(from: EthereumAddress, to: EthereumAddress, amount: String, data: [UInt8], using web3: Web3) async throws -> CodableTransaction {
        let value = try await parseAmount(amount, using: web3)
        return try contract.createWriteTransaction(method: "transferWithData", parameters: [to, value, data], from: from)
    }

    public func transferFromWithDataTxn(from: EthereumAddress, to: EthereumAddress, originalOwner: EthereumAddress, amount: String, data: [UInt8], using web3: Web3) async throws -> CodableTransaction {
        let value = try await parseAmount(amount, using: web3)
        return try contract.createWriteTransaction(method: "transferFromWithData", parameters: [originalOwner, to, value, data], from: from)
    }

    public func transferByPartitionTxn(partition: Data, from: EthereumAddress, to: EthereumAddress, amount: String, data: [UInt8], using web3: Web3) async throws -> CodableTransaction {
        let value = try await parseAmount(amount, using: web3)
        return try contract.createWriteTransaction(method: "transferByPartition", parameters: [partition, to, value, data], from: from)
    }

    public func operatorTransferByPartitionTxn(partition: Data, from: EthereumAddress, to: EthereumAddress, originalOwner: EthereumAddress, amount: String, data: [UInt8], operatorData: [UInt8], using web3: Web3) async throws -> CodableTransaction {
        let value = try await parseAmount(amount, using: web3)
        return try contract.createWriteTransaction(method: "operatorTransferByPartition", parameters: [partition, originalOwner, to, value, data, operatorData], from: from)
    }

    public func isControllable(using web3: Web3) async throws -> Bool {
        let executor = ContractReadExecutor(contract: contract, web3: web3)
        return try await executor.call(method: "isControllable")
    }

    public func controllerTransferTxn(from: EthereumAddress, to: EthereumAddress, originalOwner: EthereumAddress, amount: String, data: [UInt8], operatorData: [UInt8], using web3: Web3) async throws -> CodableTransaction {
        let value = try await parseAmount(amount, using: web3)
        return try contract.createWriteTransaction(method: "controllerTransfer", parameters: [originalOwner, to, value, data, operatorData], from: from)
    }

    public func controllerRedeemTxn(from: EthereumAddress, tokenHolder: EthereumAddress, amount: String, data: [UInt8], operatorData: [UInt8], using web3: Web3) async throws -> CodableTransaction {
        let value = try await parseAmount(amount, using: web3)
        return try contract.createWriteTransaction(method: "controllerRedeem", parameters: [tokenHolder, value, data, operatorData], from: from)
    }

    public func authorizeOperatorTxn(from: EthereumAddress, operator user: EthereumAddress) throws -> CodableTransaction {
        try contract.createWriteTransaction(method: "authorizeOperator", parameters: [user], from: from)
    }

    public func revokeOperatorTxn(from: EthereumAddress, operator user: EthereumAddress) throws -> CodableTransaction {
        try contract.createWriteTransaction(method: "revokeOperator", parameters: [user], from: from)
    }

    public func authorizeOperatorByPartitionTxn(from: EthereumAddress, partition: Data, operator user: EthereumAddress) throws -> CodableTransaction {
        try contract.createWriteTransaction(method: "authorizeOperatorByPartition", parameters: [partition, user], from: from)
    }

    public func revokeOperatorByPartitionTxn(from: EthereumAddress, partition: Data, operator user: EthereumAddress) throws -> CodableTransaction {
        try contract.createWriteTransaction(method: "revokeOperatorByPartition", parameters: [partition, user], from: from)
    }

    public func isOperator(operator user: EthereumAddress, tokenHolder: EthereumAddress, using web3: Web3) async throws -> Bool {
        let executor = ContractReadExecutor(contract: contract, web3: web3)
        return try await executor.call(method: "isOperator", parameters: [user, tokenHolder])
    }

    public func isOperatorForPartition(partition: Data, operator user: EthereumAddress, tokenHolder: EthereumAddress, using web3: Web3) async throws -> Bool {
        let executor = ContractReadExecutor(contract: contract, web3: web3)
        return try await executor.call(method: "isOperatorForPartition", parameters: [partition, user, tokenHolder])
    }

    public func isIssuable(using web3: Web3) async throws -> Bool {
        let executor = ContractReadExecutor(contract: contract, web3: web3)
        return try await executor.call(method: "isIssuable")
    }

    public func issueTxn(from: EthereumAddress, tokenHolder: EthereumAddress, amount: String, data: [UInt8], using web3: Web3) async throws -> CodableTransaction {
        let value = try await parseAmount(amount, using: web3)
        return try contract.createWriteTransaction(method: "issue", parameters: [tokenHolder, value, data], from: from)
    }

    public func issueByPartitionTxn(from: EthereumAddress, partition: Data, tokenHolder: EthereumAddress, amount: String, data: [UInt8], using web3: Web3) async throws -> CodableTransaction {
        let value = try await parseAmount(amount, using: web3)
        return try contract.createWriteTransaction(method: "issueByPartition", parameters: [partition, tokenHolder, value, data], from: from)
    }

    public func redeemTxn(from: EthereumAddress, amount: String, data: [UInt8], using web3: Web3) async throws -> CodableTransaction {
        let value = try await parseAmount(amount, using: web3)
        return try contract.createWriteTransaction(method: "redeem", parameters: [value, data], from: from)
    }

    public func redeemFromTxn(from: EthereumAddress, tokenHolder: EthereumAddress, amount: String, data: [UInt8], using web3: Web3) async throws -> CodableTransaction {
        let value = try await parseAmount(amount, using: web3)
        return try contract.createWriteTransaction(method: "redeemFrom", parameters: [tokenHolder, value, data], from: from)
    }

    public func redeemByPartitionTxn(from: EthereumAddress, partition: Data, amount: String, data: [UInt8], using web3: Web3) async throws -> CodableTransaction {
        let value = try await parseAmount(amount, using: web3)
        return try contract.createWriteTransaction(method: "redeemByPartition", parameters: [partition, value, data], from: from)
    }

    public func operatorRedeemByPartitionTxn(from: EthereumAddress, partition: Data, tokenHolder: EthereumAddress, amount: String, operatorData: [UInt8], using web3: Web3) async throws -> CodableTransaction {
        let value = try await parseAmount(amount, using: web3)
        return try contract.createWriteTransaction(method: "operatorRedeemByPartition", parameters: [partition, tokenHolder, value, operatorData], from: from)
    }

    public func canTransfer(to: EthereumAddress, amount: String, data: [UInt8], using web3: Web3) async throws -> ([UInt8], Data) {
        let executor = ContractReadExecutor(contract: contract, web3: web3)
        let value = try await parseAmount(amount, using: web3)
        return try await executor.call(method: "canTransfer", parameters: [to, value, data])
    }

    public func canTransferFrom(originalOwner: EthereumAddress, to: EthereumAddress, amount: String, data: [UInt8], using web3: Web3) async throws -> ([UInt8], Data) {
        let executor = ContractReadExecutor(contract: contract, web3: web3)
        let value = try await parseAmount(amount, using: web3)
        return try await executor.call(method: "canTransfer", parameters: [originalOwner, to, value, data])
    }

    public func canTransferByPartition(originalOwner: EthereumAddress, to: EthereumAddress, partition: Data, amount: String, data: [UInt8], using web3: Web3) async throws -> ([UInt8], Data, Data) {
        let executor = ContractReadExecutor(contract: contract, web3: web3)
        let value = try await parseAmount(amount, using: web3)
        return try await executor.call(method: "canTransferByPartition", parameters: [partition, originalOwner, to, value, data])
    }
}
