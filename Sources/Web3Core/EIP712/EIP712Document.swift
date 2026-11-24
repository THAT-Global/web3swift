//
//  EIP712Document.swift
//  Web3Core
//
//  EIP-712 typed data read from its JSON text exactly, and hashed. Lifted from ledger-core's `EthereumTypedData`
//  (develop 980773a), whose digest is pinned to 29 vectors of an independent hasher; the Ledger device's commands and
//  wire limits stay in ledger-core. Two readings, chosen by the caller and never guessed:
//
//  - `signTypedDataV4`, for a key on the phone: `eth_signTypedData_v4` as wallets in the field implement it, with
//    MetaMask's `@metamask/eth-sig-util` (`TypedDataUtils`, version V4) the reference. For every document eth-sig-util
//    hashes, this reading gives the digest eth-sig-util gives, or refuses: never another digest. Where the old
//    web3swift hasher and eth-sig-util signed one document to one digest, this reading signs it too (a phone wallet
//    keeps what it signed before): so a struct-typed field that is null or left out is 32 zero bytes, a short `bytesN`
//    is padded, a JSON number a double holds exactly is read (`1e18`, `137.0`), and `uint`/`int` are `uint256`/`int256`.
//    What eth-sig-util reads loosely and no contract can check, or the old code refused, is refused: a number for an
//    address, "false" or 1 for a bool, a JSON number JavaScript rounds, an `int8` of 255.
//  - `strict`, for a hardware signer: what ledger-core's reader accepts (it adds the device's wire limits itself).
//
//  Both readings keep exactness: a number is read from its text, never through a floating-point value; a key written
//  twice is refused; a type is read only as EIP-712 spells it.
//

import CryptoSwift
import Foundation

/// EIP-712 typed data: its types, its domain and message as values, and the hashes EIP-712 defines over them.
public struct EIP712Document: Hashable, Sendable {
    /// How a document's JSON is read. The two differ only where `eth_signTypedData_v4` as wallets implement it and a
    /// hardware signer part ways; see each case.
    public enum Reading: String, Hashable, Sendable, CaseIterable {
        /// For a key on the phone: `eth_signTypedData_v4` as MetaMask's eth-sig-util V4 hashes it, or refused.
        ///
        /// Read here and refused in ``strict``: a struct-typed field (or array entry) that is null or left out (32 zero
        /// bytes); a JSON number with a fraction or an exponent whose value is a whole number a double holds exactly;
        /// a number string with ASCII space, tab, CR or LF around it, or more than 80 (decimal) or 64 (hex) digits of
        /// which the extra are leading zeros; a `bytesN` shorter than N (padded on the right) or an odd count of hex
        /// digits in `bytes` or `bytesN` (a leading zero added); a JSON 0 or 1 for a `bytesN`; `uint` and `int` as
        /// `uint256` and `int256`, their text kept in the type hash.
        ///
        /// Refused here and read in ``strict``: no `EIP712Domain` type (eth-sig-util hashes an empty one; ethers one
        /// made from the domain's keys); a bool written as a number; a JSON number a double does not hold exactly
        /// (JavaScript rounds it); a `0X` prefix. Also refused here: a struct name outside `A-Z a-z 0-9 _`
        /// (eth-sig-util finds a field's struct by the name's leading word characters), named as an atomic type or an
        /// alias, or named as a member every JavaScript object inherits; a domain type with a struct-typed field
        /// (eth-sig-util cannot hash one).
        case signTypedDataV4
        /// For a hardware signer: every struct value present and an object; no rounding, no defaults beyond the
        /// domain type a document leaves out, which is made from the standard fields its domain carries (EIP-712's
        /// order: name, version, chainId, verifyingContract, salt).
        case strict
    }

    /// The reading the document was read with.
    public let reading: Reading
    /// The message's struct type.
    public let primaryType: String
    /// Every struct type, by name in Unicode scalar order. `EIP712Domain` is among them (in the strict reading, made
    /// from the domain's standard fields when the JSON leaves it out).
    public let types: [StructDefinition]
    /// The domain, as a value of `EIP712Domain`.
    public let domain: Value
    /// The message, as a value of ``primaryType``.
    public let message: Value
    /// `hashStruct(domain)`: the domain separator.
    public let domainHash: Data
    /// `hashStruct(message)`.
    public let messageHash: Data
    /// What a key signs: `keccak256(0x19 0x01 ‖ domainHash ‖ messageHash)`.
    public let signingDigest: Data

