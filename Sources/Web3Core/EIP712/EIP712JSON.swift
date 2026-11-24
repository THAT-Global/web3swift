//
//  EIP712JSON.swift
//  Web3Core
//
//  A JSON reader for typed data that gets signed, lifted from ledger-core's `StrictJSON` (develop 980773a). Three things
//  Foundation's reader does not promise, and typed data needs: a number keeps its digits exactly (a uint256 has up to 78
//  of them; a parsed double or decimal has fewer), an object keeps its members in order, and a repeated key is refused
//  instead of one of the two winning (Foundation keeps one, JavaScript the other).
//
//  One change from ledger-core: a string's bytes are decoded as UTF-8 by the standard library's validating decoder, not
//  by Foundation, so nothing in a string is dropped or replaced on the way to its hash.
//

import Foundation

indirect enum EIP712JSON: Equatable, Sendable {
    case object([Member])
    case array([EIP712JSON])
    case string(String)
    /// The number's text exactly as written.
    case number(String)
    case bool(Bool)
    case null

    struct Member: Equatable, Sendable {
        let key: String
        let value: EIP712JSON
    }

    /// The value of `key` in an object; nil for a key that is not there or a value that is not an object.
    ///
    /// The key is matched scalar for scalar, as JavaScript matches a property name: `"é"` written as one scalar and as
    /// `e` with a combining accent are two keys (Swift's `==` would call them one).
    subscript(key: String) -> EIP712JSON? {
        guard case .object(let members) = self else { return nil }
        return members.first { $0.key.unicodeScalars.elementsEqual(key.unicodeScalars) }?.value
    }

    var members: [Member]? {
        if case .object(let members) = self { return members }
        return nil
    }

    var elements: [EIP712JSON]? {
        if case .array(let elements) = self { return elements }
        return nil
    }

    var text: String? {
        if case .string(let text) = self { return text }
        return nil
    }

    /// The deepest a document may nest.
    static let maximumDepth = 64

    /// Reads one JSON document (RFC 8259) from its UTF-8 bytes.
    ///
    /// - Throws: `EIP712DocumentError.invalidJSON` for anything RFC 8259 does not allow, for a repeated key, and for
    ///   nesting past ``maximumDepth`` levels.
    static func parse<Bytes: Collection>(_ bytes: Bytes) throws -> EIP712JSON where Bytes.Element == UInt8 {
        var parser = Parser(bytes: Array(bytes))
        parser.skipWhitespace()
        let value = try parser.value(depth: 0)
        parser.skipWhitespace()
        guard parser.isAtEnd else { throw Parser.failure("text after the document") }
        return value
    }

    private struct Parser {
        let bytes: [UInt8]
        var index = 0

        var isAtEnd: Bool { index == bytes.count }

        static func failure(_ what: String) -> EIP712DocumentError {
            .invalidJSON(what)
        }

        mutating func skipWhitespace() {
            while index < bytes.count, [0x20, 0x09, 0x0A, 0x0D].contains(bytes[index]) { index += 1 }
        }

        mutating func value(depth: Int) throws -> EIP712JSON {
            guard depth <= EIP712JSON.maximumDepth else { throw Self.failure("nested too deep") }
            guard index < bytes.count else { throw Self.failure("ends early") }
            switch bytes[index] {
            case UInt8(ascii: "{"): return try object(depth: depth)
            case UInt8(ascii: "["): return try array(depth: depth)
            case UInt8(ascii: "\""): return .string(try string())
            case UInt8(ascii: "t"): try literal("true"); return .bool(true)
            case UInt8(ascii: "f"): try literal("false"); return .bool(false)
            case UInt8(ascii: "n"): try literal("null"); return .null
            default: return .number(try number())
            }
        }

        private mutating func literal(_ word: String) throws {
            let wanted = Array(word.utf8)
            guard index + wanted.count <= bytes.count, Array(bytes[index..<index + wanted.count]) == wanted else {
                throw Self.failure("an unknown word")
            }
            index += wanted.count
        }

        private mutating func object(depth: Int) throws -> EIP712JSON {
            index += 1
            var members: [Member] = []
            var seen = Set<String>()
            skipWhitespace()
            if index < bytes.count, bytes[index] == UInt8(ascii: "}") {
                index += 1
                return .object([])
            }
            while true {
                skipWhitespace()
                guard index < bytes.count, bytes[index] == UInt8(ascii: "\"") else { throw Self.failure("a key that is not a string") }
                let key = try string()
                // `Set<String>` compares by canonical equivalence, so two spellings of one character count as one key
                // repeated: refused, where JavaScript would keep both and a reader could be shown either.
                guard seen.insert(key).inserted else { throw Self.failure("the key \"\(key)\" twice") }
                skipWhitespace()
                guard index < bytes.count, bytes[index] == UInt8(ascii: ":") else { throw Self.failure("a key with no value") }
                index += 1
                skipWhitespace()
                members.append(Member(key: key, value: try value(depth: depth + 1)))
                skipWhitespace()
                guard index < bytes.count else { throw Self.failure("ends early") }
                if bytes[index] == UInt8(ascii: ",") {
                    index += 1
                } else if bytes[index] == UInt8(ascii: "}") {
                    index += 1
                    return .object(members)
                } else {
                    throw Self.failure("an object that does not close")
                }
            }
        }

        private mutating func array(depth: Int) throws -> EIP712JSON {
            index += 1
            var elements: [EIP712JSON] = []
            skipWhitespace()
            if index < bytes.count, bytes[index] == UInt8(ascii: "]") {
                index += 1
                return .array([])
            }
            while true {
                skipWhitespace()
                elements.append(try value(depth: depth + 1))
                skipWhitespace()
                guard index < bytes.count else { throw Self.failure("ends early") }
                if bytes[index] == UInt8(ascii: ",") {
                    index += 1
                } else if bytes[index] == UInt8(ascii: "]") {
                    index += 1
                    return .array(elements)
                } else {
                    throw Self.failure("an array that does not close")
                }
            }
        }

        private mutating func number() throws -> String {
            let start = index
            if index < bytes.count, bytes[index] == UInt8(ascii: "-") { index += 1 }
            let digitsStart = index
            while index < bytes.count, (UInt8(ascii: "0")...UInt8(ascii: "9")).contains(bytes[index]) { index += 1 }
            guard index > digitsStart else { throw Self.failure("a value that is not JSON") }
            if index - digitsStart > 1, bytes[digitsStart] == UInt8(ascii: "0") { throw Self.failure("a number with a leading zero") }
            if index < bytes.count, bytes[index] == UInt8(ascii: ".") {
                index += 1
                let fraction = index
                while index < bytes.count, (UInt8(ascii: "0")...UInt8(ascii: "9")).contains(bytes[index]) { index += 1 }
                guard index > fraction else { throw Self.failure("a number that ends at its point") }
            }
            if index < bytes.count, bytes[index] == UInt8(ascii: "e") || bytes[index] == UInt8(ascii: "E") {
                index += 1
                if index < bytes.count, bytes[index] == UInt8(ascii: "+") || bytes[index] == UInt8(ascii: "-") { index += 1 }
                let exponent = index
                while index < bytes.count, (UInt8(ascii: "0")...UInt8(ascii: "9")).contains(bytes[index]) { index += 1 }
                guard index > exponent else { throw Self.failure("a number with an empty exponent") }
            }
            // ASCII only, so the text is the bytes as written.
            return String(decoding: bytes[start..<index], as: UTF8.self)
        }

        private mutating func string() throws -> String {
            index += 1
            var scalars = String.UnicodeScalarView()
            var raw: [UInt8] = []
            func flush(_ raw: inout [UInt8], into scalars: inout String.UnicodeScalarView) throws {
                guard !raw.isEmpty else { return }
                var iterator = raw.makeIterator()
                var decoder = UTF8()
                decoding: while true {
                    switch decoder.decode(&iterator) {
                    case .scalarValue(let scalar): scalars.append(scalar)
                    case .emptyInput: break decoding
                    case .error: throw Self.failure("a string that is not UTF-8")
                    }
                }
                raw.removeAll(keepingCapacity: true)
            }
            while true {
                guard index < bytes.count else { throw Self.failure("a string that does not close") }
                let byte = bytes[index]
                index += 1
                switch byte {
                case UInt8(ascii: "\""):
                    try flush(&raw, into: &scalars)
                    return String(scalars)
                case UInt8(ascii: "\\"):
                    try flush(&raw, into: &scalars)
                    guard index < bytes.count else { throw Self.failure("an escape that ends early") }
                    let escape = bytes[index]
                    index += 1
                    switch escape {
                    case UInt8(ascii: "\""): scalars.append("\"")
                    case UInt8(ascii: "\\"): scalars.append("\\")
                    case UInt8(ascii: "/"): scalars.append("/")
                    case UInt8(ascii: "b"): scalars.append("\u{08}")
                    case UInt8(ascii: "f"): scalars.append("\u{0C}")
                    case UInt8(ascii: "n"): scalars.append("\n")
                    case UInt8(ascii: "r"): scalars.append("\r")
                    case UInt8(ascii: "t"): scalars.append("\t")
                    case UInt8(ascii: "u"):
                        var unit = try hex4()
                        if (0xD800...0xDBFF).contains(unit) {
                            guard index + 1 < bytes.count, bytes[index] == UInt8(ascii: "\\"), bytes[index + 1] == UInt8(ascii: "u") else {
                                throw Self.failure("half a surrogate pair")
                            }
                            index += 2
                            let low = try hex4()
                            guard (0xDC00...0xDFFF).contains(low) else { throw Self.failure("half a surrogate pair") }
                            unit = 0x10000 + ((unit - 0xD800) << 10) + (low - 0xDC00)
                        }
                        guard let scalar = Unicode.Scalar(unit) else { throw Self.failure("half a surrogate pair") }
                        scalars.append(scalar)
                    default:
                        throw Self.failure("an unknown escape")
                    }
                case 0x00..<0x20:
                    throw Self.failure("a control character in a string")
                default:
                    raw.append(byte)
                }
            }
        }

        private mutating func hex4() throws -> UInt32 {
            guard index + 4 <= bytes.count else { throw Self.failure("an escape that is not four hex digits") }
            var value: UInt32 = 0
            for byte in bytes[index..<index + 4] {
                guard let digit = EIP712Hex.digit(byte) else { throw Self.failure("an escape that is not four hex digits") }
                value = value << 4 | UInt32(digit)
            }
            index += 4
            return value
        }
    }
}

/// Hex digits, read one by one: no sign, no prefix, no whitespace, nothing a numeric parser would also accept.
enum EIP712Hex {
    static func digit(_ byte: UInt8) -> UInt8? {
        switch byte {
        case UInt8(ascii: "0")...UInt8(ascii: "9"): return byte - UInt8(ascii: "0")
        case UInt8(ascii: "a")...UInt8(ascii: "f"): return byte - UInt8(ascii: "a") + 10
        case UInt8(ascii: "A")...UInt8(ascii: "F"): return byte - UInt8(ascii: "A") + 10
        default: return nil
        }
    }

    /// The bytes an even number of hex digits spell; nil for an odd count or a character that is not a hex digit.
    static func bytes<Digits: Collection>(_ digits: Digits) -> Data? where Digits.Element == UInt8 {
        guard digits.count.isMultiple(of: 2) else { return nil }
        var out = Data(capacity: digits.count / 2)
        var high: UInt8?
        for byte in digits {
            guard let digit = digit(byte) else { return nil }
            if let first = high {
                out.append(first << 4 | digit)
                high = nil
            } else {
                high = digit
            }
        }
        return out
    }
}
