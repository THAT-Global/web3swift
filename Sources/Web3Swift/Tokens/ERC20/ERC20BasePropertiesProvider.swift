//
//  ERC20BasePropertiesProvider.swift
//
//
//  Created by Jann Driessen on 21.11.22.
//

import BigInt
import Foundation
import Web3Core

/// The default implementation of access of common [ERC-20](https://eips.ethereum.org/EIPS/eip-20#methods) properties `name`, `symbol` and `decimals`.
public final class ERC20BasePropertiesProvider {
    private(set) public var name: String?
    private(set) public var symbol: String?
    private(set) public var decimals: Int?
    
    private let contract: Contract
    private(set) public var hasReadProperties: Bool = false
    
    public init(contract: Contract) {
        self.contract = contract
    }
    
    public func readProperties(using web3: Web3) async throws {
        guard !hasReadProperties else { return }
        
        let nameTxn = try contract.createReadTransaction(method: "name")
        let nameData = try await web3.eth.callTransaction(nameTxn)
        name = try contract.abi.decodeReturnData("name", data: nameData)["0"] as? String
        
        let symbolTxn = try contract.createReadTransaction(method: "symbol")
        let symbolData = try await web3.eth.callTransaction(symbolTxn)
        symbol = try contract.abi.decodeReturnData("symbol", data: symbolData)["0"] as? String
        
        let decimalsTxn = try contract.createReadTransaction(method: "decimals")
        let decimalsData = try await web3.eth.callTransaction(decimalsTxn)
        let decimalsResult = try contract.abi.decodeReturnData("decimals", data: decimalsData)
        guard let rawDecimals = decimalsResult["0"] as? BigUInt else {
            throw Web3Error.inputError(desc: "Invalid or missing decimals")
        }
        decimals = Int(rawDecimals)
        
        hasReadProperties = true
    }
    
    public func setProperties(name: String, symbol: String, decimals: Int) {
        guard !hasReadProperties else { return }
        self.name = name
        self.symbol = symbol
        self.decimals = decimals
        hasReadProperties = true
    }
}
