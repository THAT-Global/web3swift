//
//  PackedUserOperation.swift
//  Web3Core
//
//  ERC-4337 v0.7+ PackedUserOperation. The bundler accepts ordinary
//  UserOperations as JSON but the canonical hash (the bytes the user actually
//  signs) is computed over the packed form. This file owns the packing and
//  hashing — the bundler-facing JSON DTO lives in AlchemyKit.
//

import Foundation
import BigInt
import CryptoSwift

/// Packed representation of an ERC-4337 v0.7 UserOperation. The `accountGasLimits`
/// and `gasFees` fields are 32-byte values that pack two 128-bit gas-related
/// numbers each. We keep them as their semantic pairs and pack on encode.
public struct PackedUserOperation: Sendable, Equatable {
    public var sender: EthereumAddress
    public var nonce: BigUInt
    public var initCode: Data
    public var callData: Data
    /// uint128 — gas used inside the account's `validateUserOp`.
    public var verificationGasLimit: BigUInt
    /// uint128 — gas used inside the account's execution.
    public var callGasLimit: BigUInt
    public var preVerificationGas: BigUInt
    /// uint128 — equivalent of EIP-1559 maxPriorityFeePerGas for this user-op.
    public var maxPriorityFeePerGas: BigUInt
    /// uint128 — equivalent of EIP-1559 maxFeePerGas for this user-op.
    public var maxFeePerGas: BigUInt
    /// Concatenation of paymaster address (20) || paymasterVerificationGasLimit (16)
    /// || paymasterPostOpGasLimit (16) || paymasterData. Empty when unsponsored.
    public var paymasterAndData: Data
    public var signature: Data

    public init(
        sender: EthereumAddress,
        nonce: BigUInt,
        initCode: Data = Data(),
        callData: Data,
        verificationGasLimit: BigUInt,
        callGasLimit: BigUInt,
        preVerificationGas: BigUInt,
        maxPriorityFeePerGas: BigUInt,
        maxFeePerGas: BigUInt,
        paymasterAndData: Data = Data(),
        signature: Data = Data()
    ) {
        self.sender = sender
        self.nonce = nonce
        self.initCode = initCode
        self.callData = callData
        self.verificationGasLimit = verificationGasLimit
        self.callGasLimit = callGasLimit
        self.preVerificationGas = preVerificationGas
        self.maxPriorityFeePerGas = maxPriorityFeePerGas
        self.maxFeePerGas = maxFeePerGas
        self.paymasterAndData = paymasterAndData
        self.signature = signature
    }

    /// `accountGasLimits = verificationGasLimit << 128 | callGasLimit` packed
    /// as 32 bytes big-endian.
    public var accountGasLimits: Data {
        Self.packUint128Pair(high: verificationGasLimit, low: callGasLimit)
    }

    /// `gasFees = maxPriorityFeePerGas << 128 | maxFeePerGas` packed
    /// as 32 bytes big-endian.
    public var gasFees: Data {
        Self.packUint128Pair(high: maxPriorityFeePerGas, low: maxFeePerGas)
    }

    /// Compute the canonical userOpHash for v0.7.
    ///
    ///     userOpHash = keccak256(abi.encode(
    ///         keccak256(abi.encode(
    ///             sender,
    ///             nonce,
    ///             keccak256(initCode),
    ///             keccak256(callData),
    ///             accountGasLimits,
    ///             preVerificationGas,
    ///             gasFees,
    ///             keccak256(paymasterAndData)
    ///         )),
    ///         entryPoint,
    ///         chainId
    ///     ))
    ///
    /// `signature` is intentionally excluded.
    public func hash(entryPoint: EthereumAddress, chainID: BigUInt) -> Data {
        var inner = Data()
        inner.append(Self.padAddress(sender))
        inner.append(Self.padUint256(nonce))
        inner.append(initCode.sha3(.keccak256))
        inner.append(callData.sha3(.keccak256))
        inner.append(accountGasLimits)
        inner.append(Self.padUint256(preVerificationGas))
        inner.append(gasFees)
        inner.append(paymasterAndData.sha3(.keccak256))
        let innerHash = inner.sha3(.keccak256)

        var outer = Data()
        outer.append(innerHash)
        outer.append(Self.padAddress(entryPoint))
        outer.append(Self.padUint256(chainID))
        return outer.sha3(.keccak256)
    }

    /// **LEGACY — DO NOT USE FOR MODULAR ACCOUNT V2 / SemiModularAccount7702.**
    ///
    /// Signs the raw v0.7 userOpHash directly. SMA7702's fallback signer
    /// validates with EIP-191 wrapping (`"\x19Ethereum Signed Message:\n32"
    /// || userOpHash`) before ecrecover, so signatures produced here
    /// won't recover the right address.
    ///
    /// THAT's sponsored pipeline signs `hash(entryPoint:chainID:)` via
    /// `Web3Signer.signPersonalMessage(_, useHash: true)` which performs
    /// the EIP-191 wrap natively. This method is kept only for non-AA
    /// bundler integrations or future delegates that genuinely want a raw
    /// 4337 signature.
    ///
    /// Resulting signature is 65 bytes (r ‖ s ‖ v), `v` in {27, 28}.
    public mutating func sign(
        entryPoint: EthereumAddress,
        chainID: BigUInt,
        privateKey: Data,
        useExtraEntropy: Bool = false
    ) throws {
        let opHash = hash(entryPoint: entryPoint, chainID: chainID)
        for _ in 0..<1024 {
            let (serialized, _) = SECP256K1.signForRecovery(
                hash: opHash, privateKey: privateKey, useExtraEntropy: useExtraEntropy
            )
            if let s = serialized {
                self.signature = s
                return
            }
        }
        throw EIP7702Error.signingFailed
    }

    // MARK: - Packing helpers

    static func packUint128Pair(high: BigUInt, low: BigUInt) -> Data {
        // Right-align the low 16 bytes of `high` into out[0..16] and of `low`
        // into out[16..32]. Values that overflow uint128 have their high bytes
        // silently dropped — the caller is responsible for constraining inputs
        // to uint128 (which the ERC-4337 spec requires anyway).
        var out = Data(repeating: 0, count: 32)
        let highBytes = high.serialize()
        let lowBytes = low.serialize()
        let highLen = min(highBytes.count, 16)
        let lowLen = min(lowBytes.count, 16)
        for i in 0..<highLen {
            out[16 - highLen + i] = highBytes[highBytes.count - highLen + i]
        }
        for i in 0..<lowLen {
            out[32 - lowLen + i] = lowBytes[lowBytes.count - lowLen + i]
        }
        return out
    }

    static func padAddress(_ address: EthereumAddress) -> Data {
        var out = Data(repeating: 0, count: 32)
        let raw = address.addressData
        let offset = 32 - raw.count
        for i in 0..<raw.count { out[offset + i] = raw[i] }
        return out
    }

    static func padUint256(_ value: BigUInt) -> Data {
        var out = Data(repeating: 0, count: 32)
        let raw = value.serialize()
        guard raw.count <= 32 else { return out }
        let offset = 32 - raw.count
        for i in 0..<raw.count { out[offset + i] = raw[i] }
        return out
    }
}