    static let domainTypeName = "EIP712Domain"

    /// Reads `json` as EIP-712 typed data: an object with `types`, `primaryType`, `domain` and `message`.
    ///
    /// - Throws: ``EIP712DocumentError/invalidJSON(_:)`` for text that is not one JSON document or repeats a key;
    ///   ``EIP712DocumentError/refused(_:)`` for typed data `reading` refuses, with the reason.
    public init(json: String, reading: Reading) throws {
        try self.init(jsonData: Data(json.utf8), reading: reading)
    }

    /// Reads typed data from its JSON text's UTF-8 bytes. See ``init(json:reading:)``.
    public init(jsonData: Data, reading: Reading) throws {
        let document = try EIP712JSON.parse(jsonData)
        let reader = try EIP712Reader(document: document, reading: reading)
        self.reading = reading
        self.primaryType = reader.primaryType
        self.types = reader.definitions.sorted { $0.name.unicodeScalars.lexicographicallyPrecedes($1.name.unicodeScalars) }
        self.domain = try reader.walk(root: Self.domainTypeName, value: reader.domainJSON)
        self.message = try reader.walk(root: reader.primaryType, value: reader.messageJSON)
        var encoder = EIP712Encoder(types: types)
        self.domainHash = try encoder.encoding(of: domain)
        self.messageHash = try encoder.encoding(of: message)
        self.signingDigest = (Data([0x19, 0x01]) + domainHash + messageHash).sha3(.keccak256)
    }

    /// The struct type `name`; nil when the document defines none.
    public func definition(of name: String) -> StructDefinition? {
        StructLookup(types)[name]
    }

    /// EIP-712's `encodeType` for one of the document's struct types.
    public func encodeType(of name: String) throws -> String {
        try Self.encodeType(of: name, in: types)
    }

    /// `keccak256(encodeType(name))`.
    public func typeHash(of name: String) throws -> Data {
        Data(try encodeType(of: name).utf8).sha3(.keccak256)
    }

    /// What EIP-712's `encodeData` puts in place of a value: an atomic value's 32-byte word; the Keccak-256 of a
    /// `string`'s or `bytes`'s bytes; the Keccak-256 of an array's entries' encodings; a struct's `hashStruct`; 32 zero
    /// bytes for a struct that is null or left out.
    public func encoding(of value: Value) throws -> Data {
        var encoder = EIP712Encoder(types: types)
        return try encoder.encoding(of: value)
    }

    /// EIP-712's `encodeData` of a struct value: its type hash, then each field's ``encoding(of:)``.
    ///
    /// - Throws: ``EIP712DocumentError/refused(_:)`` for a value that is not a struct of this document's types.
    public func encodeData(of value: Value) throws -> Data {
        var encoder = EIP712Encoder(types: types)
        return try encoder.encodeData(of: value)
    }

    /// `keccak256(encodeData(value))`.
    public func hashStruct(of value: Value) throws -> Data {
        try encodeData(of: value).sha3(.keccak256)
    }

    /// Reads `json` as a value of the struct type `name`, with this document's types and `reading` (the document's
    /// own when nil).
    ///
    /// - Throws: ``EIP712DocumentError`` as ``init(json:reading:)`` does, and for a `name` the document does not define.
    public func value(ofStruct name: String, json: String, reading: Reading? = nil) throws -> Value {
        let parsed = try EIP712JSON.parse(Data(json.utf8))
        let reader = EIP712Reader(definitions: types, reading: reading ?? self.reading)
        try reader.requireDefined(reachedFrom: [name])
        return try reader.walk(root: name, value: parsed)
    }
}

/// Why typed data was not read.
public enum EIP712DocumentError: Error, Hashable, Sendable, CustomStringConvertible {
    /// The text is not one JSON document (RFC 8259), repeats a key, or nests deeper than 64 levels.
    case invalidJSON(String)
    /// The JSON is not typed data the reading accepts: malformed, ambiguous, or read another way by the reference.
    case refused(String)

