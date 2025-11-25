//
//  BaseRegistrar.swift
//
//  Created by Anton on 15/04/2019.
//  Major rewrite by Bailey Nahi on 08/08/2025.
//  Copyright © 2019 The Matter Inc. All rights reserved.
//

import BigInt
import Foundation
import Web3Core

// FIXME: Rewrite this to CodableTransaction
public extension ENS {
    class BaseRegistrar: ERC721 {
        
        public override init(contractAddress: EthereumAddress, chainId: BigUInt, abiString: String = Web3.Utils.baseRegistrarABI) throws {
            try super.init(contractAddress: contractAddress, chainId: chainId, abiString: abiString)
        }
        
        // MARK: - Controller Management
        @available(*, message: "Available only for contract owner")
        public func prepareAddController(controller: EthereumAddress, from: EthereumAddress) throws -> CodableTransaction {
            try contract.createWriteTransaction(method: "addController", parameters: [controller], from: from)
        }
        
        @available(*, message: "Available only for contract owner")
        public func prepareRemoveController(controller: EthereumAddress, from: EthereumAddress) throws -> CodableTransaction {
            try contract.createWriteTransaction(method: "removeController", parameters: [controller], from: from)
        }
        
        // MARK: - Resolver Management
        @available(*, message: "Available only for contract owner")
        public func prepareSetResolver(resolver: EthereumAddress, from: EthereumAddress) throws -> CodableTransaction {
            try contract.createWriteTransaction(method: "setResolver", parameters: [resolver], from: from)
        }
        
        // MARK: - Queries
        public func getNameExpiry(name: BigUInt, using web3: Web3) async throws -> BigUInt {
            let executor = ContractReadExecutor(contract: contract, web3: web3)
            return try await executor.call(method: "nameExpires", parameters: [name])
        }
        
        @available(*, message: "This function should not be used to check if a name can be registered by a user. To check if a name can be registered by a user, check name availability via the controller")
        public func isNameAvailable(name: BigUInt, using web3: Web3) async throws -> Bool {
            let executor = ContractReadExecutor(contract: contract, web3: web3)
            return try await executor.call(method: "available", parameters: [name])
        }
        
        // MARK: - Reclaim
        public func prepareReclaim(record: BigUInt, from: EthereumAddress) throws -> CodableTransaction {
            try contract.createWriteTransaction(method: "reclaim", parameters: [record], from: from)
        }
    }
}
