//
//  Web3+ST20.swift
//
//  Created by Anton on 05/03/2019.
//  Major rewrite by Bailey Nahi on 08/08/2025.
//  Copyright © 2019 The Matter Inc. All rights reserved.
//

import BigInt
import Foundation
import Web3Core

// NPolymath Token Standard
public protocol IST20: IERC20 {
    func tokenDetails(using web3: Web3) async throws -> [UInt32]
    func verifyTransfer(from: EthereumAddress, originalOwner: EthereumAddress, to: EthereumAddress, amount: String, using web3: Web3) async throws -> CodableTransaction
    func mint(from: EthereumAddress, investor: EthereumAddress, amount: String, using web3: Web3) async throws -> CodableTransaction
    func burn(from: EthereumAddress, amount: String, using web3: Web3) async throws -> CodableTransaction
}

// This namespace contains functions to work with ST-20 tokens.
public class ST20: ERC20, IST20 {
    public override init(address: EthereumAddress, chainId: BigUInt, abiString: String = Web3.Utils.st20ABI) throws {
        try super.init(address: address, chainId: chainId, abiString: abiString)
    }
    
    public func tokenDetails(using web3: Web3) async throws -> [UInt32] {
        let executor = ContractReadExecutor(contract: contract, web3: web3)
        return try await executor.call(method: "tokenDetails")
    }
    
    public func verifyTransfer(from: EthereumAddress, originalOwner: EthereumAddress, to: EthereumAddress, amount: String, using web3: Web3) async throws -> CodableTransaction {
        let value = try await parseAmount(amount, using: web3)
        return try contract.createWriteTransaction(method: "verifyTransfer", parameters: [originalOwner, to, value], from: from)
    }
    
    public func mint(from: EthereumAddress, investor: EthereumAddress, amount: String, using web3: Web3) async throws -> CodableTransaction {
        let value = try await parseAmount(amount, using: web3)
        return try contract.createWriteTransaction(method: "mint", parameters: [investor, value], from: from)
    }
    
    public func burn(from: EthereumAddress, amount: String, using web3: Web3) async throws -> CodableTransaction {
        let value = try await parseAmount(amount, using: web3)
        return try contract.createWriteTransaction(method: "burn", parameters: [value], from: from)
    }
}
