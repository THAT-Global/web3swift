//
//  IERC20.swift
//  THAT
//
//  Created by Bailey Nahi on 07/08/2025.
//

import BigInt
import Foundation
import Web3Core

// Token Standard
public protocol IERC20: ERC20BaseProperties {
    // MARK: - Balance
    func getBalanceTxn(account: EthereumAddress) throws -> CodableTransaction
    func getBalance(account: EthereumAddress, using web3: Web3) async throws -> BigUInt

    // MARK: - Allowance
    func getAllowanceTxn(originalOwner: EthereumAddress, delegate: EthereumAddress) throws -> CodableTransaction
    func getAllowance(originalOwner: EthereumAddress, delegate: EthereumAddress, using web3: Web3) async throws -> BigUInt

    // MARK: - Total Supply
    func totalSupplyTxn() throws -> CodableTransaction
    func totalSupply(using web3: Web3) async throws -> BigUInt

    // MARK: - Approve
    func approveTxn(from: EthereumAddress, spender: EthereumAddress, value: BigUInt) throws -> CodableTransaction
    func approveTxn(from: EthereumAddress, spender: EthereumAddress, amount: String, using web3: Web3) async throws -> CodableTransaction

    // MARK: - Transfer
    func transferTxn(from: EthereumAddress, to: EthereumAddress, value: BigUInt) throws -> CodableTransaction
    func transferTxn(from: EthereumAddress, to: EthereumAddress, amount: String, withDecimals: Int) throws -> CodableTransaction
    func transferTxn(from: EthereumAddress, to: EthereumAddress, amount: String, using web3: Web3) async throws -> CodableTransaction

    // MARK: - Transfer From
    func transferFromTxn(from: EthereumAddress, to: EthereumAddress, originalOwner: EthereumAddress, value: BigUInt) throws -> CodableTransaction
    func transferFromTxn(from: EthereumAddress, to: EthereumAddress, originalOwner: EthereumAddress, amount: String, using web3: Web3) async throws -> CodableTransaction

    // MARK: - Set Allowance
    func setAllowanceTxn(from: EthereumAddress, to: EthereumAddress, newAmount: BigUInt) throws -> CodableTransaction
    func setAllowanceTxn(from: EthereumAddress, to: EthereumAddress, newAmount: String, using web3: Web3) async throws -> CodableTransaction
}
