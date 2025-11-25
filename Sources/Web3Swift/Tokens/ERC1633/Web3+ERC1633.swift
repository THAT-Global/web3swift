//
//  Web3+ERC1634.swift
//
//  Created by Anton Grigorev on 20/12/2018.
//  Major rewrite by Bailey Nahi on 08/08/2025.
//  Copyright © 2018 The Matter Inc. All rights reserved.
//

import BigInt
import Foundation
import Web3Core

// Re-Fungible Token Standard (RFT)
public protocol IERC1633: IERC20, IERC165 {
    func parentToken(using web3: Web3) async throws -> EthereumAddress
    func parentTokenId(using web3: Web3) async throws -> BigUInt
}

public final class ERC1633: ERC20, IERC1633 {
    public override init(address: EthereumAddress, chainId: BigUInt, abiString: String = Web3.Utils.erc1633ABI) throws {
        try super.init(address: address, chainId: chainId, abiString: abiString)
    }
    
    public func parentToken(using web3: Web3) async throws -> EthereumAddress {
        let executor = ContractReadExecutor(contract: contract, web3: web3)
        return try await executor.call(method: "parentToken")
    }
    
    public func parentTokenId(using web3: Web3) async throws -> BigUInt {
        let executor = ContractReadExecutor(contract: contract, web3: web3)
        return try await executor.call(method: "parentTokenId")
    }
    
    public func supportsInterface(interfaceID: String, using web3: Web3) async throws -> Bool {
        let executor = ContractReadExecutor(contract: contract, web3: web3)
        return try await executor.call(method: "supportsInterface", parameters: [interfaceID])
    }
}
