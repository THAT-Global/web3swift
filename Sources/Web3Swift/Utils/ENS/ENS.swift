//
//  Created by Alex Vlasov.
//  Major rewrite by Bailey Nahi on 08/08/2025.
//  Copyright © 2018 Alex Vlasov. All rights reserved.
//

import BigInt
import Foundation
import Web3Core

public final class ENS {
    public let registry: ENS.Registry
    
    private(set) var resolver: ENS.Resolver?
    private(set) var baseRegistrar: ENS.BaseRegistrar?
    private(set) var registrarController: ENS.ETHRegistrarController?
    private(set) var reverseRegistrar: ENS.ReverseRegistrar?
    
    public init(registry: ENS.Registry) {
        self.registry = registry
    }
    
    public func setENSResolver(_ resolver: ENS.Resolver) throws {
        guard registry.contract.chainId == resolver.contract.chainId else {
            throw Web3Error.processingError(desc: "Resolver should use same chain as ENS")
        }
        self.resolver = resolver
    }
    
    public func setENSResolver(withDomain domain: String, using web3: Web3) async throws {
        self.resolver = try await registry.getResolver(forDomain: domain, using: web3)
    }
    
    public func setBaseRegistrar(_ registrar: ENS.BaseRegistrar) throws {
        guard registry.contract.chainId == registrar.contract.chainId else {
            throw Web3Error.processingError(desc: "BaseRegistrar should use same chain as ENS")
        }
        self.baseRegistrar = registrar
    }
    
    public func setBaseRegistrar(withAddress address: EthereumAddress) throws {
        self.baseRegistrar = try ENS.BaseRegistrar(contractAddress: address, chainId: registry.contract.chainId)
    }
    
    public func setRegistrarController(_ controller: ENS.ETHRegistrarController) throws {
        guard registry.contract.chainId == controller.contract.chainId else {
            throw Web3Error.processingError(desc: "ETHRegistrarController should use same chain as ENS")
        }
        self.registrarController = controller
    }
    
    public func setRegistrarController(withAddress address: EthereumAddress) throws {
        self.registrarController = try ENS.ETHRegistrarController(contractAddress: address, chainId: registry.contract.chainId)
    }
    
    public func setReverseRegistrar(_ registrar: ENS.ReverseRegistrar) throws {
        guard registry.contract.chainId == registrar.contract.chainId else {
            throw Web3Error.processingError(desc: "ReverseRegistrar should use same chain as ENS")
        }
        self.reverseRegistrar = registrar
    }
    
    public func setReverseRegistrar(withAddress address: EthereumAddress) throws {
        self.reverseRegistrar = try ENS.ReverseRegistrar(contractAddress: address, chainId: registry.contract.chainId)
    }
    
    // MARK: - Resolver Convenience Read Wrappers
    
    public func getAddress(forNode node: String, using web3: Web3) async throws -> EthereumAddress {
        let resolver = try await registry.getResolver(forDomain: node, using: web3)
        guard try await resolver.supportsInterface(interfaceID: .addr, using: web3) else {
            throw Web3Error.processingError(desc: "Resolver does not support addr interface")
        }
        return try await resolver.getAddress(forNode: node, using: web3)
    }
    
    public func getName(forNode node: String, using web3: Web3) async throws -> String {
        let resolver = try await registry.getResolver(forDomain: node, using: web3)
        guard try await resolver.supportsInterface(interfaceID: .name, using: web3) else {
            throw Web3Error.processingError(desc: "Resolver does not support name interface")
        }
        return try await resolver.getCanonicalName(forNode: node, using: web3)
    }
    
    public func getContent(forNode node: String, using web3: Web3) async throws -> Data {
        let resolver = try await registry.getResolver(forDomain: node, using: web3)
        guard try await resolver.supportsInterface(interfaceID: .content, using: web3) else {
            throw Web3Error.processingError(desc: "Resolver does not support content interface")
        }
        return try await resolver.getContentHash(forNode: node, using: web3)
    }
    
