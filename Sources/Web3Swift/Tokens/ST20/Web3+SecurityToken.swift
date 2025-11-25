//
//  Web3+SecurityToken.swift
//
//  Created by Anton on 05/03/2019.
//  Major rewrite by Bailey Nahi on 08/08/2025.
//  Copyright © 2019 The Matter Inc. All rights reserved.
//

import BigInt
import Foundation
import Web3Core

/// The Ownable contract has an owner address, and provides basic authorization control functions, this simplifies the implementation of "user permissions".
public protocol IOwnable {
    /// Allows the current owner to relinquish control of the contract.
    func renounceOwnership(from: EthereumAddress) throws -> CodableTransaction
    /// Allows the current owner to transfer control of the contract to a newOwner.
    func transferOwnership(from: EthereumAddress, newOwner: EthereumAddress) throws -> CodableTransaction
}

/// Security token interface
public protocol ISecurityToken: IST20, IOwnable {
    func currentCheckpointId(using web3: Web3) async throws -> BigUInt
    func getGranularity(using web3: Web3) async throws -> BigUInt
    /// Total number of non-zero token holders
    func investorCount(using web3: Web3) async throws -> BigUInt
    /// List of token holders at specified index
    func investors(index: UInt, using web3: Web3) async throws -> [EthereumAddress]
    func checkPermission(delegate: EthereumAddress, module: EthereumAddress, perm: [UInt32], using web3: Web3) async throws -> Bool
    func getModule(moduleType: UInt8, moduleIndex: UInt8, using web3: Web3) async throws -> ([UInt32], EthereumAddress)
    func getModuleByName(moduleType: UInt8, name: [UInt32], using web3: Web3) async throws -> ([UInt32], EthereumAddress)
    /// Queries totalSupply as of a defined checkpoint
    func totalSupplyAt(checkpointId: BigUInt, using web3: Web3) async throws -> BigUInt
    /// Queries balances as of a defined checkpoint
    func balanceOfAt(investor: EthereumAddress, checkpointId: BigUInt, using web3: Web3) async throws -> BigUInt
    /// Creates a checkpoint that can be used to query historical balances / totalSupply
    func createCheckpoint(from: EthereumAddress) throws -> CodableTransaction
    /// Gets length of investors array
    func getInvestorsLength(using web3: Web3) async throws -> BigUInt
}

public final class SecurityToken: ST20, ISecurityToken {
    public override init(address: EthereumAddress, chainId: BigUInt, abiString: String = Web3.Utils.st20ABI) throws {
        try super.init(address: address, chainId: chainId, abiString: abiString)
    }
    
    public func renounceOwnership(from: EthereumAddress) throws -> CodableTransaction {
        try contract.createWriteTransaction(method: "renounceOwnership", from: from)
    }
    
    public func transferOwnership(from: EthereumAddress, newOwner: EthereumAddress) throws -> CodableTransaction {
        try contract.createWriteTransaction(method: "transferOwnership", parameters: [newOwner], from: from)
    }
    
    public func currentCheckpointId(using web3: Web3) async throws -> BigUInt {
        try await read(web3, method: "currentCheckpointId")
    }
    
    public func getGranularity(using web3: Web3) async throws -> BigUInt {
        try await read(web3, method: "granularity")
    }
    
    public func investorCount(using web3: Web3) async throws -> BigUInt {
        try await read(web3, method: "investorCount")
    }
    
    public func investors(index: UInt, using web3: Web3) async throws -> [EthereumAddress] {
        let executor = ContractReadExecutor(contract: contract, web3: web3)
        return try await executor.call(method: "investors", parameters: [index])
    }
    
    public func checkPermission(delegate: EthereumAddress, module: EthereumAddress, perm: [UInt32], using web3: Web3) async throws -> Bool {
        let executor = ContractReadExecutor(contract: contract, web3: web3)
        return try await executor.call(method: "checkPermission", parameters: [delegate, module, perm])
    }
    
    public func getModule(moduleType: UInt8, moduleIndex: UInt8, using web3: Web3) async throws -> ([UInt32], EthereumAddress) {
        let executor = ContractReadExecutor(contract: contract, web3: web3)
        let result: (first: [UInt32], second: EthereumAddress) = try await executor.call(method: "getModule", parameters: [moduleType, moduleIndex])
        return (result.first, result.second)
    }
    
    public func getModuleByName(moduleType: UInt8, name: [UInt32], using web3: Web3) async throws -> ([UInt32], EthereumAddress) {
        let executor = ContractReadExecutor(contract: contract, web3: web3)
        let result: (first: [UInt32], second: EthereumAddress) = try await executor.call(method: "getModuleByName", parameters: [moduleType, name])
        return (result.first, result.second)
    }
    
    public func totalSupplyAt(checkpointId: BigUInt, using web3: Web3) async throws -> BigUInt {
        let executor = ContractReadExecutor(contract: contract, web3: web3)
        return try await executor.call(method: "totalSupplyAt", parameters: [checkpointId])
    }
    
    public func balanceOfAt(investor: EthereumAddress, checkpointId: BigUInt, using web3: Web3) async throws -> BigUInt {
        let executor = ContractReadExecutor(contract: contract, web3: web3)
        return try await executor.call(method: "balanceOfAt", parameters: [investor, checkpointId])
    }
    
    public func createCheckpoint(from: EthereumAddress) throws -> CodableTransaction {
        try contract.createWriteTransaction(method: "createCheckpoint", from: from)
    }
    
    public func getInvestorsLength(using web3: Web3) async throws -> BigUInt {
        try await read(web3, method: "getInvestorsLength")
    }
}
