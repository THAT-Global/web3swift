//
//  EIP712Document+Reading.swift
//  Web3Core
//
//  Typed data's JSON read into definitions and values, in either reading. The walk and the value encoders are
//  ledger-core's (`EthereumTypedData.visit`, `encode`, `integer`, develop 980773a); what the phone-key reading adds or
//  refuses is marked where it happens, and each refusal says what MetaMask's eth-sig-util would have done instead.
//

import Foundation

struct EIP712Reader {
    typealias Document = EIP712Document

    let reading: Document.Reading
    let definitions: [Document.StructDefinition]
    let lookup: StructLookup
    private(set) var primaryType = ""
    private(set) var domainJSON = EIP712JSON.null
    private(set) var messageJSON = EIP712JSON.null

    /// How deep a value may nest below its root: struct fields and array entries each count one level.
    static let maximumDepth = 32

    /// Members every JavaScript object inherits from `Object.prototype`. eth-sig-util reads a field's value as
    /// `data[name]` and a type as `types[name]`, so under one of these names a value left out, or a type, is the
    /// inherited member rather than nothing.
    static let javaScriptObjectMembers: Set<String> = [
        "constructor", "hasOwnProperty", "isPrototypeOf", "propertyIsEnumerable", "toLocaleString", "toString",
        "valueOf", "__defineGetter__", "__defineSetter__", "__lookupGetter__", "__lookupSetter__", "__proto__",
    ]

    private static func refused(_ what: String) -> EIP712DocumentError { .refused(what) }

    init(definitions: [Document.StructDefinition], reading: Document.Reading) {
        self.reading = reading
        self.definitions = definitions
        self.lookup = StructLookup(definitions)
    }

    /// Reads a whole document's types and checks them; the domain and message are walked by ``walk(root:value:)``.
    init(document: EIP712JSON, reading: Document.Reading) throws {
        guard let typesMembers = document["types"]?.members,
              let primaryType = document["primaryType"]?.text,
              let domain = document["domain"], domain.members != nil,
              let message = document["message"], message.members != nil
        else {
            throw Self.refused("typed data is an object with types, primaryType, domain and message")
        }

        var definitions: [Document.StructDefinition] = []
        for member in typesMembers {
            let name = member.key
            guard !name.isEmpty else { throw Self.refused("a type with no name") }
            if reading == .signTypedDataV4 {
                // eth-sig-util finds the structs a field reaches by the leading run of word characters in its type
                // (`/^\w*/`), and looks a type up as a JavaScript property before it asks whether it is atomic.
                guard name.utf8.allSatisfy(Self.isWordCharacter) else {
                    throw Self.refused("the type name \"\(name)\" has a character outside A-Z, a-z, 0-9 and _")
                }
                guard Document.Primitive(parsing: name) == nil, Document.RootType.aliases[name] == nil else {
                    throw Self.refused("a struct named \(name), as an atomic type is")
                }
                guard !Self.javaScriptObjectMembers.contains(name) else {
                    throw Self.refused("a struct named \(name), as a member every JavaScript object has")
                }
            }
            guard let entries = member.value.elements else { throw Self.refused("the type \(name) is not a list of fields") }
            var fields: [Document.Field] = []
            // Compared by canonical equivalence: two spellings of one name are refused as one name twice.
            var names = Set<String>()
            for entry in entries {
                guard let fieldName = entry["name"]?.text, let type = entry["type"]?.text else {
                    throw Self.refused("a field of \(name) without a name and a type")
                }
                guard names.insert(fieldName).inserted else { throw Self.refused("the field \(name).\(fieldName) twice") }
                // The phone-key reading reads `uint` and `int` as eth-sig-util and the old web3swift did (no struct can
                // have those names in it).
                let fieldType = Document.FieldType(parsing: type)
                fields.append(Document.Field(name: fieldName, type: reading == .signTypedDataV4 ? fieldType.aliasingItsRoot : fieldType))
            }
            definitions.append(Document.StructDefinition(name: name, fields: fields))
        }

        if StructLookup(definitions)[Document.domainTypeName] == nil {
            guard reading == .strict else {
                // eth-sig-util hashes the domain as an `EIP712Domain` with no fields; ethers builds the type from the
                // domain's keys; the strict reading from its standard fields. Readers disagree: refused.
                throw Self.refused("no EIP712Domain type")
            }
            // The domain type the JSON leaves out is made from the standard fields the domain carries, in EIP-712's order.
            let standard: [(String, Document.Primitive)] = [
                ("name", .string), ("version", .string), ("chainId", .uint(32)),
                ("verifyingContract", .address), ("salt", .bytes(32)),
            ]
            let present = standard.filter { domain[$0.0] != nil }
            if !present.isEmpty {
                definitions.append(Document.StructDefinition(
                    name: Document.domainTypeName,
                    fields: present.map { Document.Field(name: $0.0, type: .root(.primitive($0.1))) }))
            }
        }

        self.init(definitions: definitions, reading: reading)
        guard lookup[primaryType] != nil else { throw Self.refused("the primary type \(primaryType) is not defined") }
        guard let domainType = lookup[Document.domainTypeName] else { throw Self.refused("the domain has no fields") }
        // eth-sig-util hashes only the domain for this primary type (no message hash); EIP-712 defines no such digest.
        guard primaryType != Document.domainTypeName else { throw Self.refused("the domain as the primary type") }
        if reading == .signTypedDataV4 {
            // eth-sig-util hashes the domain with `EIP712Domain` as its only type, so a struct-typed field cannot be hashed.
            for field in domainType.fields {
                if case .structure = field.type.rootType {
                    throw Self.refused("the domain's field \(field.name) has a struct type")
                }
            }
        }
        try requireDefined(reachedFrom: [primaryType, Document.domainTypeName])
        self.primaryType = primaryType
        self.domainJSON = domain
        self.messageJSON = message
    }

