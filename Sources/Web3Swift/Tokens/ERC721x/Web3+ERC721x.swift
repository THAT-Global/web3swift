//
//  Web3+ERC721x.swift
//
//  Created by Anton Grigorev on 20/12/2018.
//  Major rewrite by Bailey Nahi on 08/08/2025.
//  Copyright © 2018 The Matter Inc. All rights reserved.
//

import BigInt
import Foundation
import Web3Core

/// Extended NFT Interface — Backward-compatible with IERC721 + Adds multi-token support and batch transfers.
protocol IERC721x: IERC721, IERC721Metadata, IERC721Enumerable {
    // MARK: - Extended Read
    func implementsERC721X(using web3: Web3) async throws -> Bool
    func getBalance(account: EthereumAddress, tokenId: BigUInt, using web3: Web3) async throws -> BigUInt
    func tokensOwned(account: EthereumAddress, using web3: Web3) async throws -> ([BigUInt], [BigUInt])
    
    // MARK: - Extended Write
    func transferTxn(from: EthereumAddress, to: EthereumAddress, tokenId: BigUInt, quantity: BigUInt) throws -> CodableTransaction
    func transferFromTxn(from: EthereumAddress, to: EthereumAddress, originalOwner: EthereumAddress, tokenId: BigUInt, quantity: BigUInt) throws -> CodableTransaction
    func safeTransferFromTxn(from: EthereumAddress, to: EthereumAddress, originalOwner: EthereumAddress, tokenId: BigUInt, amount: BigUInt) throws -> CodableTransaction
    func safeTransferFromTxn(from: EthereumAddress, to: EthereumAddress, originalOwner: EthereumAddress, tokenId: BigUInt, amount: BigUInt, data: [UInt8]) throws -> CodableTransaction
    func safeTransferFromTxn(from: EthereumAddress, to: EthereumAddress, originalOwner: EthereumAddress, tokenIds: [BigUInt], amounts: [BigUInt], data: [UInt8]) throws -> CodableTransaction
}

/// ERC721x is an extension of ERC721 that adds support for multi-fungible tokens and batch transfers, while remaining backward-compatible.
// FIXME: Rewrite this to CodableTransaction
public final class ERC721x: ERC721, IERC721x {
    public override init(contractAddress: EthereumAddress, chainId: BigUInt, abiString: String = Web3.Utils.erc721xABI) throws {
        try super.init(contractAddress: contractAddress, chainId: chainId, abiString: abiString)
    }
    
    // MARK: - ERC721x-specific Reads
    
    public func implementsERC721X(using web3: Web3) async throws -> Bool {
        let executor = ContractReadExecutor(contract: contract, web3: web3)
        return try await executor.call(method: "implementsERC721X")
    }
    
    public func getBalance(account: EthereumAddress, tokenId: BigUInt, using web3: Web3) async throws -> BigUInt {
        let executor = ContractReadExecutor(contract: contract, web3: web3)
        return try await executor.call(method: "balanceOf", parameters: [account, tokenId])
    }
    
    public func tokensOwned(account: EthereumAddress, using web3: Web3) async throws -> ([BigUInt], [BigUInt]) {
        let executor = ContractReadExecutor(contract: contract, web3: web3)
        return try await executor.call(method: "tokensOwned", parameters: [account])
    }
    
    // MARK: - ERC721x-specific Writes
    
    public func transferTxn(from: EthereumAddress, to: EthereumAddress, tokenId: BigUInt, quantity: BigUInt) throws -> CodableTransaction {
        try contract.createWriteTransaction(method: "transfer", parameters: [to, tokenId, quantity], from: from)
    }
    
    public func transferFromTxn(from: EthereumAddress, to: EthereumAddress, originalOwner: EthereumAddress, tokenId: BigUInt, quantity: BigUInt) throws -> CodableTransaction {
        try contract.createWriteTransaction(method: "transferFrom", parameters: [originalOwner, to, tokenId, quantity], from: from)
    }
    
    public func safeTransferFromTxn(from: EthereumAddress, to: EthereumAddress, originalOwner: EthereumAddress, tokenId: BigUInt, amount: BigUInt) throws -> CodableTransaction {
        try contract.createWriteTransaction(method: "safeTransferFrom", parameters: [originalOwner, to, tokenId, amount], from: from)
    }
    
    public func safeTransferFromTxn(from: EthereumAddress, to: EthereumAddress, originalOwner: EthereumAddress, tokenId: BigUInt, amount: BigUInt, data: [UInt8]) throws -> CodableTransaction {
        try contract.createWriteTransaction(method: "safeTransferFrom", parameters: [originalOwner, to, tokenId, amount, data], from: from)
    }
    
    public func safeTransferFromTxn(from: EthereumAddress, to: EthereumAddress, originalOwner: EthereumAddress, tokenIds: [BigUInt], amounts: [BigUInt], data: [UInt8]) throws -> CodableTransaction {
        try contract.createWriteTransaction(method: "safeTransferFrom", parameters: [originalOwner, to, tokenIds, amounts, data], from: from)
    }
}
