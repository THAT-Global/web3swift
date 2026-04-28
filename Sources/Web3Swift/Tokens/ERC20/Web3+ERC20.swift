//
//  Created by Alex Vlasov.
//  Major rewrite by Bailey Nahi on 08/08/2025.
//  Copyright © 2018 Alex Vlasov. All rights reserved.
//

import BigInt
import Foundation
import Web3Core

// This namespace contains functions to work with ERC20 tokens.
public class ERC20: IERC20, ERC20BaseProperties {
    public let contract: Contract
    public let contractAddress: EthereumAddress
    public let basePropertiesProvider: ERC20BasePropertiesProvider
    
    public init(address: EthereumAddress, chainId: BigUInt, abiString: String = Web3.Utils.erc20ABI) throws {
        // guard address != EthereumAddress.native else { throw Web3Error.contractError(desc: "Invalid ERC20 address: \(address)") }
        self.contract = try Contract(abiString: abiString, address: address, chainId: chainId)
        self.contractAddress = address
        self.basePropertiesProvider = ERC20BasePropertiesProvider(contract: contract)
    }
        
    public func getAllowanceTxn(originalOwner: EthereumAddress, delegate: EthereumAddress) throws -> CodableTransaction {
        try contract.createReadTransaction(method: "allowance", parameters: [originalOwner, delegate])
    }
        
    public func getAllowance(originalOwner: EthereumAddress, delegate: EthereumAddress, using web3: Web3) async throws -> BigUInt {
        let executor = ContractReadExecutor(contract: contract, web3: web3)
        return try await executor.call(method: "allowance", parameters: [originalOwner, delegate])
    }
    
    public func getBalanceTxn(account: EthereumAddress) throws -> CodableTransaction {
        try contract.createReadTransaction(method: "balanceOf", parameters: [account])
    }
    
    public func getBalance(account: EthereumAddress, using web3: Web3) async throws -> BigUInt {
        let executor = ContractReadExecutor(contract: contract, web3: web3)
        return try await executor.call(method: "balanceOf", parameters: [account])
    }
    
    public func totalSupplyTxn() throws -> CodableTransaction {
        try contract.createReadTransaction(method: "totalSupply")
    }
    
    public func totalSupply(using web3: Web3) async throws -> BigUInt {
        let executor = ContractReadExecutor(contract: contract, web3: web3)
        return try await executor.call(method: "totalSupply")
    }
    
    public func approveTxn(from: EthereumAddress, spender: EthereumAddress, value: BigUInt) throws -> CodableTransaction {
        try contract.createWriteTransaction(method: "approve", parameters: [spender, value], from: from )
    }
    
    public func approveTxn(from: EthereumAddress, spender: EthereumAddress, amount: String, using web3: Web3) async throws -> CodableTransaction {
        let value = try await parseAmount(amount, using: web3)
        return try contract.createWriteTransaction(method: "approve", parameters: [spender, value], from: from )
    }
    
    public func transferTxn(from: EthereumAddress, to: EthereumAddress, value: BigUInt) throws -> CodableTransaction {
        try contract.createWriteTransaction(method: "transfer", parameters: [to, value], from: from)
    }

    public func transferTxn(from: EthereumAddress, to: EthereumAddress, amount: String, withDecimals: Int) throws -> CodableTransaction {
        let value = try parseAmount(amount, decimals: withDecimals)
        return try contract.createWriteTransaction(method: "transfer", parameters: [to, value], from: from)
    }

    public func transferTxn(from: EthereumAddress, to: EthereumAddress, amount: String, using web3: Web3) async throws -> CodableTransaction {
        let value = try await parseAmount(amount, using: web3)
        return try contract.createWriteTransaction(method: "transfer", parameters: [to, value], from: from)
    }
    
    public func transferFromTxn(from: EthereumAddress, to: EthereumAddress, originalOwner: EthereumAddress, value: BigUInt) throws -> CodableTransaction {
        try contract.createWriteTransaction(method: "transferFrom", parameters: [originalOwner, to, value], from: from)
    }
    
