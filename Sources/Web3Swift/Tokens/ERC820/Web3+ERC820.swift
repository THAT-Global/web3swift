//
//  Web3+ERC820.swift
//
//  Created by Anton Grigorev on 15/12/2018.
//  Copyright © 2018 The Matter Inc. All rights reserved.
//

import Foundation
import Web3Core

// Pseudo-introspection using a registry contract
public protocol IERC820: IERC165 {
    func canImplementInterfaceForAddress(interfaceHash: Data, addr: EthereumAddress, using web3: Web3) async throws -> Data
    func getInterfaceImplementer(addr: EthereumAddress, interfaceHash: Data, using web3: Web3) async throws -> EthereumAddress
    func setInterfaceImplementerTxn(from: EthereumAddress, addr: EthereumAddress, interfaceHash: Data, implementer: EthereumAddress) throws -> CodableTransaction
    func setManagerTxn(from: EthereumAddress, addr: EthereumAddress, newManager: EthereumAddress) throws -> CodableTransaction
    func interfaceHash(interfaceName: String, using web3: Web3) async throws -> Data
    func updateERC165CacheTxn(from: EthereumAddress, contract: EthereumAddress, interfaceId: [UInt8]) throws -> CodableTransaction
}
