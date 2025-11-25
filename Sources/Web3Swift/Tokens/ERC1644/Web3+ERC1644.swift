//
//  Web3+ERC1644.swift
//
//  Created by Anton Grigorev on 19/12/2018.
//  Major rewrite by Bailey Nahi on 08/08/2025.
//  Copyright © 2018 The Matter Inc. All rights reserved.
//

import BigInt
import Foundation
import Web3Core

// Controller Token Operation Standard
public protocol IERC1644: IERC20 {
    func isControllable(using web3: Web3) async throws -> Bool
    func controllerTransfer(from: EthereumAddress, to: EthereumAddress, originalOwner: EthereumAddress, amount: String, data: [UInt8], operatorData: [UInt8], using web3: Web3) async throws -> CodableTransaction
    func controllerRedeem(from: EthereumAddress, tokenHolder: EthereumAddress, amount: String, data: [UInt8], operatorData: [UInt8], using web3: Web3) async throws -> CodableTransaction
}

public final class ERC1644: ERC20, IERC1644 {
    public override init(address: EthereumAddress, chainId: BigUInt, abiString: String = Web3.Utils.erc1644ABI) throws {
        try super.init(address: address, chainId: chainId, abiString: abiString)
    }
    
    public func isControllable(using web3: Web3) async throws -> Bool {
        let executor = ContractReadExecutor(contract: contract, web3: web3)
        return try await executor.call(method: "isControllable")
    }
    
    public func controllerTransfer(
        from: EthereumAddress,
        to: EthereumAddress,
        originalOwner: EthereumAddress,
        amount: String,
        data: [UInt8],
        operatorData: [UInt8],
        using web3: Web3
    ) async throws -> CodableTransaction {
        let value = try await parseAmount(amount, using: web3)
        return try contract.createWriteTransaction(
            method: "controllerTransfer",
            parameters: [originalOwner, to, value, data, operatorData],
            from: from
        )
    }
    
    public func controllerRedeem(
        from: EthereumAddress,
        tokenHolder: EthereumAddress,
        amount: String,
        data: [UInt8],
        operatorData: [UInt8],
        using web3: Web3
    ) async throws -> CodableTransaction {
        let value = try await parseAmount(amount, using: web3)
        return try contract.createWriteTransaction(
            method: "controllerRedeem",
            parameters: [tokenHolder, value, data, operatorData],
            from: from
        )
    }
}
