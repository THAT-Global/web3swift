//
//  ENSReverseRegistrar.swift
//
//  Created by Anton on 20/04/2019.
//  Major rewrite by Bailey Nahi on 08/08/2025.
//  Copyright © 2019 The Matter Inc. All rights reserved.
//

import BigInt
import Foundation
import Web3Core

public extension ENS {
    struct ReverseRegistrar {
        public let contract: Contract
        public let contractAddress: EthereumAddress
        
        public init(contractAddress: EthereumAddress, chainId: BigUInt, abiString: String = Web3.Utils.reverseRegistrarABI) throws {
            self.contract = try Contract(abiString: abiString, address: contractAddress, chainId: chainId)
            self.contractAddress = contractAddress
        }
        
        // MARK: - Write Transactions
        
        public func claimAddress(owner: EthereumAddress) throws -> CodableTransaction {
            try contract.createWriteTransaction(method: "claim", parameters: [owner])
        }
        
        public func claimAddressWithResolver(owner: EthereumAddress, resolver: EthereumAddress) throws -> CodableTransaction {
            try contract.createWriteTransaction(method: "claimWithResolver", parameters: [owner, resolver])
        }
        
        public func setName(name: String) throws -> CodableTransaction {
            try contract.createWriteTransaction(method: "setName", parameters: [name])
        }
        
        // MARK: - Read Functions
        
        public func getReverseRecordName(for address: EthereumAddress, using web3: Web3) async throws -> Data {
            let executor = ContractReadExecutor(contract: contract, web3: web3)
            return try await executor.call(method: "node", parameters: [address])
        }
        
        public func getDefaultResolver(using web3: Web3) async throws -> EthereumAddress {
            let executor = ContractReadExecutor(contract: contract, web3: web3)
            return try await executor.call(method: "defaultResolver")
        }
    }
}
