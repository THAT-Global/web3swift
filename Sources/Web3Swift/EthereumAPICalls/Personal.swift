//
//  Personal.swift
//  Created by Bailey Nahi on 26/11/2025.
//

import BigInt
import Foundation
import Web3Core

/// Public Personal namespace.
public final class Personal: Sendable {
    public let provider: Web3Provider
    public init(provider: Web3Provider) { self.provider = provider }
    
    // MARK: - Create Account
    
    public func createAccount(password: String ) async throws -> EthereumAddress {
        guard provider.attachedKeystoreManager == nil else {
            throw Web3Error.inputError(desc: "Creating a remote account is not supported when a local keystore is attached.")
        }
        
        let requestCall: APIRequest = .createAccount(password)
        let response: APIResponse<EthereumAddress> = try await APIRequest.sendRequest(with: provider, for: requestCall)
        return response.result
    }
    
    // MARK: - Sign
    
    /// Local (keystore) if available, otherwise `personal_sign` via node.
    /// To avoid potential signing of a transaction the message is first prepended by a special header and then hashed.
    /// - Returns: signed personal message
    public func signPersonalMessage(message: Data, from: EthereumAddress, password: String) async throws -> Data {
        guard let attachedKeystoreManager = self.provider.attachedKeystoreManager else {
            let hexData = message.toHexString().addHexPrefix()
            let request: APIRequest = .personalSign(from.address.lowercased(), hexData)
            let response: APIResponse<Data> = try await APIRequest.sendRequest(with: provider, for: request)
            return response.result
        }
        
        guard let signature = try Web3Signer.signPersonalMessage(message, keystore: attachedKeystoreManager, account: from, password: password) else {
            throw Web3Error.inputError(desc: "Failed to locally sign a message")
        }
        
        return signature
    }
    
    // MARK: - Unlock Account
    
    public func unlock(account: EthereumAddress, password: String, seconds: UInt = 300) async throws -> Bool {
        try await unlock(account: account.address, password: password, seconds: seconds)
    }
    
    /// Unlock an account on the remote node to be able to send transactions and sign messages.
    public func unlock(account: Address, password: String, seconds: UInt = 300) async throws -> Bool {
        guard provider.attachedKeystoreManager == nil else {
            throw Web3Error.inputError(desc: "Cannot unlock a local keystore via the node.")
        }
        let request: APIRequest = .unlockAccount(account, password, seconds)
        let response: APIResponse<Bool> = try await APIRequest.sendRequest(with: provider, for: request)
        return response.result
    }
}

extension Bool: APIResultType { }

public extension Personal {
    /// Recover signer address from a *personal* message + signature.
    /// (Adds the standard prefix then hashes before recovery.)
    func recoverAddress(message: Data, signature: Data) -> EthereumAddress? {
        Utilities.personalECRecover(message, signature: signature)
    }
    
    /// Recover signer address from a precomputed hash and signature.
    func recoverAddress(hash: Data, signature: Data) -> EthereumAddress? {
        Utilities.hashECRecover(hash: hash, signature: signature)
    }
}