    public var description: String {
        switch self {
        case .invalidJSON(let what): return "typed data: JSON: \(what)"
        case .refused(let what): return "typed data: \(what)"
        }
    }
}

// MARK: - Values

extension EIP712Document {
    /// One value as the JSON gives it and EIP-712 encodes it.
    public indirect enum Value: Hashable, Sendable {
        /// A struct: its type's name and its fields' values, in the order its ``StructDefinition`` lists the fields.
        case structure(type: String, fields: [Value])
        /// A struct-typed value that is null or left out: encoded as 32 zero bytes. Only the ``Reading/signTypedDataV4``
        /// reading makes one.
        case absentStructure(type: String)
        /// An array's entries, in order.
        case array([Value])
        /// An atomic or dynamic value.
        case primitive(PrimitiveValue)
    }

    /// An atomic or dynamic value: its type and its bytes.
    public struct PrimitiveValue: Hashable, Sendable {
        public let type: Primitive
        /// The value's bytes, as short as they go: an unsigned or non-negative integer's big-endian magnitude (`128` is
        /// the one byte `0x80`, zero is `0x00`); a negative integer in two's complement at its type's full width; an
        /// address's 20 bytes; a `bytesN`'s N (a shorter one padded on the right, in the phone-key reading); a bool's
        /// one byte; a `string`'s UTF-8; a `bytes`'s own bytes.
        public let bytes: Data

        init(type: Primitive, bytes: Data) {
            self.type = type
            self.bytes = bytes
        }

        /// What EIP-712's `encodeData` puts in its place: the 32-byte word of an atomic value (an integer widened by
        /// its sign, a `bytesN` padded on the right), or the Keccak-256 of a `string`'s or `bytes`'s bytes.
        public var encoded: Data {
            let padding = max(0, 32 - bytes.count)
            switch type {
            case .string, .bytes(nil):
                return bytes.sha3(.keccak256)
            case .bytes:
                return bytes + Data(count: padding)
            case .uint, .address, .bool:
                return Data(count: padding) + bytes
            case .int(let size):
                // A negative value is written at its type's full width, and a non-negative one of that width always
                // has its top bit clear.
                let isNegative = bytes.count == size && (bytes.first ?? 0) & 0x80 != 0
                return Data(repeating: isNegative ? 0xFF : 0x00, count: padding) + bytes
            }
        }
    }
}

// MARK: - Hashing

/// `encodeData` and `hashStruct` over a document's types, each struct's type hash worked out once.
struct EIP712Encoder {
    let types: [EIP712Document.StructDefinition]
    let lookup: StructLookup
    private var typeHashes: [ScalarKey: Data] = [:]

    init(types: [EIP712Document.StructDefinition]) {
        self.types = types
        self.lookup = StructLookup(types)
    }

    mutating func typeHash(of name: String) throws -> Data {
        if let known = typeHashes[ScalarKey(name)] { return known }
        let hash = Data(try EIP712Document.encodeType(of: name, in: types).utf8).sha3(.keccak256)
        typeHashes[ScalarKey(name)] = hash
        return hash
    }

    mutating func encodeData(of value: EIP712Document.Value) throws -> Data {
        guard case .structure(let type, let fields) = value else {
            throw EIP712DocumentError.refused("encodeData of a value that is not a struct")
        }
        guard let definition = lookup[type], definition.fields.count == fields.count else {
            throw EIP712DocumentError.refused("a value of \(type) that its definition does not describe")
        }
        var data = try typeHash(of: type)
        for field in fields { data.append(try encoding(of: field)) }
        return data
    }

    mutating func encoding(of value: EIP712Document.Value) throws -> Data {
        switch value {
        case .primitive(let primitive):
            return primitive.encoded
        case .absentStructure:
            return Data(count: 32)
        case .array(let entries):
            var data = Data()
            for entry in entries { data.append(try encoding(of: entry)) }
            return data.sha3(.keccak256)
        case .structure:
            return try encodeData(of: value).sha3(.keccak256)
        }
    }
}
