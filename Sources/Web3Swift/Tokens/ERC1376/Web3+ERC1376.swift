//
//  Web3+ERC1376.swift
//
//  Created by Anton Grigorev on 20/12/2018.
//  Copyright © 2018 The Matter Inc. All rights reserved.
//

import BigInt
import Foundation
import Web3Core

public enum IERC1376DelegateMode: UInt {
    case PublicMsgSender = 0
    case PublicTxOrigin = 1
    case PrivateMsgSender = 2
    case PrivateTxOrigin = 3
}

public struct DirectDebitInfo {
    let amount: BigUInt
    let startTime: BigUInt
    let interval: BigUInt
}

public struct DirectDebit {
    let info: DirectDebitInfo
    let epoch: BigUInt
}

extension DirectDebit: Hashable {
}

extension DirectDebitInfo: Hashable {
}

// Service-Friendly Token Standard
public protocol IERC1376: IERC20 {
    func approve(from: EthereumAddress, spender: EthereumAddress, expectedValue: String, newValue: String, using web3: Web3) async throws -> CodableTransaction
    func increaseAllowance(from: EthereumAddress, spender: EthereumAddress, value: String, using web3: Web3) async throws -> CodableTransaction
    func decreaseAllowance(from: EthereumAddress, spender: EthereumAddress, value: String, strict: Bool, using web3: Web3) async throws -> CodableTransaction
    func setERC20ApproveChecking(from: EthereumAddress, approveChecking: Bool) async throws -> CodableTransaction

    func spendableAllowance(owner: EthereumAddress, spender: EthereumAddress, using web3: Web3) async throws -> BigUInt
    func transfer(from: EthereumAddress, data: String, using web3: Web3) async throws -> CodableTransaction
    func transferAndCall(from: EthereumAddress, to: EthereumAddress, value: String, data: [UInt8], using web3: Web3) async throws -> CodableTransaction

    func nonceOf(owner: EthereumAddress, using web3: Web3) async throws -> BigUInt
    func increaseNonce(from: EthereumAddress) async throws -> CodableTransaction
    func delegateTransferAndCall(
        from: EthereumAddress,
        nonce: BigUInt,
        fee: BigUInt,
        gasAmount: BigUInt,
        to: EthereumAddress,
        value: String,
        data: [UInt8],
        mode: IERC1376DelegateMode,
        v: UInt8,
        r: Data,
        s: Data,
        using web3: Web3
    ) async throws -> CodableTransaction

    func directDebit(debtor: EthereumAddress, receiver: EthereumAddress, using web3: Web3) async throws -> DirectDebit
    func setupDirectDebit(from: EthereumAddress, receiver: EthereumAddress, info: DirectDebitInfo) async throws -> CodableTransaction
    func terminateDirectDebit(from: EthereumAddress, receiver: EthereumAddress) async throws -> CodableTransaction
    func withdrawDirectDebit(from: EthereumAddress, debtor: EthereumAddress) async throws -> CodableTransaction
    func withdrawDirectDebit(from: EthereumAddress, debtors: [EthereumAddress], strict: Bool) async throws -> CodableTransaction
}

public final class ERC1376: ERC20, IERC1376 {
    public override init(address: EthereumAddress, chainId: BigUInt, abiString: String = Web3.Utils.erc1376ABI) throws {
        try super.init(address: address, chainId: chainId, abiString: abiString)
    }

    public func approve(from: EthereumAddress, spender: EthereumAddress, expectedValue: String, newValue: String, using web3: Web3) async throws -> CodableTransaction {
        let expected = try await parseAmount(expectedValue, using: web3)
        let new = try await parseAmount(newValue, using: web3)
        return try contract.createWriteTransaction(method: "approve", parameters: [spender, expected, new], from: from)
    }

    public func increaseAllowance(from: EthereumAddress, spender: EthereumAddress, value: String, using web3: Web3) async throws -> CodableTransaction {
        let amount = try await parseAmount(value, using: web3)
        return try contract.createWriteTransaction(method: "increaseAllowance", parameters: [spender, amount], from: from)
    }