    /// Every struct the types of `roots` reach, at any depth, is defined: an undefined one is refused even where no
    /// value reaches it (an empty array of it, say), since its name is still hashed into the type.
    func requireDefined(reachedFrom roots: [String]) throws {
        var seen = Set<ScalarKey>()
        var pending = roots.map { (name: $0, from: $0) }
        while let next = pending.popLast() {
            let (name, from) = next
            guard seen.insert(ScalarKey(name)).inserted else { continue }
            guard let definition = lookup[name] else { throw Self.refused("\(from) has the undefined type \(name)") }
            for field in definition.fields {
                if case .structure(let inner) = field.type.rootType { pending.append((inner, "\(name).\(field.name)")) }
            }
        }
    }

    private static func isWordCharacter(_ byte: UInt8) -> Bool {
        switch byte {
        case UInt8(ascii: "A")...UInt8(ascii: "Z"), UInt8(ascii: "a")...UInt8(ascii: "z"),
             UInt8(ascii: "0")...UInt8(ascii: "9"), UInt8(ascii: "_"):
            return true
        default:
            return false
        }
    }

    // MARK: Values

    /// The value of the struct type `root` that `value` gives, its fields in declaration order, depth first.
    func walk(root: String, value: EIP712JSON) throws -> Document.Value {
        guard value.members != nil else { throw Self.refused("\(root) is not an object") }
        return try visit(.root(.structure(root)), value, path: root, depth: 0, fieldName: nil)
    }

