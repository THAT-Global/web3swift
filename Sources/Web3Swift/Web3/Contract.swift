//
//  Contract.swift
//  THAT
//
//  Created by Bailey Nahi on 11/08/2025.
//

import BigInt
import Foundation
import Web3Core

public struct Contract {
    public let abi: EthereumContract
    public let address: EthereumAddress
    public let chainId: BigUInt
    
    public init(abiString: String, address: EthereumAddress, chainId: BigUInt, abiVersion: Int = 2) throws {
        switch abiVersion {
            case 2:
                self.abi = try EthereumContract(abiString, at: address)
                self.address = address
                self.chainId = chainId
            default:
                throw Web3Error.contractError(desc: "Unsupported abiVersion: \(abiVersion)")
        }
    }
    
    public func createReadTransaction(
        method: String,
        parameters: [Any] = [],
        extraData: Data = Data(),
        from: EthereumAddress? = nil,
        callOnBlock: BlockNumber = .latest,
        type: TransactionType = .eip1559
    ) throws -> CodableTransaction {
        guard let data = abi.method(method, parameters: parameters, extraData: extraData) else {
            throw Web3Error.inputError(desc: "Could not encode method: \(method)")
        }
        
        return CodableTransaction(
            type: type,
            from: from,
            to: address,
            chainID: chainId,
            data: data,
            callOnBlock: callOnBlock
        )
    }
    
    public func createWriteTransaction(
        method: String,
        parameters: [Any] = [],
        extraData: Data = Data(),
        from: EthereumAddress? = nil,
        value: BigUInt = 0,
        nonce: BigUInt = .zero,
        callOnBlock: BlockNumber = .latest,
        type: TransactionType = .eip1559
    ) throws -> CodableTransaction {
        guard let data = abi.method(method, parameters: parameters, extraData: extraData) else {
            throw Web3Error.inputError(desc: "Could not encode method: \(method)")
        }
        
        return CodableTransaction(
            type: type,
            from: from,
            to: address,
            nonce: nonce,
            chainID: chainId,
            value: value,
            data: data,
            callOnBlock: callOnBlock
        )
    }
    
    public func prepareDeployTransaction(
        bytecode: Data,
        constructor: ABI.Element.Constructor? = nil,
        parameters: [Any]? = nil,
        extraData: Data = Data(),
        from: EthereumAddress,
        value: BigUInt = 0,
        nonce: BigUInt = .zero,
        callOnBlock: BlockNumber = .latest
    ) throws -> CodableTransaction {
        guard let data = abi.deploy(bytecode: bytecode, constructor: constructor, parameters: parameters, extraData: extraData) else {
            throw Web3Error.inputError(desc: "Failed to encode contract deployment")
        }
        
        return CodableTransaction(
            from: from,
            to: .contractDeploymentAddress(),
            nonce: nonce,
            chainID: chainId,
            value: value,
            data: data,
            callOnBlock: callOnBlock
        )
    }
}
