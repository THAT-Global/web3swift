//
//  EIP712Parser.swift
//
//  Created by JeneaVranceanu on 17.10.2023.
//
//  THAT fork (5.1.0): the hashing is Web3Core's `EIP712Document`, read from the JSON text. The encoder this file had
//  read only a `[]` suffix as an array (so `bool[2]` was encoded in place and `Leg[2]` threw) and built `encodeType`
//  from each child's whole subtree, sorting only direct children (so a struct reached only through another, or two
//  ways, got the wrong type hash). Its digest is never used again: what the document refuses throws.
//

import Foundation
import Web3Core

/// Parses `eth_signTypedData` JSON and outputs the EIP-712 hash ready for signing.
///
/// The JSON is read by ``EIP712Document`` with the ``EIP712Document/Reading/signTypedDataV4`` reading unless another
/// is named: the digest MetaMask's eth-sig-util V4 gives, or a thrown ``Web3Error/inputError(desc:)`` saying why not.
/// Example of a payload that is received via `eth_signTypedData_v4` for signing:
/// ```
/// {
///    "types":{
///       "EIP712Domain":[
///          {
///             "name":"name",
///             "type":"string"
///          },
///          {
///             "name":"version",
///             "type":"string"
///          },
///          {
///             "name":"chainId",
///             "type":"uint256"
///          },
///          {
///             "name":"verifyingContract",
///             "type":"address"
///          }
///       ],
///       "Person":[
///          {
///             "name":"name",
///             "type":"string"
///          },
///          {
///             "name":"wallet",
///             "type":"address"
///          }
///       ],
///       "Mail":[
///          {
///             "name":"from",
///             "type":"Person"
///          },
///          {
///             "name":"to",
///             "type":"Person"
///          },
///          {
///             "name":"contents",
///             "type":"string"
///          }
///       ]
///    },
///    "primaryType":"Mail",
///    "domain":{
///       "name":"Ether Mail",
///       "version":"1",
///       "chainId":1,
///       "verifyingContract":"0xCcCCccccCCCCcCCCCCCcCcCccCcCCCcCcccccccC"
///    },
///    "message":{
///       "from":{
///          "name":"Cow",
///          "wallet":"0xCD2a3d9F938E13CD947Ec05AbC7FE734Df8DD826"
///       },
///       "to":{
///          "name":"Bob",
///          "wallet":"0xbBbBBBBbbBBBbbbBbbBbbbbBBbBbbbbBbBbbBBbB"
///       },
///       "contents":"Hello, Bob!"
///    }
/// }
/// ```
///
/// Example use case:
/// ```
///     let payload: String = ... // This is the payload received from eth_signTypedData
///     let eip712TypedData = try EIP712Parser.parse(payload)
///     let signature = try Web3Signer.signEIP712(
///         eip712TypedData,
///         keystore: keystore,
///         account: account,
///         password: password)
/// ```
public class EIP712Parser {

    /// Reads `eth_signTypedData_v4` JSON for a key on the phone (``EIP712Document/Reading/signTypedDataV4``).
    public static func parse(_ rawJson: String) throws -> EIP712TypedData {
        try parse(Data(rawJson.utf8), reading: .signTypedDataV4)
    }

    /// Reads typed-data JSON with the reading named.
    public static func parse(_ rawJson: String, reading: EIP712Document.Reading) throws -> EIP712TypedData {
        try parse(Data(rawJson.utf8), reading: reading)
    }

    /// Reads `eth_signTypedData_v4` JSON, as UTF-8 bytes, for a key on the phone.
    public static func parse(_ rawJson: Data) throws -> EIP712TypedData {
        try parse(rawJson, reading: .signTypedDataV4)
    }

    /// Reads typed-data JSON, as UTF-8 bytes, with the reading named.
    ///
    /// - Throws: ``Web3Error/inputError(desc:)`` with the reason, for JSON the reading refuses.
    public static func parse(_ rawJson: Data, reading: EIP712Document.Reading) throws -> EIP712TypedData {
        let document: EIP712Document
        do {
            document = try EIP712Document(jsonData: rawJson, reading: reading)
        } catch let error as EIP712DocumentError {
            throw Web3Error.inputError(desc: "EIP712Parser. \(error.description)")
        }
        return try EIP712TypedData(document: document, json: rawJson)
    }
}

public struct EIP712TypeProperty: Codable {
    /// Property name. An arbitrary string.
    public let name: String
    /// Property type. A type that's ABI encodable or a custom type from ``EIP712TypedData/types``.
    public let type: String
    /// For an array, its entry type: the type with its LAST bracket removed (`uint8[2][]` holds `uint8[2]`s; `Leg[2]`
    /// holds `Leg`s). Otherwise the type itself.
    public let coreType: String
    /// Whether ``type`` is an array: `T[]` or `T[n]`, at any depth.
    public let isArray: Bool