    /// One value of `type`. `value` is nil for a struct's field the JSON leaves out.
    private func visit(
        _ type: Document.FieldType, _ value: EIP712JSON?, path: String, depth: Int, fieldName: String?
    ) throws -> Document.Value {
        guard depth <= Self.maximumDepth else { throw Self.refused("\(path) nests too deep") }
        switch type {
        case .root(.structure(let name)):
            guard let definition = lookup[name] else { throw Self.refused("\(path) has the undefined type \(name)") }
            switch value {
            case nil:
                guard reading == .signTypedDataV4 else { throw Self.refused("\(path) is missing") }
                // eth-sig-util V4 encodes a struct-typed field whose value is undefined as 32 zero bytes, unless the
                // name is one JavaScript objects inherit: then `data[name]` is that member, not undefined.
                if let fieldName, Self.javaScriptObjectMembers.contains(fieldName) {
                    throw Self.refused("\(path) is left out under a name every JavaScript object has")
                }
                return .absentStructure(type: name)
            case .null?:
                guard reading == .signTypedDataV4 else { throw Self.refused("\(path) is null") }
                return .absentStructure(type: name)
            case .object?:
                var fields: [Document.Value] = []
                for field in definition.fields {
                    fields.append(try visit(
                        field.type, value?[field.name], path: "\(path).\(field.name)", depth: depth + 1,
                        fieldName: field.name))
                }
                return .structure(type: name, fields: fields)
            default:
                throw Self.refused("\(path) is not an object")
            }
        case .root(.primitive(let primitive)):
            return try primitiveValue(value, as: primitive, path: path)
        case .root(.alias(let name)):
            guard let primitive = Document.RootType.aliases[name] else { throw Self.refused("\(path) has the unknown type \(name)") }
            return try primitiveValue(value, as: primitive, path: path)
        case .array(_, let levels):
            guard let value else { throw Self.refused("\(path) is missing") }
            guard let elements = value.elements else { throw Self.refused("\(path) is not an array") }
            // The last bracket is this dimension; the rest are each entry's own.
            if let fixed = levels.last ?? nil, fixed != elements.count {
                throw Self.refused("\(path) has \(elements.count) entries where its type has \(fixed)")
            }
            guard let elementType = type.elementType else { throw Self.refused("\(path) has no entry type") }
            var entries: [Document.Value] = []
            for (index, element) in elements.enumerated() {
                entries.append(try visit(elementType, element, path: "\(path)[\(index)]", depth: depth + 1, fieldName: nil))
            }
            return .array(entries)
        }
    }

    private func primitiveValue(_ value: EIP712JSON?, as primitive: Document.Primitive, path: String) throws -> Document.Value {
        guard let value else { throw Self.refused("\(path) is missing") }
        do {
            return .primitive(Document.PrimitiveValue(type: primitive, bytes: try encode(value, as: primitive)))
        } catch EIP712DocumentError.refused(let what) {
            throw Self.refused("\(what) at \(path)")
        }
    }

    /// One primitive value's bytes, as short as they go: see ``EIP712Document/PrimitiveValue/bytes``.
    private func encode(_ value: EIP712JSON, as type: Document.Primitive) throws -> Data {
        switch type {
        case .string:
            // eth-sig-util hashes a number's bytes, and null as "", in a string's place.
            guard case .string(let text) = value else { throw Self.refused("a string that is not text") }
            return Data(text.utf8)
        case .address:
            return try hexBytes(value, size: 20, isAddress: true)
        case .bytes(let size?) where reading == .signTypedDataV4:
            // A JSON 0 or 1: the old web3swift read it as a Bool's one byte and eth-sig-util as the number's one byte,
            // the same byte. Any other number: eth-sig-util takes its bytes and the old web3swift refused; refused here.
            if case .number(let text) = value {
                let (isNegative, magnitude) = try Self.exactDoubleInteger(text)
                guard magnitude == [0] || (magnitude == [1] && !isNegative) else {
                    throw Self.refused("a number in place of bytes, other than 0 or 1")
                }
                return Data(magnitude) + Data(count: size - 1)
            }
            return try hexBytes(value, size: size, isAddress: false)
        case .bytes(let size):
            return try hexBytes(value, size: size, isAddress: false)
        case .bool:
            if case .bool(let flag) = value { return Data([flag ? 1 : 0]) }
            // eth-sig-util 9 reads the strings "true" and "false" as booleans (its releases before November 2026 read
            // any non-empty string as true) and refuses numbers. The strict reading takes 0 and 1, as ledger-core does.
            guard reading == .strict else { throw Self.refused("a bool that is not true or false") }
            return try integer(value, bits: 1, signed: false)
        case .uint(let size):
            return try integer(value, bits: size * 8, signed: false)
        case .int(let size):
            return try integer(value, bits: size * 8, signed: true)
        }
    }

