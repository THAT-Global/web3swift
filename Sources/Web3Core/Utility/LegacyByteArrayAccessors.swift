//
//  LegacyByteArrayAccessors.swift
//  Web3Core
//
//  swift-secp256k1 0.10.0's Swift module (`secp256k1`, GigaBitcoin LLC, MIT) exported these two accessors. Before
//  Swift's member-import rule, an extension member reached every module that loaded the module, so web3swift and
//  everything importing it (nft-core among them) read `Data.bytes` and `ContiguousBytes.bytes` as `[UInt8]` from there:
//  CryptoSwift renamed its own `Data.bytes` to `byteArray` (Foundation's `Data.bytes` is now a `RawSpan`). From 0.24.0
//  web3swift imports only the C module, `libsecp256k1`, so the accessors live here, with the bodies 0.10.0 compiled,
//  and every call site resolves and behaves as it did (that-ios BITCOIN-PLAN.md B0: no change for today's users).
//
//  RLP.swift's file-private copy of `Data.bytes` (`Array(self)`, the same bytes) gives way to this one.
//
//  New code should say `Array(data)`. Once the call sites do, this file goes.
//

import Foundation

public extension ContiguousBytes {
    @inlinable var bytes: [UInt8] {
        withUnsafeBytes { bytesPtr in Array(bytesPtr) }
    }
}

public extension Data {
    @inlinable var bytes: [UInt8] {
        withUnsafeBytes { bytesPtr in Array(bytesPtr) }
    }
}
