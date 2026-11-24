//
//  EIP712Document+Types.swift
//  Web3Core
//
//  The types of EIP-712 typed data, as EIP-712 writes them. Lifted from ledger-core's `EthereumTypedData` (develop
//  980773a). A type is read the one way EIP-712 spells it: `uint08`, `bytes04` and `x[02]` are not their canonical
//  selves, because a type's text is part of what is hashed.
//

import Foundation

extension EIP712Document {
    /// An atomic or dynamic type.
    public enum Primitive: Hashable, Sendable {
        /// A signed integer; its size in bytes, 1 to 32.
        case int(Int)
        /// An unsigned integer; its size in bytes, 1 to 32.
        case uint(Int)
        case address
        case bool
        case string
        /// `bytes1` to `bytes32` (the size in bytes), or nil for dynamic `bytes`.
        case bytes(Int?)

        /// The type as EIP-712 writes it: `uint256`, `bytes4`, `bytes`.
        public var text: String {
            switch self {
            case .int(let bytes): return "int\(bytes * 8)"
            case .uint(let bytes): return "uint\(bytes * 8)"
            case .address: return "address"
            case .bool: return "bool"
            case .string: return "string"
            case .bytes(let size?): return "bytes\(size)"
            case .bytes(nil): return "bytes"
            }
        }

        /// `string` and `bytes`: EIP-712 encodes them as the Keccak-256 of their bytes, not as a word.
        public var isDynamic: Bool {
            switch self {
            case .string, .bytes(nil): return true
            default: return false
            }
        }

        /// The primitive `text` names, written the one way EIP-712 writes it; nil for anything else.
        public init?(parsing text: String) {
            // Every primitive's name is ASCII, and two ASCII strings are equal only byte for byte (Swift's `==` is
            // canonical equivalence, which no other text can meet here).
            guard text.utf8.allSatisfy({ $0 < 0x80 }) else { return nil }
            switch text {
            case "address": self = .address; return
            case "bool": self = .bool; return
            case "string": self = .string; return
            case "bytes": self = .bytes(nil); return
            default: break
            }
            func sized(_ prefix: String) -> Int? {
                guard text.hasPrefix(prefix) else { return nil }
                let digits = text.utf8.dropFirst(prefix.utf8.count)
                guard !digits.isEmpty, digits.count <= 3, digits.first != UInt8(ascii: "0"),
                      digits.allSatisfy({ (UInt8(ascii: "0")...UInt8(ascii: "9")).contains($0) })
                else { return nil }
                return Int(String(decoding: digits, as: UTF8.self))
            }
            // `uint8` to `uint256` and `int8` to `int256`, in whole bytes. `uint` is tried before `int`.
            if let bits = sized("uint") {
                guard bits > 0, bits <= 256, bits.isMultiple(of: 8) else { return nil }
                self = .uint(bits / 8)
            } else if let bits = sized("int") {
                guard bits > 0, bits <= 256, bits.isMultiple(of: 8) else { return nil }
                self = .int(bits / 8)
            } else if let size = sized("bytes") {
                guard size > 0, size <= 32 else { return nil }
                self = .bytes(size)
            } else {
                return nil
            }
        }
    }

    /// What an array holds at its bottom, or a field's type when it is not an array.
    public enum RootType: Hashable, Sendable {
        case primitive(Primitive)
        /// A struct type, by name.
        case structure(String)

        public var text: String {
            switch self {
            case .primitive(let primitive): return primitive.text
            case .structure(let name): return name
            }
        }
    }

    /// A field's type.
    public enum FieldType: Hashable, Sendable {
        case root(RootType)
        /// `root[2][][4]` has levels `[2, nil, 4]`: a count, or nil for a dynamic dimension. The LAST bracket is the
        /// outermost dimension: a `uint8[2][]` is an array of any length whose entries are each a `uint8[2]`.
        case array(root: RootType, levels: [Int?])

        /// Reads a type as EIP-712 spells it. It never fails: text that is neither a primitive nor an array of a root
        /// type is a struct's name, and is refused where it is used when no struct has that name.
        public init(parsing text: String) {
            if let primitive = Primitive(parsing: text) {
                self = .root(.primitive(primitive))
            } else if let array = Self.parseArray(text) {
                self = array
            } else {
                self = .root(.structure(text))
            }
        }