    /// Whether `text` starts with the hex prefix this reading takes: `0x`, or `0X` too in the strict reading.
    private func hasHexPrefix<Bytes: Collection>(_ utf8: Bytes) -> Bool where Bytes.Element == UInt8 {
        var iterator = utf8.makeIterator()
        guard iterator.next() == UInt8(ascii: "0"), let x = iterator.next() else { return false }
        return x == UInt8(ascii: "x") || (reading == .strict && x == UInt8(ascii: "X"))
    }

    /// `0x` and hex digits. The strict reading takes an even count and exactly `size` bytes when a size is due.
    ///
    /// The phone-key reading reads `bytes` and `bytesN` as eth-sig-util does where the old web3swift signed the same or
    /// eth-sig-util is the only reading: an odd count of digits gains a leading zero (`0x5` is the byte 05), and a
    /// `bytesN` shorter than N is padded with zero bytes on the right (`bytes32` `0x10`, a 3-byte salt). Longer than N,
    /// text that is not hex, and an address that is not 40 digits are refused (eth-sig-util reads other text as UTF-8,
    /// or an address digit by digit).
    private func hexBytes(_ value: EIP712JSON, size: Int?, isAddress: Bool) throws -> Data {
        guard case .string(let text) = value else { throw Self.refused("bytes that are not 0x-prefixed hex") }
        var digits = Array(text.utf8)
        guard hasHexPrefix(digits) else { throw Self.refused("bytes that are not 0x-prefixed hex") }
        digits.removeFirst(2)
        let isPhone = reading == .signTypedDataV4
        if isPhone, !isAddress, !digits.count.isMultiple(of: 2) { digits.insert(UInt8(ascii: "0"), at: 0) }
        guard let bytes = EIP712Hex.bytes(digits) else { throw Self.refused("bytes that are not 0x-prefixed hex of whole bytes") }
        guard let size else { return bytes }
        if isPhone, !isAddress, bytes.count < size { return bytes + Data(count: size - bytes.count) }
        guard bytes.count == size else { throw Self.refused("\(bytes.count) bytes where \(size) are due") }
        return bytes
    }

