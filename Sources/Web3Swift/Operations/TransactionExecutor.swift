//
//  TransactionExecutor.swift
//  Created by Bailey Nahi on 26/11/2025.
//

import BigInt
import Foundation
import Web3Core

public enum TransactionExecutor {
    /// Resolves missing fields in-place (gas, nonce, fees) according to `policies`.
    /// - Parameter policies: Controls how values like gas limit, gas price, and nonce are resolved.
    public static func resolvePolicies(
        for transaction: inout CodableTransaction,
        policies: Policies = .auto,
        using web3: Web3
    ) async throws {
        try await PolicyResolver.resolveAllMissing(for: &transaction, policies: policies, using: web3.provider)
    }
    
    /// Signs a transaction in-place.
    /// - Parameters:
    ///   - transaction: The transaction to be signed.
    ///   - account: Address to sign with. Falls back to `transaction.from` or `sender`. Throws if none.
    ///   - password: Keystore password.
    public static func signTransaction(
        _ transaction: inout CodableTransaction,
        account: EthereumAddress? = nil,
        password: String,
        keystore: KeystoreManager
    ) throws {
        guard let sender = account ?? transaction.from else {
            throw Web3Error.inputError(desc: "Cannot sign transaction: missing 'from' address and no signing account provided.")
        }
        try Web3Signer.signTX(
            transaction: &transaction,
            keystore: keystore,
            account: sender,
            password: password
        )
    }
    
    /// Resolves policies and signs the transaction in-place.
    /// - Parameters:
    ///   - account: Address to sign with. Falls back to `transaction.from` or `sender`. Throws if none.
    ///   - password: Keystore password.
    ///   - web3: Web3 instance with attached keystore manager.
    public static func resolveAndSignTransaction(
        _ transaction: inout CodableTransaction,
        account: EthereumAddress? = nil,
        password: String,
        policies: Policies = .auto,
        using web3: Web3
    ) async throws {
        guard let keystore = web3.provider.attachedKeystoreManager else {
            throw Web3Error.inputError(desc: "Web3 provider doesn't have an attached keystore.")
        }
        try await resolvePolicies(for: &transaction, policies: policies, using: web3)
        try signTransaction(&transaction, account: account, password: password, keystore: keystore)
    }
    
    /// Sends a transaction via `eth_sendTransaction`, signed by the node.
    /// Requires the sender account to be unlocked on the node (not suitable for mobile wallets).
    public static func sendTransaction(_ transaction: CodableTransaction, using web3: Web3) async throws -> TransactionSendingResult {
        return try await web3.eth.send(transaction)
    }
    
    /// Sends a signed transaction using `eth_sendRawTransaction`.
    /// Transaction must already be signed.
    public static func sendRawTransaction(_ transaction: CodableTransaction, using web3: Web3) async throws -> TransactionSendingResult {
        guard let transactionData = transaction.encode(for: .transaction) else {
            throw Web3Error.dataError
        }
        
#if DEBUG
        // === MARK: Temp Transaction Submission Logging ===
        print("XXX Submitting transaction:")
        print("XXX To: \(transaction.to.address)")
        print("XXX Value: \(transaction.value)")
        print("XXX Gas Limit: \(transaction.gasLimit)")
        print("XXX Gas Price: \(transaction.gasPrice ?? 0)")
        print("XXX Max Fee Per Gas : \(transaction.maxFeePerGas ?? 0)")
        print("XXX Max Priority Fee Per Gas: \(transaction.maxPriorityFeePerGas ?? 0)")
        print("XXX Data: \(transaction.data.toHexString().prefix(50))...") // Log first 50 chars
        print("XXX Broadcasting: \(transactionData.toHexString().prefix(20))... via \(web3.provider.url)")
        // === TODO: Submitting ===
#endif
        
        return try await web3.eth.send(raw: transactionData)
    }
}

/// Returns a modified copy of the transaction. Calls the `inout` variant internally.
extension TransactionExecutor {
    /// Calls ``resolvePolicies(into:policies:using:)`` and returns a new copy with resolved fields.
    public static func resolvePolicies(
        for transaction: CodableTransaction,
        policies: Policies = .auto,
        using web3: Web3
    ) async throws -> CodableTransaction {
        var txn = transaction
        try await resolvePolicies(for: &txn, policies: policies, using: web3)
        return txn
    }
    
    /// Calls ``signTransaction(_:account:password:keystore:)`` and returns a new signed copy.
    public static func signTransaction(
        _ transaction: CodableTransaction,
        account: EthereumAddress? = nil,
        password: String,
        keystore: KeystoreManager
    ) throws -> CodableTransaction {
        var txn = transaction
        try signTransaction(&txn, account: account, password: password, keystore: keystore)
        return txn
    }
    
    /// Calls ``resolveAndSignTransaction(_:account:password:policies:using:)`` and returns a signed copy.
    public static func resolveAndSignTransaction(
        _ transaction: CodableTransaction,
        account: EthereumAddress? = nil,
        password: String,
        policies: Policies = .auto,
        using web3: Web3
    ) async throws -> CodableTransaction {
        var txn = transaction
        try await resolveAndSignTransaction(&txn, account: account, password: password, policies: policies, using: web3)
        return txn
    }
    
    //    public static func resolveAndSendTransaction(
    //        _ transaction: CodableTransaction,
    //        password: String,
    //        policies: Policies = .auto,
    //        sendRaw: Bool = true,
    //        using web3: Web3
    //    ) async throws -> TransactionSendingResult {
    //        guard sendRaw else {
    //            let resolved = try await resolvePolicies(for: transaction, policies: policies, using: web3)
    //            return try await web3.eth.send(transaction)
    //        }
    //        let signed = try await resolveAndSignTransaction(transaction, password: password, policies: policies, using: web3)
    //        return try await sendRawTransaction(signed, using: web3)
    //    }
}
