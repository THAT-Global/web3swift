//
//  Created by Alex Vlasov.
//  Major rewrite by Bailey Nahi on 08/08/2025.
//  Copyright © 2018 Alex Vlasov. All rights reserved.
//

import BigInt
import Foundation
import Web3Core

public extension ENS {
    struct Resolver {
        public let contract: Contract
        public let contractAddress: EthereumAddress
        
        public enum ContentType: BigUInt {
            case JSON = 1
            case zlibCompressedJSON = 2
            case CBOR = 4
            case URI = 8
        }
        
        public enum InterfaceName {
            case addr, name, content, ABI, pubkey, text
            
            var hash: String {
                switch self {
                    case .addr: return "0x3b3b57de"
                    case .name: return "0x691f3431"
                    case .content: return "0xbc1c58d1"
                    case .ABI: return "0x2203ab56"
                    case .pubkey: return "0xc8690233"
                    case .text: return "0x59d1d43c"
                }
            }
        }
        
        public init(contractAddress: EthereumAddress, chainId: BigUInt, abiString: String = Web3.Utils.resolverABI) throws {
            self.contract = try Contract(abiString: abiString, address: contractAddress, chainId: chainId)
            self.contractAddress = contractAddress
        }
        
        // MARK: - Write Transactions | @available(*, message: "Available for only owner") applies to all writes.
        
        public func setAddress(forNode node: String, address: EthereumAddress) throws -> CodableTransaction {
            try contract.createWriteTransaction(method: "setAddr", parameters: [resolveNameHash(node), address])
        }
        
        public func setCanonicalName(forNode node: String, name: String) throws -> CodableTransaction {
            try contract.createWriteTransaction(method: "setName", parameters: [resolveNameHash(node), name])
        }
        
        public func setContentHash(forNode node: String, hash: String) throws -> CodableTransaction {
            try contract.createWriteTransaction(method: "setContenthash", parameters: [resolveNameHash(node), hash])
        }
        
        public func setContractABI(forNode node: String, contentType: ContentType, data: Data) throws -> CodableTransaction {
            try contract.createWriteTransaction(method: "setABI", parameters: [resolveNameHash(node), contentType.rawValue, data])
        }
        
        public func setPublicKey(forNode node: String, publicKey: PublicKey) throws -> CodableTransaction {
            let pubkey = publicKey.getComponentsWithoutPrefix()
            return try contract.createWriteTransaction(method: "setPubkey", parameters: [resolveNameHash(node), pubkey.x, pubkey.y])
        }
        
        public func setTextData(forNode node: String, key: String, value: String) throws -> CodableTransaction {
            try contract.createWriteTransaction(method: "setText", parameters: [resolveNameHash(node), key, value])
        }
        
        // MARK: - Read Functions
        
        public func supportsInterface(interfaceID: Data, using web3: Web3) async throws -> Bool {
            try await supportsInterface(interfaceID: interfaceID.toHexString(), using: web3)
        }
        
        public func supportsInterface(interfaceID: InterfaceName, using web3: Web3) async throws -> Bool {
            try await supportsInterface(interfaceID: interfaceID.hash, using: web3)
        }
        
        public func supportsInterface(interfaceID: String, using web3: Web3) async throws -> Bool {
            let executor = ContractReadExecutor(contract: contract, web3: web3)
            return try await executor.call(method: "supportsInterface", parameters: [interfaceID])
        }
        
        public func interfaceImplementer(forNode node: String, interfaceID: String, using web3: Web3) async throws -> EthereumAddress {
            let executor = ContractReadExecutor(contract: contract, web3: web3)
            return try await executor.call(method: "interfaceImplementer", parameters: [resolveNameHash(node), interfaceID])
        }
        
        public func getAddress(forNode node: String, using web3: Web3) async throws -> EthereumAddress {
            let executor = ContractReadExecutor(contract: contract, web3: web3)
            return try await executor.call(method: "addr", parameters: [resolveNameHash(node)])
        }
        
        public func getCanonicalName(forNode node: String, using web3: Web3) async throws -> String {
            let executor = ContractReadExecutor(contract: contract, web3: web3)
            return try await executor.call(method: "name", parameters: [resolveNameHash(node)])
        }
        
        public func getContentHash(forNode node: String, using web3: Web3) async throws -> Data {
            let executor = ContractReadExecutor(contract: contract, web3: web3)
            return try await executor.call(method: "contenthash", parameters: [resolveNameHash(node)])
        }
        
        public func getContractABI(forNode node: String, contentType: ContentType, using web3: Web3) async throws -> (BigUInt, Data) {
            let executor = ContractReadExecutor(contract: contract, web3: web3)
            let result = try await executor.call(method: "ABI", parameters: [resolveNameHash(node), contentType.rawValue])
            guard
                let encoding = result["0"] as? BigUInt,
                let data = result["1"] as? Data
            else {
                throw Web3Error.processingError(desc: "Malformed ABI result")
            }
            return (encoding, data)
        }
        
        public func getPublicKey(forNode node: String, using web3: Web3) async throws -> PublicKey {
            let executor = ContractReadExecutor(contract: contract, web3: web3)
            let result = try await executor.call(method: "pubkey", parameters: [resolveNameHash(node)])
            guard let x = result["x"] as? Data, let y = result["y"] as? Data else {
                throw Web3Error.processingError(desc: "Malformed public key")
            }
            return PublicKey(x: "0x" + x.toHexString(), y: "0x" + y.toHexString())
        }
        
        public func getTextData(forNode node: String, key: String, using web3: Web3) async throws -> String {
            let executor = ContractReadExecutor(contract: contract, web3: web3)
            return try await executor.call(method: "text", parameters: [resolveNameHash(node), key])
        }
        
        // MARK: - Helpers
        
        private func resolveNameHash(_ name: String) throws -> Data {
            guard let hash = NameHash.nameHash(name) else {
                throw Web3Error.processingError(desc: "Invalid name hash")
            }
            return hash
        }
    }
}
