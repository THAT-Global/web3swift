//
//  Web3Signer.swift
//  THAT
//
//  Created by Bailey Nahi on 11/08/2025.
//

import BigInt
import Foundation
import Web3Core

public struct Web3Signer {
    public static func signTX(
        transaction: inout CodableTransaction,
        keystore: AbstractKeystore,
        account: EthereumAddress,
        password: String,
        useExtraEntropy: Bool = false
    ) throws {
        var privateKey = try keystore.UNSAFE_getPrivateKeyData(password: password, account: account)
        defer { Data.zero(&privateKey) }
        try transaction.sign(privateKey: privateKey, useExtraEntropy: useExtraEntropy)
    }
    
    public static func signPersonalMessage<T: AbstractKeystore>(
        _ personalMessage: Data,
        keystore: T,
        account: EthereumAddress,
        password: String,
        useHash: Bool = true,
        useExtraEntropy: Bool = false
    ) throws -> Data? {
        var privateKey = try keystore.UNSAFE_getPrivateKeyData(password: password, account: account)
        defer { Data.zero(&privateKey) }
        var data: Data
        if useHash {
            guard let hash = Utilities.hashPersonalMessage(personalMessage) else { return nil }
            data = hash
        } else {
            data = personalMessage
        }
        let (compressedSignature, _) = SECP256K1.signForRecovery(
            hash: data,
            privateKey: privateKey,
            useExtraEntropy: useExtraEntropy
        )
        return compressedSignature
    }
    
    public static func signEIP712(
        _ eip712TypedDataPayload: EIP712TypedData,
        keystore: AbstractKeystore,
        account: EthereumAddress,
        password: String? = nil
    ) throws -> Data {
        let hash = try eip712TypedDataPayload.signHash()
        guard let signature = try Web3Signer.signPersonalMessage(
            hash,
            keystore: keystore,
            account: account,
            password: password ?? "",
            useHash: false
        )
        else {
            throw Web3Error.dataError
        }
        return signature
    }
    
    public static func signEIP712(
        _ eip712Hashable: EIP712Hashable,
        keystore: AbstractKeystore,
        verifyingContract: EthereumAddress,
        account: EthereumAddress,
        password: String? = nil,
        chainId: BigUInt? = nil
    ) throws -> Data {
        
        let domainSeparator: EIP712Hashable = EIP712Domain(chainId: chainId, verifyingContract: verifyingContract)
        let hash = try eip712hash(domainSeparator: domainSeparator, message: eip712Hashable)
        guard let signature = try Web3Signer.signPersonalMessage(
            hash,
            keystore: keystore,
            account: account,
            password: password ?? "",
            useHash: false
        )
        else {
            throw Web3Error.dataError
        }
        return signature
    }

    /// Parse EIP-712 typed-data JSON, sign, and return `0x`-prefixed 65-byte hex
    /// with `v` normalised to `{27, 28}`.
    public static func signTypedDataV4(
        _ typedDataJSON: String,
        keystore: AbstractKeystore,
        account: EthereumAddress,
        password: String
    ) throws -> String {
        let eip712 = try EIP712Parser.parse(typedDataJSON)
        var sig = try signEIP712(eip712, keystore: keystore, account: account, password: password)
        normalizeRecoveryByte(in: &sig)
        return "0x" + sig.toHexString()
    }

    /// Ensure the recovery byte `v` at index 64 of a 65-byte signature is in `{27, 28}`.
    public static func normalizeRecoveryByte(in sig: inout Data) {
        if sig.count == 65, sig[64] < 27 {
            sig[64] += 27
        }
    }

    // MARK: - EIP-7702

    /// Sign an EIP-7702 authorization tuple with the EOA key. The caller is
    /// responsible for verifying that `tuple.address` is the pinned per-chain
    /// delegate BEFORE calling this — Web3Signer doesn't know about THAT's
    /// pinning policy, so it can't enforce §5.2 on its own. The crypto-level
    /// guard `chainID != 0` is enforced inside `EIP7702Authorization.sign`.
    public static func signEIP7702Authorization(
        _ tuple: inout EIP7702Authorization,
        keystore: AbstractKeystore,
        account: EthereumAddress,
        password: String,
        useExtraEntropy: Bool = false
    ) throws {
        var privateKey = try keystore.UNSAFE_getPrivateKeyData(password: password, account: account)
        defer { Data.zero(&privateKey) }
        try tuple.sign(privateKey: privateKey, useExtraEntropy: useExtraEntropy)
    }

    /// Sign an EIP-7702 SetCode transaction (type 0x04) with the EOA key.
    /// Used by the native revoke path (§5.7).
    public static func signEIP7702SetCodeTransaction(
        _ tx: inout EIP7702SetCodeTransaction,
        keystore: AbstractKeystore,
        account: EthereumAddress,
        password: String,
        useExtraEntropy: Bool = false
    ) throws {
        var privateKey = try keystore.UNSAFE_getPrivateKeyData(password: password, account: account)
        defer { Data.zero(&privateKey) }
        try tx.sign(privateKey: privateKey, useExtraEntropy: useExtraEntropy)
    }

    /// **LEGACY — DO NOT USE FOR MODULAR ACCOUNT V2 / SemiModularAccount7702.**
    ///
    /// Signs the raw v0.7 userOpHash directly (no EIP-191 wrapping, no
    /// MA v2 validator prefix). SMA7702's fallback signer validates with
    /// EIP-191 wrapping, so signatures produced by this method will
    /// recover the wrong address and reverts AA24.
    ///
    /// THAT's sponsored pipeline signs user-ops via
    /// `Web3Signer.signPersonalMessage(hash, useHash: true)` and wraps
    /// the resulting bytes in MA v2's `0xff 0x00` prefix at the
    /// app-layer (`SponsoredUserOpPipeline.packMAv2UOSignature`). This
    /// method is kept only for non-AA bundler integrations that
    /// genuinely want a raw 4337 signature.
    public static func signUserOperation(
        _ op: inout PackedUserOperation,
        entryPoint: EthereumAddress,
        chainID: BigUInt,
        keystore: AbstractKeystore,
        account: EthereumAddress,
        password: String,
        useExtraEntropy: Bool = false
    ) throws {
        var privateKey = try keystore.UNSAFE_getPrivateKeyData(password: password, account: account)
        defer { Data.zero(&privateKey) }
        try op.sign(
            entryPoint: entryPoint, chainID: chainID,
            privateKey: privateKey, useExtraEntropy: useExtraEntropy
        )
    }
}
