//
//  ContractReadExecutor.swift
//  Created by Bailey Nahi on 26/11/2025.
//

import BigInt
import Foundation
import Web3Core

public struct ContractReadExecutor {
    public let contract: Contract
    public let web3: Web3
    
    public init(contract: Contract, web3: Web3) {
        self.contract = contract
        self.web3 = web3
    }
    
    public func call(method: String, parameters: [Any] = [], from: EthereumAddress? = nil, block: BlockNumber = .latest) async throws -> [String: Any] {
        let txn = try contract.createReadTransaction(method: method, parameters: parameters, from: from, callOnBlock: block)
        return try await call(method: method, txn: txn)
    }
    
    public func call<T>(method: String, parameters: [Any] = [], from: EthereumAddress? = nil, block: BlockNumber = .latest) async throws -> T {
        let result = try await call(method: method, parameters: parameters, from: from, block: block)
        guard let value = result["0"] as? T else {
            throw Web3Error.processingError(desc: "\(method) returned unexpected type: \(T.self)")
        }
        return value
    }
    
    public func call(method: String, txn: CodableTransaction) async throws -> [String: Any] {
        let raw = try await web3.eth.callTransaction(txn)
        return try contract.abi.decodeReturnData(method, data: raw)
    }
    
    public func call<T>(method: String, txn: CodableTransaction) async throws -> T {
        let result = try await call(method: method, txn: txn)
        guard let value = result["0"] as? T else {
            throw Web3Error.processingError(desc: "\(method) returned unexpected type: \(T.self)")
        }
        return value
    }
}
