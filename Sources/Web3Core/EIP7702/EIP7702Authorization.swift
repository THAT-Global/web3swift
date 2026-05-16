//
//  EIP7702Authorization.swift
//  Web3Core
//
//  EIP-7702 authorization tuple — the bearer credential that delegates an EOA
//  to a smart-contract implementation. The signed payload is
//
//      MAGIC || rlp([chain_id, address, nonce])
//
//  hashed with keccak256, signed with secp256k1. The resulting tuple
//  [chain_id, address, nonce, y_parity, r, s] is included in the
//  authorization_list field of a type-0x04 SetCode transaction.
//

import Foundation
import BigInt
import CryptoSwift

/// EIP-7702 authorization tuple. Construct with `chainID`, `address`, `nonce`;
/// call `sign(privateKey:)` to produce a signed tuple. The struct is also the
/// natural shape for an entry in a SetCode transaction's authorization list.
public struct EIP7702Authorization: Sendable, Equatable, Hashable {
    /// EIP-7702 magic byte prefixed before the RLP payload before hashing.
    public static let magic: UInt8 = 0x05

    /// `chainId` the authorization is bound to. Must be the EOA's current
    /// chain. Per §5.6 of the THAT plan, `0` is forbidden (universal replay).
    public let chainID: BigUInt

    /// The contract address the EOA is delegating to.
    public let address: EthereumAddress

    /// EOA nonce at the time of signing. The bundler/protocol validates this
    /// matches the on-chain nonce at submission.
    public let nonce: BigUInt

    // Signature components (set after sign()). y_parity is 0 or 1.
    public var yParity: UInt8
    public var r: BigUInt
    public var s: BigUInt

    public init(
        chainID: BigUInt,
        address: EthereumAddress,
        nonce: BigUInt,
        yParity: UInt8 = 0,
        r: BigUInt = 0,
        s: BigUInt = 0
    ) {
        self.chainID = chainID
        self.address = address
        self.nonce = nonce
        self.yParity = yParity
        self.r = r
        self.s = s
    }

    /// The 32-byte keccak256 hash that the EOA private key signs over.
    /// `keccak256(MAGIC || rlp([chain_id, address, nonce]))`.
    public func signingHash() -> Data? {
        guard let rlp = RLP.encode([chainID, address.addressData, nonce]) else { return nil }
        var preimage = Data([Self.magic])
        preimage.append(rlp)
        return preimage.sha3(.keccak256)
    }

    /// Sign this authorization tuple in place.
    /// Throws if `chainID == 0` (universal replay — explicitly forbidden by §5.6)
    /// or if the signing primitives fail.
    public mutating func sign(privateKey: Data, useExtraEntropy: Bool = false) throws {
        if chainID == 0 {
            throw EIP7702Error.chainIDZero
        }
        guard let hash = signingHash() else {
            throw EIP7702Error.encodingFailed
        }
        for _ in 0..<1024 {
            let (serialized, _) = SECP256K1.signForRecovery(
                hash: hash, privateKey: privateKey, useExtraEntropy: useExtraEntropy
            )
            guard let serializedSignature = serialized,
                  let unmarshalled = SECP256K1.unmarshalSignature(signatureData: serializedSignature)
            else { continue }
            // SECP256K1.unmarshalSignature returns v as the recovery id encoded
            // as 27/28 (or 0/1 in some paths). EIP-7702 requires y_parity in {0,1}.
            self.yParity = unmarshalled.v >= 27 ? unmarshalled.v - 27 : unmarshalled.v
            self.r = BigUInt(unmarshalled.r)
            self.s = BigUInt(unmarshalled.s)
            return
        }
        throw EIP7702Error.signingFailed
    }

    /// RLP item shape used inside a SetCode transaction's authorization list:
    /// `[chain_id, address, nonce, y_parity, r, s]`.
    public func rlpFields() -> [Any?] {
        [chainID, address.addressData, nonce, BigUInt(yParity), r, s]
    }

    /// Recover the signer address. Returns nil if the tuple isn't signed.
    public func recoverSigner() -> EthereumAddress? {
        guard r != 0 || s != 0 else { return nil }
        guard let hash = signingHash() else { return nil }
        guard let rData = r.serialize().setLengthLeft(32),
              let sData = s.serialize().setLengthLeft(32) else { return nil }
        // SECP256K1.recoverPublicKey expects 65-byte signature with v in
        // {27,28,31,32,...}. Normalize yParity back to 27/28.
        let v: UInt8 = yParity + 27
        var sig = Data(rData)
        sig.append(sData)
        sig.append(v)
        guard let pub = SECP256K1.recoverPublicKey(hash: hash, signature: sig) else { return nil }
        return Utilities.publicToAddress(pub)
    }
}

public enum EIP7702Error: Error, Sendable, Equatable {
    /// chainID == 0 is rejected to prevent universal-replay attacks.
    case chainIDZero
    /// RLP encoding produced no bytes (shouldn't happen with well-formed inputs).
    case encodingFailed
    /// secp256k1 failed to produce a valid recoverable signature within the retry budget.
    case signingFailed
    /// Encoded payload exceeded the size we can safely represent.
    case payloadTooLarge
}