        /// `root[2][][4]`: a root type followed by one or more brackets, each empty or a count without leading zeros.
        private static func parseArray(_ text: String) -> FieldType? {
            guard let firstBracket = text.firstIndex(of: "[") else { return nil }
            let rootText = String(text[..<firstBracket])
            var levels: [Int?] = []
            var rest = text[firstBracket...]
            while !rest.isEmpty {
                guard rest.first == "[", let close = rest.firstIndex(of: "]") else { return nil }
                let inside = rest[rest.index(after: rest.startIndex)..<close]
                if inside.isEmpty {
                    levels.append(nil)
                } else {
                    guard inside.utf8.allSatisfy({ (UInt8(ascii: "0")...UInt8(ascii: "9")).contains($0) }),
                          inside.first != "0" || inside.count == 1,
                          let count = Int(inside)
                    else { return nil }
                    levels.append(count)
                }
                rest = rest[rest.index(after: close)...]
            }
            guard !levels.isEmpty, !rootText.contains("]") else { return nil }
            let root: RootType = Primitive(parsing: rootText).map(RootType.primitive) ?? .structure(rootText)
            return .array(root: root, levels: levels)
        }

        /// The type as EIP-712 writes it. For a type read with ``init(parsing:)`` it is the text read.
        public var text: String {
            switch self {
            case .root(let root): return root.text
            case .array(let root, let levels): return root.text + levels.map { $0.map { "[\($0)]" } ?? "[]" }.joined()
            }
        }

        /// The type at the bottom of every array level.
        public var rootType: RootType {
            switch self {
            case .root(let root): return root
            case .array(let root, _): return root
            }
        }

        /// An array's entry type (its last bracket removed); nil for a type that is not an array.
        public var elementType: FieldType? {
            guard case .array(let root, let levels) = self else { return nil }
            let inner = Array(levels.dropLast())
            return inner.isEmpty ? .root(root) : .array(root: root, levels: inner)
        }
    }

    /// One field of a struct type.
    public struct Field: Hashable, Sendable {
        public let name: String
        public let type: FieldType

        public init(name: String, type: FieldType) {
            self.name = name
            self.type = type
        }
    }

    /// A struct type: its name and its fields, in the order the JSON lists them.
    public struct StructDefinition: Hashable, Sendable {
        public let name: String
        public let fields: [Field]

        public init(name: String, fields: [Field]) {
            self.name = name
            self.fields = fields
        }

        /// `Name(type1 name1,type2 name2)`: the struct alone, without the types it reaches.
        public var encodedAlone: String {
            name + "(" + fields.map { "\($0.type.text) \($0.name)" }.joined(separator: ",") + ")"
        }
    }

    /// EIP-712's `encodeType`: the struct `name`, then every struct it reaches through its fields, at any depth, each
    /// once, by name in Unicode scalar order. A field's struct type that `types` does not define is left out, as
    /// eth-sig-util, ledger-core and the old web3swift leave it out (a document that reaches one is refused when read).
    ///
    /// - Throws: ``EIP712DocumentError/refused(_:)`` when `name` is not among `types`.
    public static func encodeType(of name: String, in types: [StructDefinition]) throws -> String {
        let lookup = StructLookup(types)
        guard let primary = lookup[name] else { throw EIP712DocumentError.refused("the type \(name) is not defined") }
        var reached: [StructDefinition] = []
        var seen = Set<ScalarKey>([ScalarKey(name)])
        var pending = [primary]
        while let definition = pending.popLast() {
            for field in definition.fields {
                guard case .structure(let inner) = field.type.rootType, seen.insert(ScalarKey(inner)).inserted,
                      let reachedDefinition = lookup[inner]
                else { continue }
                reached.append(reachedDefinition)
                pending.append(reachedDefinition)
            }
        }
        reached.sort { $0.name.unicodeScalars.lexicographicallyPrecedes($1.name.unicodeScalars) }
        return ([primary] + reached).map(\.encodedAlone).joined()
    }
}

/// A name compared scalar for scalar (Swift's `String ==` is canonical equivalence; a JSON key is not).
struct ScalarKey: Hashable, Sendable {
    let scalars: [UInt32]
    init(_ text: String) { scalars = text.unicodeScalars.map(\.value) }
}

/// Struct definitions by exact name.
struct StructLookup: Sendable {
    private let byName: [ScalarKey: EIP712Document.StructDefinition]

    init(_ definitions: [EIP712Document.StructDefinition]) {
        byName = Dictionary(definitions.map { (ScalarKey($0.name), $0) }) { first, _ in first }
    }

    subscript(name: String) -> EIP712Document.StructDefinition? { byName[ScalarKey(name)] }
}
