//
//  Web3+ERC1594.swift
//
//  Created by Anton Grigorev on 19/12/2018.
//  Major rewrite by Bailey Nahi on 08/08/2025.
//  Copyright © 2018 The Matter Inc. All rights reserved.
//

import BigInt
import Foundation
import Web3Core

// Core Security Token Standard
public protocol IERC1594: IERC20 {
    // Transfers
    func transferWithDataTxn(from: EthereumAddress, to: EthereumAddress, amount: String, data: [UInt8], using web3: Web3) async throws -> CodableTransaction
    func transferFromWithDataTxn(from: EthereumAddress, to: EthereumAddress, originalOwner: EthereumAddress, amount: String, data: [UInt8], using web3: Web3) async throws -> CodableTransaction

    // Token Issuance
    func isIssuable(using web3: Web3) async throws -> Bool
    func issueTxn(from: EthereumAddress, tokenHolder: EthereumAddress, amount: String, data: [UInt8], using web3: Web3) async throws -> CodableTransaction

    // Token Redemption
    func redeemTxn(from: EthereumAddress, amount: String, data: [UInt8], using web3: Web3) async throws -> CodableTransaction
    func redeemFromTxn(from: EthereumAddress, tokenHolder: EthereumAddress, amount: String, data: [UInt8], using web3: Web3) async throws -> CodableTransaction

    // Transfer Validity
    func canTransfer(to: EthereumAddress, amount: String, data: [UInt8], using web3: Web3) async throws -> ([UInt8], Data)
    func canTransferFrom(originalOwner: EthereumAddress, to: EthereumAddress, amount: String, data: [UInt8], using web3: Web3) async throws -> ([UInt8], Data)
}

public final class ERC1594: ERC20, IERC1594 {
    public override init(address: EthereumAddress, chainId: BigUInt, abiString: String = Web3.Utils.erc1594ABI) throws {
        try super.init(address: address, chainId: chainId, abiString: abiString)
    }
    
    public func transferWithDataTxn(from: EthereumAddress, to: EthereumAddress, amount: String, data: [UInt8], using web3: Web3) async throws -> CodableTransaction {
        let value = try await parseAmount(amount, using: web3)
        return try contract.createWriteTransaction(method: "transferWithData", parameters: [to, value, data], from: from)
    }
    
    public func transferFromWithDataTxn(from: EthereumAddress, to: EthereumAddress, originalOwner: EthereumAddress, amount: String, data: [UInt8], using web3: Web3) async throws -> CodableTransaction {
        let value = try await parseAmount(amount, using: web3)
        return try contract.createWriteTransaction(method: "transferFromWithData", parameters: [originalOwner, to, value, data], from: from)
    }
    
    public func isIssuable(using web3: Web3) async throws -> Bool {
        let executor = ContractReadExecutor(contract: contract, web3: web3)
        return try await executor.call(method: "isIssuable")
    }
    
    public func issueTxn(from: EthereumAddress, tokenHolder: EthereumAddress, amount: String, data: [UInt8], using web3: Web3) async throws -> CodableTransaction {
        let value = try await parseAmount(amount, using: web3)
        return try contract.createWriteTransaction(method: "issue", parameters: [tokenHolder, value, data], from: from)
    }
    
    public func redeemTxn(from: EthereumAddress, amount: String, data: [UInt8], using web3: Web3) async throws -> CodableTransaction {
        let value = try await parseAmount(amount, using: web3)
        return try contract.createWriteTransaction(method: "redeem", parameters: [value, data], from: from)
    }
    
    public func redeemFromTxn(from: EthereumAddress, tokenHolder: EthereumAddress, amount: String, data: [UInt8], using web3: Web3) async throws -> CodableTransaction {
        let value = try await parseAmount(amount, using: web3)
        return try contract.createWriteTransaction(method: "redeemFrom", parameters: [tokenHolder, value, data], from: from)
    }
    
    public func canTransfer(to: EthereumAddress, amount: String, data: [UInt8], using web3: Web3) async throws -> ([UInt8], Data) {
        let value = try await parseAmount(amount, using: web3)
        let executor = ContractReadExecutor(contract: contract, web3: web3)
        return try await executor.call(method: "canTransfer", parameters: [to, value, data])
    }
    
    public func canTransferFrom(originalOwner: EthereumAddress, to: EthereumAddress, amount: String, data: [UInt8], using web3: Web3) async throws -> ([UInt8], Data) {
        let value = try await parseAmount(amount, using: web3)
        let executor = ContractReadExecutor(contract: contract, web3: web3)
        return try await executor.call(method: "canTransferFrom", parameters: [originalOwner, to, value, data])
    }
}
