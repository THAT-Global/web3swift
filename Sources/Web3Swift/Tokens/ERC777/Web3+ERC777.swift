//
//  Web3+ERC777.swift
//
//  Created by Anton Grigorev on 07/12/2018.
//  Major rewrite by Bailey Nahi on 08/08/2025.
//  Copyright © 2018 The Matter Inc. All rights reserved.
//

import BigInt
import Foundation
import Web3Core

// A New Advanced Token Standard
public protocol IERC777: IERC20, IERC820 {
    func getDefaultOperators(using web3: Web3) async throws -> [EthereumAddress]
    func getGranularity(using web3: Web3) async throws -> BigUInt
    func authorizeTxn(from: EthereumAddress, operator user: EthereumAddress) throws -> CodableTransaction
    func revokeTxn(from: EthereumAddress, operator user: EthereumAddress) throws -> CodableTransaction
    func isOperatorFor(operator user: EthereumAddress, tokenHolder: EthereumAddress, using web3: Web3) async throws -> Bool
    func sendTxn(from: EthereumAddress, to: EthereumAddress, amount: String, data: [UInt8], using web3: Web3) async throws -> CodableTransaction
    func operatorSendTxn(from: EthereumAddress, to: EthereumAddress, originalOwner: EthereumAddress, amount: String, data: [UInt8], operatorData: [UInt8], using web3: Web3) async throws -> CodableTransaction
    func burnTxn(from: EthereumAddress, amount: String, data: [UInt8], using web3: Web3) async throws -> CodableTransaction
    func operatorBurnTxn(from: EthereumAddress, amount: String, originalOwner: EthereumAddress, data: [UInt8], operatorData: [UInt8], using web3: Web3) async throws -> CodableTransaction
}

// This namespace contains functions to work with ERC777 tokens.
public class ERC777: ERC20, IERC777 {
    public override init(address: EthereumAddress, chainId: BigUInt, abiString: String = Web3.Utils.erc777ABI) throws {
        try super.init(address: address, chainId: chainId, abiString: abiString)
    }
    
    public func getDefaultOperators(using web3: Web3) async throws -> [EthereumAddress] {
        let executor = ContractReadExecutor(contract: contract, web3: web3)
        return try await executor.call(method: "defaultOperators")
    }
    
    public func getGranularity(using web3: Web3) async throws -> BigUInt {
        let executor = ContractReadExecutor(contract: contract, web3: web3)
        return try await executor.call(method: "granularity")
    }
    
    public func authorizeTxn(from: EthereumAddress, operator user: EthereumAddress) throws -> CodableTransaction {
        try contract.createWriteTransaction(method: "authorizeOperator", parameters: [user], from: from)
    }
    
    public func revokeTxn(from: EthereumAddress, operator user: EthereumAddress) throws -> CodableTransaction {
        try contract.createWriteTransaction(method: "revokeOperator", parameters: [user], from: from)
    }
    
    public func isOperatorFor(operator user: EthereumAddress, tokenHolder: EthereumAddress, using web3: Web3) async throws -> Bool {
        let executor = ContractReadExecutor(contract: contract, web3: web3)
        return try await executor.call(method: "isOperatorFor", parameters: [user, tokenHolder])
    }
    
    public func sendTxn(from: EthereumAddress, to: EthereumAddress, amount: String, data: [UInt8], using web3: Web3) async throws -> CodableTransaction {
        let value = try await parseAmount(amount, using: web3)
        return try contract.createWriteTransaction(method: "send", parameters: [to, value, data], from: from)
    }
    
    public func operatorSendTxn(from: EthereumAddress, to: EthereumAddress, originalOwner: EthereumAddress, amount: String, data: [UInt8], operatorData: [UInt8], using web3: Web3) async throws -> CodableTransaction {
        let value = try await parseAmount(amount, using: web3)
        return try contract.createWriteTransaction(method: "operatorSend", parameters: [originalOwner, to, value, data, operatorData], from: from)
    }
    
    public func burnTxn(from: EthereumAddress, amount: String, data: [UInt8], using web3: Web3) async throws -> CodableTransaction {
        let value = try await parseAmount(amount, using: web3)
        return try contract.createWriteTransaction(method: "burn", parameters: [value, data], from: from)
    }
    
    public func operatorBurnTxn(from: EthereumAddress, amount: String, originalOwner: EthereumAddress, data: [UInt8], operatorData: [UInt8], using web3: Web3) async throws -> CodableTransaction {
        let value = try await parseAmount(amount, using: web3)
        return try contract.createWriteTransaction(method: "operatorBurn", parameters: [originalOwner, value, data, operatorData], from: from)
    }
    
    // MARK: - IERC820
    
    public func canImplementInterfaceForAddress(interfaceHash: Data, addr: EthereumAddress, using web3: Web3) async throws -> Data {
        let executor = ContractReadExecutor(contract: contract, web3: web3)
        return try await executor.call(method: "canImplementInterfaceForAddress", parameters: [interfaceHash, addr])
    }
    
    public func getInterfaceImplementer(addr: EthereumAddress, interfaceHash: Data, using web3: Web3) async throws -> EthereumAddress {
        let executor = ContractReadExecutor(contract: contract, web3: web3)
        return try await executor.call(method: "getInterfaceImplementer", parameters: [addr, interfaceHash])
    }
    
    public func setInterfaceImplementerTxn(from: EthereumAddress, addr: EthereumAddress, interfaceHash: Data, implementer: EthereumAddress) throws -> CodableTransaction {
        try contract.createWriteTransaction(method: "setInterfaceImplementer", parameters: [addr, interfaceHash, implementer], from: from)
    }
    
    public func setManagerTxn(from: EthereumAddress, addr: EthereumAddress, newManager: EthereumAddress) throws -> CodableTransaction {
        try contract.createWriteTransaction(method: "setManager", parameters: [addr, newManager], from: from)
    }
    
    public func interfaceHash(interfaceName: String, using web3: Web3) async throws -> Data {
        let executor = ContractReadExecutor(contract: contract, web3: web3)
        return try await executor.call(method: "interfaceHash", parameters: [interfaceName])
    }
    
    public func updateERC165CacheTxn(from: EthereumAddress, contract: EthereumAddress, interfaceId: [UInt8]) throws -> CodableTransaction {
        try self.contract.createWriteTransaction(method: "updateERC165Cache", parameters: [contract, interfaceId], from: from)
    }
    
    public func supportsInterface(interfaceID: String, using web3: Web3) async throws -> Bool {
        let executor = ContractReadExecutor(contract: contract, web3: web3)
        return try await executor.call(method: "supportsInterface", parameters: [interfaceID])
    }
}
