//
//  RegistrarController.swift
//
//  Created by Anton on 15/04/2019.
//  Major rewrite by Bailey Nahi on 08/08/2025.
//  Copyright © 2019 The Matter Inc. All rights reserved.
//

import BigInt
import Foundation
import Web3Core

public extension ENS {
    struct ETHRegistrarController {
        public let contract: Contract
        public let contractAddress: EthereumAddress
        
        public init(contractAddress: EthereumAddress, chainId: BigUInt, abiString: String = Web3.Utils.ethRegistrarControllerABI) throws {
            self.contract = try Contract(abiString: abiString, address: contractAddress, chainId: chainId)
            self.contractAddress = contractAddress
        }
        
        // MARK: - Write Transactions
        
        public func submitCommitment(commitment: Data) throws -> CodableTransaction {
            try contract.createWriteTransaction(method: "commit", parameters: [commitment])
        }
        
        public func registerName(name: String, owner: EthereumAddress, duration: UInt, secret: String, priceInEther: String) throws -> CodableTransaction {
            guard let value = Utilities.parseToBigUInt(priceInEther, units: .ether) else {
                throw Web3Error.inputError(desc: "Invalid price string")
            }
            return try contract.createWriteTransaction(
                method: "register",
                parameters: [name, owner.address, duration, secret],
                value: value
            )
        }
        
        public func extendNameRegistration(name: String, duration: UInt, priceInEther: String) throws -> CodableTransaction {
            guard let value = Utilities.parseToBigUInt(priceInEther, units: .ether) else {
                throw Web3Error.inputError(desc: "Invalid price string")
            }
            return try contract.createWriteTransaction(
                method: "renew",
                parameters: [name, duration],
                value: value
            )
        }
        
        @available(*, message: "Available for only owner")
        public func withdraw() throws -> CodableTransaction {
            try contract.createWriteTransaction(method: "withdraw")
        }
        
        // MARK: - Read Functions
        
        public func getRentPrice(name: String, duration: UInt, using web3: Web3) async throws -> BigUInt {
            let executor = ContractReadExecutor(contract: contract, web3: web3)
            return try await executor.call(method: "rentPrice", parameters: [name, duration])
        }
        
        public func checkNameValidity(name: String, using web3: Web3) async throws -> Bool {
            let executor = ContractReadExecutor(contract: contract, web3: web3)
            return try await executor.call(method: "valid", parameters: [name])
        }
        
        public func isNameAvailable(name: String, using web3: Web3) async throws -> Bool {
            let executor = ContractReadExecutor(contract: contract, web3: web3)
            return try await executor.call(method: "available", parameters: [name])
        }
        
        public func calculateCommitmentHash(name: String, owner: EthereumAddress, secret: String, using web3: Web3) async throws -> Data {
            let executor = ContractReadExecutor(contract: contract, web3: web3)
            return try await executor.call(method: "makeCommitment", parameters: [name, owner.address, secret])
        }
    }
}
