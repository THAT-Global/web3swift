//
//  EIP7702SetCodeTransaction.swift
//  Web3Core
//
//  EIP-7702 SetCode transaction (type 0x04). Encodes a transaction that
//  applies an authorization_list before executing the payload, persistently
//  delegating each authorized EOA to the named implementation. Used by the
//  native revoke path (§5.7) where the wallet sends a self-tx 0x04 with a
//  single authorization to 0x0...0 to undo a prior delegation.
//

import Foundation
import BigInt
import CryptoSwift

public struct EIP7702SetCodeTransaction: Sendable {
    public static let txType: UInt8 = 0x04

    public var chainID: BigUInt
    public var nonce: BigUInt
    public var maxPriorityFeePerGas: BigUInt
    public var maxFeePerGas: BigUInt
    public var gasLimit: BigUInt
    public var to: EthereumAddress
    public var value: BigUInt
    public var data: Data
    public var accessList: [AccessListEntry]
    public var authorizationList: [EIP7702Authorization]

    // Outer transaction signature. y_parity is 0 or 1 per EIP-2718-style typed
    // envelopes.
    public var yParity: UInt8
    public var r: BigUInt
    public var s: BigUInt

    public init(
        chainID: BigUInt,
        nonce: BigUInt,
        maxPriorityFeePerGas: BigUInt,
        maxFeePerGas: BigUInt,
        gasLimit: BigUInt,
        to: EthereumAddress,
        value: BigUInt,
        data: Data,
        accessList: [AccessListEntry] = [],
        authorizationList: [EIP7702Authorization],
        yParity: UInt8 = 0,
        r: BigUInt = 0,
        s: BigUInt = 0
    ) {
        self.chainID = chainID
        self.nonce = nonce
        self.maxPriorityFeePerGas = maxPriorityFeePerGas
        self.maxFeePerGas = maxFeePerGas
        self.gasLimit = gasLimit
        self.to = to
        self.value = value
        self.data = data
        self.accessList = accessList
        self.authorizationList = authorizationList
        self.yParity = yParity
        self.r = r
        self.s = s
    }

    /// Encode the transaction body for either signing or broadcast.
    /// For signing: `0x04 || rlp(unsigned_fields)`.
    /// For broadcast: `0x04 || rlp(unsigned_fields ++ [y_parity, r, s])`.
    public func encode(for kind: EncodeKind) -> Data? {
        let auths = authorizationList.map { $0.rlpFields() }
        let access = accessList.map { $0.encodeAsList() }
        let unsigned: [Any?] = [
            chainID,
            nonce,
            maxPriorityFeePerGas,
            maxFeePerGas,
            gasLimit,
            to.addressData,
            value,
            data,
            access,
            auths
        ]
        let fields: [Any?]
        switch kind {
        case .signing:
            fields = unsigned
        case .transaction:
            fields = unsigned + [BigUInt(yParity), r, s]
        }
        guard var body = RLP.encode(fields) else { return nil }
        body.insert(Self.txType, at: 0)
        return body
    }

    public enum EncodeKind: Sendable {
        case signing
        case transaction
    }

    /// The 32-byte keccak256 hash that the outer transaction signature is over.
    public func signingHash() -> Data? {
        encode(for: .signing)?.sha3(.keccak256)
    }

    /// The transaction hash as it appears on-chain (keccak256 of the full
    /// encoded transaction). Only meaningful once signed.
    public func transactionHash() -> Data? {
        encode(for: .transaction)?.sha3(.keccak256)
    }

    /// Sign the transaction in place using the EOA private key.
    public mutating func sign(privateKey: Data, useExtraEntropy: Bool = false) throws {
        guard let hash = signingHash() else { throw EIP7702Error.encodingFailed }
        for _ in 0..<1024 {
            let (serialized, _) = SECP256K1.signForRecovery(
                hash: hash, privateKey: privateKey, useExtraEntropy: useExtraEntropy
            )
            guard let serializedSignature = serialized,
                  let unmarshalled = SECP256K1.unmarshalSignature(signatureData: serializedSignature)
            else { continue }
            self.yParity = unmarshalled.v >= 27 ? unmarshalled.v - 27 : unmarshalled.v
            self.r = BigUInt(unmarshalled.r)
            self.s = BigUInt(unmarshalled.s)
            return
        }
        throw EIP7702Error.signingFailed
    }
}
