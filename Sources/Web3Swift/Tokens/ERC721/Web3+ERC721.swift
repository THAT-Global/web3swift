//
//  Created by Alex Vlasov.
//  Major rewrite by Bailey Nahi on 08/08/2025.
//  Copyright © 2018 Alex Vlasov. All rights reserved.
//

import BigInt
import Foundation
import Web3Core

// Non-Fungible Token Standard
protocol IERC721: IERC165 {
    func getBalance(account: EthereumAddress, using web3: Web3) async throws -> BigUInt
    func getOwner(tokenId: BigUInt, using web3: Web3) async throws -> EthereumAddress
    func getApproved(tokenId: BigUInt, using web3: Web3) async throws -> EthereumAddress
    func transferFromTxn(from: EthereumAddress, to: EthereumAddress, originalOwner: EthereumAddress, tokenId: BigUInt) throws -> CodableTransaction
    func safeTransferFromTxn(from: EthereumAddress, to: EthereumAddress, originalOwner: EthereumAddress, tokenId: BigUInt, data: [UInt8]?) throws -> CodableTransaction
    func transferTxn(from: EthereumAddress, to: EthereumAddress, tokenId: BigUInt) throws -> CodableTransaction
    func approveTxn(from: EthereumAddress, approved: EthereumAddress, tokenId: BigUInt) throws -> CodableTransaction
    func setApprovalForAllTxn(from: EthereumAddress, operator user: EthereumAddress, approved: Bool) throws -> CodableTransaction
    func isApprovedForAll(owner: EthereumAddress, operator user: EthereumAddress, using web3: Web3) async throws -> Bool
}

protocol IERC721Metadata {
    func tokenId(using web3: Web3) async throws -> BigUInt
    func name(using web3: Web3) async throws -> String
    func symbol(using web3: Web3) async throws -> String
    func tokenURI(tokenId: BigUInt, using web3: Web3) async throws -> String
}

protocol IERC721Enumerable {
    func totalSupply(using web3: Web3) async throws -> BigUInt
    func tokenByIndex(index: BigUInt, using web3: Web3) async throws -> BigUInt
    func tokenOfOwnerByIndex(owner: EthereumAddress, index: BigUInt, using web3: Web3) async throws -> BigUInt
}

// This namespace contains functions to work with ERC721 tokens.
public class ERC721: IERC721, IERC721Metadata, IERC721Enumerable {
    public let contract: Contract
    public let contractAddress: EthereumAddress
    
    public init(contractAddress: EthereumAddress, chainId: BigUInt, abiString: String = Web3.Utils.erc721ABI) throws {
        self.contract = try Contract(abiString: abiString, address: contractAddress, chainId: chainId)
        self.contractAddress = contractAddress
    }
    
    // MARK: - Reads
    
    public func getBalance(account: EthereumAddress, using web3: Web3) async throws -> BigUInt {
        let executor = ContractReadExecutor(contract: contract, web3: web3)
        return try await executor.call(method: "balanceOf", parameters: [account])
    }
    
    public func getOwner(tokenId: BigUInt, using web3: Web3) async throws -> EthereumAddress {
        let executor = ContractReadExecutor(contract: contract, web3: web3)
        return try await executor.call(method: "ownerOf", parameters: [tokenId])
    }
    
    public func getApproved(tokenId: BigUInt, using web3: Web3) async throws -> EthereumAddress {
        let executor = ContractReadExecutor(contract: contract, web3: web3)
        return try await executor.call(method: "getApproved", parameters: [tokenId])
    }
    
    public func isApprovedForAll(owner: EthereumAddress, operator user: EthereumAddress, using web3: Web3) async throws -> Bool {
        let executor = ContractReadExecutor(contract: contract, web3: web3)
        return try await executor.call(method: "isApprovedForAll", parameters: [owner, user])
    }
    
    public func supportsInterface(interfaceID: String, using web3: Web3) async throws -> Bool {
        let executor = ContractReadExecutor(contract: contract, web3: web3)
        return try await executor.call(method: "supportsInterface", parameters: [interfaceID])
    }
    
    // MARK: - Writes
    
    public func transferTxn(from: EthereumAddress, to: EthereumAddress, tokenId: BigUInt) throws -> CodableTransaction {
        try contract.createWriteTransaction(method: "transfer", parameters: [to, tokenId], from: from)
    }
    
    public func transferFromTxn(from: EthereumAddress, to: EthereumAddress, originalOwner: EthereumAddress, tokenId: BigUInt) throws -> CodableTransaction {
        try contract.createWriteTransaction(method: "transferFrom", parameters: [originalOwner, to, tokenId], from: from)
    }
    
    public func safeTransferFromTxn(from: EthereumAddress, to: EthereumAddress, originalOwner: EthereumAddress, tokenId: BigUInt, data: [UInt8]? = nil) throws -> CodableTransaction {
        let parameters: [Any] = data.map { [originalOwner, to, tokenId, $0] } ?? [originalOwner, to, tokenId]
        return try contract.createWriteTransaction(method: "safeTransferFrom", parameters: parameters, from: from)
    }
    
    public func approveTxn(from: EthereumAddress, approved: EthereumAddress, tokenId: BigUInt) throws -> CodableTransaction {
        try contract.createWriteTransaction(method: "approve", parameters: [approved, tokenId], from: from)
    }
    
    public func setApprovalForAllTxn(from: EthereumAddress, operator user: EthereumAddress, approved: Bool) throws -> CodableTransaction {
        try contract.createWriteTransaction(method: "setApprovalForAll", parameters: [user, approved], from: from)
    }
    
    // MARK: - Metadata
    
    public func tokenId(using web3: Web3) async throws -> BigUInt {
        let executor = ContractReadExecutor(contract: contract, web3: web3)
        return try await executor.call(method: "tokenId")
    }
    
    public func name(using web3: Web3) async throws -> String {
        let executor = ContractReadExecutor(contract: contract, web3: web3)
        return try await executor.call(method: "name")
    }
    
    public func symbol(using web3: Web3) async throws -> String {
        let executor = ContractReadExecutor(contract: contract, web3: web3)
        return try await executor.call(method: "symbol")
    }
    
    public func tokenURI(tokenId: BigUInt, using web3: Web3) async throws -> String {
        let executor = ContractReadExecutor(contract: contract, web3: web3)
        return try await executor.call(method: "tokenURI", parameters: [tokenId])
    }
    
    // MARK: - Enumerable
    
    public func totalSupply(using web3: Web3) async throws -> BigUInt {
        let executor = ContractReadExecutor(contract: contract, web3: web3)
        return try await executor.call(method: "totalSupply")
    }
    
    public func tokenByIndex(index: BigUInt, using web3: Web3) async throws -> BigUInt {
        let executor = ContractReadExecutor(contract: contract, web3: web3)
        return try await executor.call(method: "tokenByIndex", parameters: [index])
    }
    
    public func tokenOfOwnerByIndex(owner: EthereumAddress, index: BigUInt, using web3: Web3) async throws -> BigUInt {
        let executor = ContractReadExecutor(contract: contract, web3: web3)
        return try await executor.call(method: "tokenOfOwnerByIndex", parameters: [owner, index])
    }
}