    /// An integer from a JSON number, a decimal string (`-` allowed), or a `0x` string. Read from its text, by long
    /// multiplication: exact at any length, never through a floating-point value.
    ///
    /// The strict reading takes a JSON number written as a whole number in full, at most 80 decimal or 64 hex digits.
    /// The phone-key reading takes a JSON number whose value is a whole number a double holds exactly (see
    /// ``exactDoubleInteger(_:)``), trims space around a string (``trimmedOfSpace(_:)``), takes a decimal string's `+`,
    /// and takes leading zeros at any length: as the old web3swift and eth-sig-util both did.
    private func integer(_ value: EIP712JSON, bits: Int, signed: Bool) throws -> Data {
        let isPhone = reading == .signTypedDataV4
        var isNegative = false
        var magnitude: [UInt8]
        switch value {
        case .number(let text) where isPhone:
            (isNegative, magnitude) = try Self.exactDoubleInteger(text)
        case .number(let text), .string(let text):
            let isJSONNumber: Bool
            if case .number = value { isJSONNumber = true } else { isJSONNumber = false }
            let literal = Array((isPhone ? Self.trimmedOfSpace(text) : text).utf8)[...]
            if !isJSONNumber, hasHexPrefix(literal) {
                var digits = Array(literal.dropFirst(2))
                guard !digits.isEmpty, digits.allSatisfy({ EIP712Hex.digit($0) != nil }) else {
                    throw Self.refused("a number that is not hex")
                }
                if isPhone { while digits.count > 1, digits.first == UInt8(ascii: "0") { digits.removeFirst() } }
                guard digits.count <= 64 else { throw Self.refused("a number that is not hex") }
                if !digits.count.isMultiple(of: 2) { digits.insert(UInt8(ascii: "0"), at: 0) }
                magnitude = [UInt8](EIP712Hex.bytes(digits) ?? Data())
            } else {
                var digits = literal
                if digits.first == UInt8(ascii: "-") {
                    isNegative = true
                    digits = digits.dropFirst()
                } else if isPhone, !isJSONNumber, digits.first == UInt8(ascii: "+") {
                    // A decimal string's `+`: the old web3swift's BigInt and JavaScript's BigInt both read it.
                    digits = digits.dropFirst()
                }
                guard !digits.isEmpty, digits.allSatisfy({ (UInt8(ascii: "0")...UInt8(ascii: "9")).contains($0) }) else {
                    throw Self.refused("a number that is not a whole number written in full")
                }
                if isPhone { while digits.count > 1, digits.first == UInt8(ascii: "0") { digits = digits.dropFirst() } }
                guard digits.count <= 80 else { throw Self.refused("a number that is not a whole number written in full") }
                magnitude = Self.decimalToBytes(digits)
            }
        default:
            throw Self.refused("a number that is not a number")
        }
        while magnitude.count > 1, magnitude[0] == 0 { magnitude.removeFirst() }
        if magnitude.isEmpty { magnitude = [0] }
        let isZero = magnitude == [0]
        let bitLength = Self.bitLength(magnitude)

        if !signed {
            guard !isNegative || isZero, bitLength <= bits else { throw Self.refused("a number out of its type's range") }
            return Data(magnitude)
        }
        if !isNegative || isZero {
            guard bitLength <= bits - 1 else { throw Self.refused("a number out of its type's range") }
            return Data(magnitude)
        }
        // Negative: within range when the magnitude is at most 2^(bits-1), then two's complement at the type's width.
        let isLimit = bitLength == bits && magnitude[0].nonzeroBitCount == 1 && magnitude.dropFirst().allSatisfy { $0 == 0 }
        guard bitLength <= bits - 1 || isLimit else { throw Self.refused("a number out of its type's range") }
        var wide = [UInt8](repeating: 0, count: bits / 8 - magnitude.count) + magnitude
        var carry = true
        for index in wide.indices.reversed() {
            let (sum, overflow) = (~wide[index]).addingReportingOverflow(carry ? 1 : 0)
            wide[index] = sum
            carry = overflow
        }
        return Data(wide)
    }

    /// `text` without the space both the old web3swift (Foundation's `.whitespacesAndNewlines`) and JavaScript's
    /// `BigInt` trimmed from a number string: tab, LF, VT, FF, CR, U+2028, U+2029 and every space separator (Zs).
    static func trimmedOfSpace(_ text: String) -> String {
        func isSpace(_ scalar: Unicode.Scalar) -> Bool {
            (0x09...0x0D).contains(scalar.value) || scalar.value == 0x2028 || scalar.value == 0x2029
                || scalar.properties.generalCategory == .spaceSeparator
        }
        var scalars = text.unicodeScalars[...]
        while let first = scalars.first, isSpace(first) { scalars = scalars.dropFirst() }
        while let last = scalars.last, isSpace(last) { scalars = scalars.dropLast() }
        return String(String.UnicodeScalarView(scalars))
    }

    private static func bitLength(_ magnitude: [UInt8]) -> Int {
        guard let first = magnitude.firstIndex(where: { $0 != 0 }) else { return 0 }
        return (magnitude.count - first - 1) * 8 + (8 - magnitude[first].leadingZeroBitCount)
    }