    public func getABI(forNode node: String, contentType: ENS.Resolver.ContentType, using web3: Web3) async throws -> (BigUInt, Data) {
        let resolver = try await registry.getResolver(forDomain: node, using: web3)
        guard try await resolver.supportsInterface(interfaceID: .ABI, using: web3) else {
            throw Web3Error.processingError(desc: "Resolver does not support ABI interface")
        }
        return try await resolver.getContractABI(forNode: node, contentType: contentType, using: web3)
    }
    
    public func getPublicKey(forNode node: String, using web3: Web3) async throws -> PublicKey {
        let resolver = try await registry.getResolver(forDomain: node, using: web3)
        guard try await resolver.supportsInterface(interfaceID: .pubkey, using: web3) else {
            throw Web3Error.processingError(desc: "Resolver does not support pubkey interface")
        }
        return try await resolver.getPublicKey(forNode: node, using: web3)
    }
    
    public func getText(forNode node: String, key: String, using web3: Web3) async throws -> String {
        let resolver = try await registry.getResolver(forDomain: node, using: web3)
        guard try await resolver.supportsInterface(interfaceID: .text, using: web3) else {
            throw Web3Error.processingError(desc: "Resolver does not support text interface")
        }
        return try await resolver.getTextData(forNode: node, key: key, using: web3)
    }
    
    // MARK: - Resolver Convenience Write Wrappers
    
    public func setAddress(forNode node: String, address: EthereumAddress, using web3: Web3) async throws -> CodableTransaction {
        let resolver = try await registry.getResolver(forDomain: node, using: web3)
        guard try await resolver.supportsInterface(interfaceID: .addr, using: web3) else {
            throw Web3Error.processingError(desc: "Resolver does not support addr interface")
        }
        return try resolver.setAddress(forNode: node, address: address)
    }
    
    public func setName(forNode node: String, name: String, using web3: Web3) async throws -> CodableTransaction {
        let resolver = try await registry.getResolver(forDomain: node, using: web3)
        guard try await resolver.supportsInterface(interfaceID: .name, using: web3) else {
            throw Web3Error.processingError(desc: "Resolver does not support name interface")
        }
        return try resolver.setCanonicalName(forNode: node, name: name)
    }
    
    public func setContent(forNode node: String, hash: String, using web3: Web3) async throws -> CodableTransaction {
        let resolver = try await registry.getResolver(forDomain: node, using: web3)
        guard try await resolver.supportsInterface(interfaceID: .content, using: web3) else {
            throw Web3Error.processingError(desc: "Resolver does not support content interface")
        }
        return try resolver.setContentHash(forNode: node, hash: hash)
    }
    
    public func setABI(forNode node: String, contentType: ENS.Resolver.ContentType, data: Data, using web3: Web3) async throws -> CodableTransaction {
        let resolver = try await registry.getResolver(forDomain: node, using: web3)
        guard try await resolver.supportsInterface(interfaceID: .ABI, using: web3) else {
            throw Web3Error.processingError(desc: "Resolver does not support ABI interface")
        }
        return try resolver.setContractABI(forNode: node, contentType: contentType, data: data)
    }
    
    public func setPublicKey(forNode node: String, publicKey: PublicKey, using web3: Web3) async throws -> CodableTransaction {
        let resolver = try await registry.getResolver(forDomain: node, using: web3)
        guard try await resolver.supportsInterface(interfaceID: .pubkey, using: web3) else {
            throw Web3Error.processingError(desc: "Resolver does not support pubkey interface")
        }
        return try resolver.setPublicKey(forNode: node, publicKey: publicKey)
    }
    
    public func setText(forNode node: String, key: String, value: String, using web3: Web3) async throws -> CodableTransaction {
        let resolver = try await registry.getResolver(forDomain: node, using: web3)
        guard try await resolver.supportsInterface(interfaceID: .text, using: web3) else {
            throw Web3Error.processingError(desc: "Resolver does not support text interface")
        }
        return try resolver.setTextData(forNode: node, key: key, value: value)
    }
}
