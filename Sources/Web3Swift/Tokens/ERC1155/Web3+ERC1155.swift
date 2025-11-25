//
//  Web3+ERC1155.swift
//
//  Created by Anton Grigorev on 20/12/2018.
//  Major rewrite by Bailey Nahi on 08/08/2025.
//  Copyright © 2018 The Matter Inc. All rights reserved.
//

import BigInt
import Foundation
import Web3Core

// Multi Token Standard
protocol IERC1155: IERC165 {
    func safeTransferFromTxn(from: EthereumAddress, to: EthereumAddress, originalOwner: EthereumAddress, id: BigUInt, value: BigUInt, data: [UInt8]) throws -> CodableTransaction
    func safeBatchTransferFromTxn(from: EthereumAddress, to: EthereumAddress, originalOwner: EthereumAddress, ids: [BigUInt], values: [BigUInt], data: [UInt8]) throws -> CodableTransaction
    func balanceOf(account: EthereumAddress, id: BigUInt, using web3: Web3) async throws -> BigUInt
    func setApprovalForAllTxn(from: EthereumAddress, operator user: EthereumAddress, approved: Bool, scope: Data) throws -> CodableTransaction
    func isApprovedForAll(owner: EthereumAddress, operator user: EthereumAddress, scope: Data, using web3: Web3) async throws -> Bool
}

protocol IERC1155Metadata {
    func uri(id: BigUInt, using web3: Web3) async throws -> String
    func name(id: BigUInt, using web3: Web3) async throws -> String
}

public final class ERC1155: IERC1155 {
    public let contract: Contract
    public let contractAddress: EthereumAddress
    
    public init(contractAddress: EthereumAddress, chainId: BigUInt, abiString: String = Web3.Utils.erc1155ABI) throws {
        self.contract = try Contract(abiString: abiString, address: contractAddress, chainId: chainId)
        self.contractAddress = contractAddress
    }
    
    public func tokenId(using web3: Web3) async throws -> BigUInt {
        let executor = ContractReadExecutor(contract: contract, web3: web3)
        return try await executor.call(method: "id")
    }
    
    public func safeTransferFromTxn(from: EthereumAddress, to: EthereumAddress, originalOwner: EthereumAddress, id: BigUInt, value: BigUInt, data: [UInt8]) throws -> CodableTransaction {
        try contract.createWriteTransaction(method: "safeTransferFrom", parameters: [originalOwner, to, id, value, data], from: from)
    }
    
    public func safeBatchTransferFromTxn(from: EthereumAddress, to: EthereumAddress, originalOwner: EthereumAddress, ids: [BigUInt], values: [BigUInt], data: [UInt8]) throws -> CodableTransaction {
        try contract.createWriteTransaction(method: "safeBatchTransferFrom", parameters: [originalOwner, to, ids, values, data], from: from)
    }
    
    public func balanceOf(account: EthereumAddress, id: BigUInt, using web3: Web3) async throws -> BigUInt {
        let executor = ContractReadExecutor(contract: contract, web3: web3)
        return try await executor.call(method: "balanceOf", parameters: [account, id])
    }
    
    public func setApprovalForAllTxn(from: EthereumAddress, operator user: EthereumAddress, approved: Bool, scope: Data) throws -> CodableTransaction {
        try contract.createWriteTransaction(method: "setApprovalForAll", parameters: [user, approved, scope], from: from)
    }
    
    public func isApprovedForAll(owner: EthereumAddress, operator user: EthereumAddress, scope: Data, using web3: Web3) async throws -> Bool {
        let executor = ContractReadExecutor(contract: contract, web3: web3)
        return try await executor.call(method: "isApprovedForAll", parameters: [owner, user, scope])
    }
    
    public func supportsInterface(interfaceID: String, using web3: Web3) async throws -> Bool {
        let executor = ContractReadExecutor(contract: contract, web3: web3)
        return try await executor.call(method: "supportsInterface", parameters: [interfaceID])
    }
}
