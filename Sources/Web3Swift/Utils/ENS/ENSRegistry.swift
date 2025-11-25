//
//  ENSRegistry.swift
//
//  Created by Anton on 17/04/2019.
//  Major rewrite by Bailey Nahi on 08/08/2025.
//  Copyright © 2019 The Matter Inc. All rights reserved.
//

import BigInt
import Foundation
import Web3Core

public extension ENS {
    struct Registry {
        public let contract: Contract
        public let contractAddress: EthereumAddress
        
        public init(contractAddress: EthereumAddress, chainId: BigUInt, abiString: String = Web3.Utils.ensRegistryABI) throws {
            self.contract = try Contract(abiString: abiString, address: contractAddress, chainId: chainId)
            self.contractAddress = contractAddress
        }
        
        // MARK: - Write Transactions
        
        public func setOwner(node: String, owner: EthereumAddress) throws -> CodableTransaction {
            try contract.createWriteTransaction(method: "setOwner", parameters: [resolveNameHash(node), owner])
        }
        
        public func setSubnodeOwner(node: String, label: String, owner: EthereumAddress) throws -> CodableTransaction {
            try contract.createWriteTransaction(
                method: "setSubnodeOwner",
                parameters: [resolveNameHash(node), resolveNameHash(label), owner]
            )
        }
        
        public func setResolver(node: String, resolver: EthereumAddress) throws -> CodableTransaction {
            try contract.createWriteTransaction(method: "setResolver", parameters: [resolveNameHash(node), resolver])
        }
        
        public func setTTL(node: String, ttl: BigUInt) throws -> CodableTransaction {
            try contract.createWriteTransaction(method: "setTTL", parameters: [resolveNameHash(node), ttl])
        }
        
        // MARK: - Read Functions
        
        public func getOwner(node: String, using web3: Web3) async throws -> EthereumAddress {
            let executor = ContractReadExecutor(contract: contract, web3: web3)
            return try await executor.call(method: "owner", parameters: [resolveNameHash(node)])
        }
        
        public func getResolver(forDomain domain: String, using web3: Web3) async throws -> Resolver {
            let executor = ContractReadExecutor(contract: contract, web3: web3)
            let resolverAddress: EthereumAddress = try await executor.call(method: "resolver", parameters: [resolveNameHash(domain)])
            return try Resolver(contractAddress: resolverAddress, chainId: contract.chainId)
        }
        
        public func getTTL(node: String, using web3: Web3) async throws -> BigUInt {
            let executor = ContractReadExecutor(contract: contract, web3: web3)
            return try await executor.call(method: "ttl", parameters: [resolveNameHash(node)])
        }
        
        // MARK: - Helpers
        
        private func resolveNameHash(_ name: String) throws -> Data {
            guard let hash = NameHash.nameHash(name) else {
                throw Web3Error.processingError(desc: "Invalid name hash")
            }
            return hash
        }
    }
}

public extension ENS.Registry {
    static func registryAddress(for chainId: BigUInt) throws -> EthereumAddress {
        switch chainId {
            case 1:
                return EthereumAddress("0x00000000000C2E074eC69A0dFb2997BA6C7d2e1e")! // Ethereum Mainnet
            case 5:
                return EthereumAddress("0x112234455c3a32fd11230c42e7bccd4a84e02010")! // Goerli Testnet
            case 11155111:
                return EthereumAddress("0x00000000000C2E074eC69A0dFb2997BA6C7d2e1e")! // Sepolia uses same as mainnet
            default:
                throw Web3Error.inputError(desc: "ENS Registry is not known for chain ID \(chainId).")
        }
    }
}