    public func transferFromTxn(from: EthereumAddress, to: EthereumAddress, originalOwner: EthereumAddress, amount: String, using web3: Web3) async throws -> CodableTransaction {
        let value = try await parseAmount(amount, using: web3)
        return try contract.createWriteTransaction(method: "transferFrom", parameters: [originalOwner, to, value], from: from)
    }
    
    public func setAllowanceTxn(from: EthereumAddress, to: EthereumAddress, newAmount: BigUInt) throws -> CodableTransaction {
        try contract.createWriteTransaction(method: "setAllowance", parameters: [to, newAmount], from: from)
    }
    
    public func setAllowanceTxn(from: EthereumAddress, to: EthereumAddress, newAmount: String, using web3: Web3) async throws -> CodableTransaction {
        let value = try await parseAmount(newAmount, using: web3)
        return try contract.createWriteTransaction(method: "setAllowance", parameters: [to, value], from: from)
    }
    
    // MARK: - Helpers
    
    internal func read<T>(_ web3: Web3, method: String) async throws -> T {
        let executor = ContractReadExecutor(contract: contract, web3: web3)
        return try await executor.call(method: method)
    }
    
    private func parseAmount(_ amount: String, decimals: Int) throws -> BigUInt {
        let decimals = self.decimals ?? decimals // on-chain token data takes precedence
        guard let parsed = Utilities.parseToBigUInt(amount, decimals: decimals) else {
            throw Web3Error.inputError(desc: "Failed to parse amount: \(amount)")
        }
        return parsed
    }
    
    internal func parseAmount(_ amount: String, using web3: Web3) async throws -> BigUInt {
        try await basePropertiesProvider.readProperties(using: web3)
        guard let decimals else {
            throw Web3Error.inputError(desc: "Invalid or missing decimals")
        }
        
        guard let parsed = Utilities.parseToBigUInt(amount, decimals: Int(decimals)) else {
            throw Web3Error.inputError(desc: "Failed to parse amount: \(amount)")
        }
        
        return parsed
    }
}

extension ERC20 {
    /// Creates an `ERC20` from a raw token id (string/hex), validating it.
    public static func make(address: String, chainId: BigUInt, abiString: String = Web3.Utils.erc20ABI) throws -> ERC20 {
        guard let tokenAddress = EthereumAddress(address) else { throw ValidationError.invalidAddress }
        return try ERC20(address: tokenAddress, chainId: chainId, abiString: abiString)
    }
    
    /// Creates an `ERC20` and preloads on-chain metadata (`name`, `symbol`, `decimals`).
    public static func makeWithMetadata(address: EthereumAddress, chainId: BigUInt, using web3: Web3) async throws -> ERC20 {
        let erc20 = try ERC20(address: address, chainId: chainId)
        try await erc20.readProperties(using: web3)
        return erc20
    }
    
    /// Bulk-create `ERC20`s with metadata. Simple throttle to avoid rate limits (default ~12 req/sec).
    public static func makeManyWithMetadata(addresses: [EthereumAddress], chainId: BigUInt, using web3: Web3) async throws -> [ERC20] {
        var result: [ERC20] = []
        result.reserveCapacity(addresses.count)
        
        for addr in addresses {
            let token = try await makeWithMetadata(address: addr, chainId: chainId, using: web3)
            result.append(token)
            try await Task.sleep(nanoseconds: 1_000_000_000 / 12)
        }
        return result
    }
}

extension ERC20 {
    public func estimateApproveCost(
        from: EthereumAddress,
        spender: EthereumAddress,
        value: BigUInt,
        using web3: Web3
    ) async throws -> (limit: BigUInt, priceWei: BigUInt) {
        let tx = try approveTxn(from: from, spender: spender, value: value)
        let gasLimit = try await web3.eth.estimateGas(for: tx)
        let gasPrice = try await web3.eth.gasPrice()
        return (gasLimit, gasPrice)
    }
}

extension ERC20: Hashable {
    public static func == (lhs: ERC20, rhs: ERC20) -> Bool {
        return lhs.contractAddress == rhs.contractAddress && lhs.contract.chainId == rhs.contract.chainId
    }
    
    public func hash(into hasher: inout Hasher) {
        hasher.combine(contractAddress)
        hasher.combine(contract.chainId)
    }
}