    /// A JSON number's value when it is a whole number that an IEEE-754 double holds exactly: then the text, JavaScript's
    /// `JSON.parse` and eth-sig-util all read the same value (`1000000000000000000`, `1.0`, `1E3`, `12.0e0`, `1e+21`).
    /// Anything else is refused: a fraction (`1.5`), or a whole number no double holds (`12345678901234567890`, which
    /// JavaScript rounds, so the text and the dapp disagree).
    ///
    /// Decided from the text with exact arithmetic: digits × 10^exponent must be whole, below 2^1024, and below 2^53
    /// once its trailing zero bits are gone. No cap below that is needed: text that has passed through Foundation (as
    /// dapp-core's re-serialised typed data has) is perturbed by far less than the spacing of doubles at its size, so a
    /// perturbed number is never an exact double: it is refused, never read as another value.
    ///
    /// - Returns: the sign and the big-endian magnitude (`[0]` for zero).
    static func exactDoubleInteger(_ text: String) throws -> (isNegative: Bool, magnitude: [UInt8]) {
        let bytes = Array(text.utf8)
        func isDigit(_ byte: UInt8) -> Bool { (UInt8(ascii: "0")...UInt8(ascii: "9")).contains(byte) }
        var index = 0
        let isNegative = bytes.first == UInt8(ascii: "-")
        if isNegative { index += 1 }
        var digits: [UInt8] = []
        while index < bytes.count, isDigit(bytes[index]) { digits.append(bytes[index]); index += 1 }
        var fractionCount = 0
        if index < bytes.count, bytes[index] == UInt8(ascii: ".") {
            index += 1
            while index < bytes.count, isDigit(bytes[index]) { digits.append(bytes[index]); fractionCount += 1; index += 1 }
        }
        var exponent = 0
        if index < bytes.count, bytes[index] == UInt8(ascii: "e") || bytes[index] == UInt8(ascii: "E") {
            index += 1
            var exponentIsNegative = false
            if index < bytes.count, bytes[index] == UInt8(ascii: "+") || bytes[index] == UInt8(ascii: "-") {
                exponentIsNegative = bytes[index] == UInt8(ascii: "-")
                index += 1
            }
            while index < bytes.count, isDigit(bytes[index]) {
                // Saturates far past any exponent that could still give a value below 2^1024 or a whole number.
                exponent = min(exponent * 10 + Int(bytes[index] - UInt8(ascii: "0")), 1_000_000_000)
                index += 1
            }
            if exponentIsNegative { exponent = -exponent }
        }
        guard index == bytes.count, !digits.isEmpty else { throw refused("a number that is not a number") }
        var scale = exponent - fractionCount
        while let first = digits.first, first == UInt8(ascii: "0") { digits.removeFirst() }
        guard !digits.isEmpty else { return (isNegative, [0]) }
        while let last = digits.last, last == UInt8(ascii: "0") {
            digits.removeLast()
            scale += 1
        }
        guard scale >= 0 else { throw refused("a JSON number that is not a whole number") }
        // 2^1024 has 309 decimal digits.
        guard digits.count + scale <= 309 else { throw refused("a JSON number past what a double holds") }
        let magnitude = decimalToBytes((digits + [UInt8](repeating: UInt8(ascii: "0"), count: scale))[...])
        let length = bitLength(magnitude)
        var trailingZeroBits = 0
        for byte in magnitude.reversed() {
            if byte == 0 { trailingZeroBits += 8 } else { trailingZeroBits += byte.trailingZeroBitCount; break }
        }
        guard length <= 1024, length - trailingZeroBits <= 53 else {
            throw refused("a JSON number JavaScript cannot hold exactly")
        }
        return (isNegative, magnitude)
    }

    /// Base ten to big-endian bytes, by long multiplication: exact at any length.
    private static func decimalToBytes(_ digits: ArraySlice<UInt8>) -> [UInt8] {
        var bytes: [UInt8] = [0]
        for digit in digits {
            var carry = Int(digit - UInt8(ascii: "0"))
            for index in bytes.indices.reversed() {
                let product = Int(bytes[index]) * 10 + carry
                bytes[index] = UInt8(product & 0xFF)
                carry = product >> 8
            }
            while carry > 0 {
                bytes.insert(UInt8(carry & 0xFF), at: 0)
                carry >>= 8
            }
        }
        return bytes
    }
}