    public func decreaseAllowance(from: EthereumAddress, spender: EthereumAddress, value: String, strict: Bool, using web3: Web3) async throws -> CodableTransaction {
        let amount = try await parseAmount(value, using: web3)
        return try contract.createWriteTransaction(method: "decreaseAllowance", parameters: [spender, amount, strict], from: from)
    }

    public func setERC20ApproveChecking(from: EthereumAddress, approveChecking: Bool) async throws -> CodableTransaction {
        return try contract.createWriteTransaction(method: "setERC20ApproveChecking", parameters: [approveChecking], from: from)
    }

    public func spendableAllowance(owner: EthereumAddress, spender: EthereumAddress, using web3: Web3) async throws -> BigUInt {
        let executor = ContractReadExecutor(contract: contract, web3: web3)
        return try await executor.call(method: "spendableAllowance", parameters: [owner, spender])
    }

    public func transfer(from: EthereumAddress, data: String, using web3: Web3) async throws -> CodableTransaction {
        let amount = try await parseAmount(data, using: web3)
        return try contract.createWriteTransaction(method: "transfer", parameters: [amount], from: from)
    }

    public func transferAndCall(from: EthereumAddress, to: EthereumAddress, value: String, data: [UInt8], using web3: Web3) async throws -> CodableTransaction {
        let amount = try await parseAmount(value, using: web3)
        return try contract.createWriteTransaction(method: "transferAndCall", parameters: [to, amount, data], from: from)
    }

    public func nonceOf(owner: EthereumAddress, using web3: Web3) async throws -> BigUInt {
        let executor = ContractReadExecutor(contract: contract, web3: web3)
        return try await executor.call(method: "nonceOf", parameters: [owner])
    }

    public func increaseNonce(from: EthereumAddress) async throws -> CodableTransaction {
        return try contract.createWriteTransaction(method: "increaseNonce", from: from)
    }

    public func delegateTransferAndCall(
        from: EthereumAddress,
        nonce: BigUInt,
        fee: BigUInt,
        gasAmount: BigUInt,
        to: EthereumAddress,
        value: String,
        data: [UInt8],
        mode: IERC1376DelegateMode,
        v: UInt8,
        r: Data,
        s: Data,
        using web3: Web3
    ) async throws -> CodableTransaction {
        let amount = try await parseAmount(value, using: web3)
        return try contract.createWriteTransaction(
            method: "delegateTransferAndCall",
            parameters: [nonce, fee, gasAmount, to, amount, data, mode.rawValue, v, r, s],
            from: from
        )
    }

    public func directDebit(debtor: EthereumAddress, receiver: EthereumAddress, using web3: Web3) async throws -> DirectDebit {
        let executor = ContractReadExecutor(contract: contract, web3: web3)
        return try await executor.call(method: "directDebit", parameters: [debtor, receiver])
    }

    public func setupDirectDebit(from: EthereumAddress, receiver: EthereumAddress, info: DirectDebitInfo) async throws -> CodableTransaction {
        return try contract.createWriteTransaction(method: "setupDirectDebit", parameters: [receiver, info], from: from)
    }

    public func terminateDirectDebit(from: EthereumAddress, receiver: EthereumAddress) async throws -> CodableTransaction {
        return try contract.createWriteTransaction(method: "terminateDirectDebit", parameters: [receiver], from: from)
    }

    public func withdrawDirectDebit(from: EthereumAddress, debtor: EthereumAddress) async throws -> CodableTransaction {
        return try contract.createWriteTransaction(method: "withdrawDirectDebit", parameters: [debtor], from: from)
    }

    public func withdrawDirectDebit(from: EthereumAddress, debtors: [EthereumAddress], strict: Bool) async throws -> CodableTransaction {
        return try contract.createWriteTransaction(method: "withdrawDirectDebit", parameters: [debtors, strict], from: from)
    }
}
