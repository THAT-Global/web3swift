//
//  Web3+ERC1643.swift
//
//  Created by Anton Grigorev on 19/12/2018.
//  Copyright © 2018 The Matter Inc. All rights reserved.
//

import BigInt
import Foundation
import Web3Core

// Document Management Standard
public protocol IERC1643: IERC20 {
    // Document Management
    func getDocument(name: Data, using web3: Web3) async throws -> (String, Data)
    func setDocumentTxn(from: EthereumAddress, name: Data, uri: String, documentHash: Data) throws -> CodableTransaction
    func removeDocumentTxn(from: EthereumAddress, name: Data) throws -> CodableTransaction
    func getAllDocuments(using web3: Web3) async throws -> [Data]
}

public final class ERC1643: ERC20, IERC1643 {
    public init(contractAddress: EthereumAddress, chainId: BigUInt) throws {
        try super.init(address: contractAddress, chainId: chainId, abiString: Web3.Utils.erc1643ABI)
    }
    
    // MARK: - Document Management
    
    public func getDocument(name: Data, using web3: Web3) async throws -> (String, Data) {
        let executor = ContractReadExecutor(contract: contract, web3: web3)
        return try await executor.call(method: "getDocument", parameters: [name])
    }
    
    public func setDocumentTxn(from: EthereumAddress, name: Data, uri: String, documentHash: Data) throws -> CodableTransaction {
        try contract.createWriteTransaction(method: "setDocument", parameters: [name, uri, documentHash], from: from)
    }
    
    public func removeDocumentTxn(from: EthereumAddress, name: Data) throws -> CodableTransaction {
        try contract.createWriteTransaction(method: "removeDocument", parameters: [name], from: from)
    }
    
    public func getAllDocuments(using web3: Web3) async throws -> [Data] {
        let executor = ContractReadExecutor(contract: contract, web3: web3)
        return try await executor.call(method: "getAllDocuments")
    }
}