    /// Trims whitespace from `name` and `type`, as this initialiser always has. A property read by ``EIP712Parser``
    /// is the JSON's, untrimmed.
    public init(name: String, type: String) {
        self.init(exactName: name.trimmingCharacters(in: .whitespacesAndNewlines),
                  exactType: type.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    init(exactName name: String, exactType type: String) {
        self.name = name
        self.type = type
        if let element = EIP712Document.FieldType(parsing: type).elementType {
            (coreType, isArray) = (element.text, true)
        } else {
            (coreType, isArray) = (type, false)
        }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let name = try container.decode(String.self, forKey: .name)
        let type = try container.decode(String.self, forKey: .type)
        self.init(name: name, type: type)
    }
}

public struct EIP712TypedData {
    public let types: [String: [EIP712TypeProperty]]
    /// A name of one of the types from `types`.
    public let primaryType: String
    /// The domain, as Foundation reads the JSON (for display; nothing is hashed from it).
    public let domain: [String : AnyObject]
    /// The message, as Foundation reads the JSON (for display; nothing is hashed from it).
    public let message: [String : AnyObject]
    /// The typed data as read from its JSON text: every hash below is this document's. Nil for a value made by the
    /// dictionary initialiser, whose hashes throw.
    public let document: EIP712Document?

    /// A value with no JSON text behind it.
    ///
    /// Its ``encodeType(_:)`` and ``typeHash(_:)`` are EIP-712's over `types`; its ``encodeData()``,
    /// ``encodeData(_:data:)``, ``structHash()``, ``structHash(_:data:)`` and ``signHash()`` throw, because
    /// dictionaries do not keep a number's digits or tell a reading what the JSON said.
    @available(*, deprecated, message: "A value made from dictionaries has no JSON text, so it is never hashed: signHash(), structHash() and encodeData() throw on it. Read typed data with EIP712Parser.parse(_:), or Web3Core's EIP712Document(json:reading:).")
    public init(types: [String : [EIP712TypeProperty]],
                primaryType: String,
                domain: [String : AnyObject],
                message: [String : AnyObject]) throws {
        self.types = types
        self.primaryType = primaryType.trimmingCharacters(in: .whitespacesAndNewlines)
        self.domain = domain
        self.message = message
        self.document = nil
    }

    /// What ``EIP712Parser`` makes: the document, and the JSON read by Foundation for the dictionaries.
    init(document: EIP712Document, json: Data) throws {
        guard let object = try json.asJsonDictionary(),
              let domain = object["domain"] as? [String: AnyObject],
              let message = object["message"] as? [String: AnyObject]
        else {
            throw Web3Error.inputError(desc: "EIP712Parser. Cannot read the domain and message as dictionaries.")
        }
        self.types = Dictionary(
            document.types.map { ($0.name, $0.fields.map { EIP712TypeProperty(exactName: $0.name, exactType: $0.type.text) }) },
            uniquingKeysWith: { first, _ in first })
        self.primaryType = document.primaryType
        self.domain = domain
        self.message = message
        self.document = document
    }

    private func readDocument() throws -> EIP712Document {
        guard let document else {
            throw Web3Error.processingError(desc: "EIP712Parser. Typed data made from dictionaries has no JSON text to hash. Read it with EIP712Parser.parse(_:).")
        }
        return document
    }

    private func mapped<T>(_ work: () throws -> T) throws -> T {
        do {
            return try work()
        } catch let error as EIP712DocumentError {
            throw Web3Error.processingError(desc: "EIP712Parser. \(error.description)")
        }
    }

    /// EIP-712's `encodeType`: `type`, then every struct it reaches at any depth, each once, by name.
    public func encodeType(_ type: String) throws -> String {
        try mapped {
            if let document { return try document.encodeType(of: type) }
            let definitions = types.map { name, properties in
                EIP712Document.StructDefinition(name: name, fields: properties.map {
                    EIP712Document.Field(name: $0.name, type: EIP712Document.FieldType(parsing: $0.type))
                })
            }
            return try EIP712Document.encodeType(of: type, in: definitions)
        }
    }

    public func typeHash(_ type: String) throws -> String {
        try encodeType(type).sha3(.keccak256).addHexPrefix()
    }

    /// Convenience function for ``encodeData(_:data:)`` that uses ``primaryType`` and ``message`` as values: the
    /// document's own message, as read from the JSON.
    /// - Returns: encoded data based on ``primaryType`` and ``message``.
    public func encodeData() throws -> Data {
        let document = try readDocument()
        return try mapped { try document.encodeData(of: document.message) }
    }

    /// EIP-712's `encodeData` of `data` as a value of `type`, with the document's types.
    ///
    /// `data` is written back to JSON and read with the ``EIP712Document/Reading/signTypedDataV4`` reading whatever
    /// the document's: Foundation holds a number past 38 digits rounded (2^128 comes back ending `…211450`), and that
    /// reading refuses every number a double does not hold exactly, so a rounded number is refused, never hashed. A
    /// value JSON cannot carry (`Data`, `BigUInt`) is refused too. A rounded number that was an exact double is never
    /// one again (the rounding is far finer than the spacing of doubles at its size); one that was not can only come
    /// from a document read with the strict reading, so for such a document this refuses outright.
    public func encodeData(_ type: String, data: [String : AnyObject]) throws -> Data {
        let document = try readDocument()
        guard document.reading == .signTypedDataV4 else {
            throw Web3Error.processingError(desc: "EIP712Parser. A strictly read document's dictionaries may hold rounded numbers; read the value with EIP712Document.value(ofStruct:json:).")
        }
        guard JSONSerialization.isValidJSONObject(data) else {
            throw Web3Error.inputError(desc: "EIP712Parser. The data for \(type) is not a JSON object.")
        }
        let json = String(decoding: try JSONSerialization.data(withJSONObject: data), as: UTF8.self)
        return try mapped { try document.encodeData(of: document.value(ofStruct: type, json: json, reading: .signTypedDataV4)) }
    }

    /// Convenience function for ``structHash(_:data:)`` that uses ``primaryType`` and ``message`` as values.
    /// - Returns: SH# keccak256 hash of encoded data based on ``primaryType`` and ``message``.
    public func structHash() throws -> Data {
        try readDocument().messageHash
    }

    public func structHash(_ type: String, data: [String : AnyObject]) throws -> Data {
        try encodeData(type, data: data).sha3(.keccak256)
    }

    /// `keccak256(0x19 0x01 ‖ hashStruct(domain) ‖ hashStruct(message))`: the document's ``EIP712Document/signingDigest``.
    public func signHash() throws -> Data {
        try readDocument().signingDigest
    }
}
