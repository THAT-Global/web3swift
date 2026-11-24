//
//  EIP712DocumentReadingTests.swift
//  localTests
//
//  How `EIP712Document` reads typed data: what both readings refuse, where the phone-key reading and the strict one
//  part ways, numbers kept exact, keys matched scalar for scalar, and the public model a hardware signer builds from.
//

import CryptoSwift
import Foundation
import Testing
@testable import Web3Core

@Suite("EIP-712 document: reading")
struct EIP712DocumentReadingTests {
    typealias Document = EIP712Document

    /// A document whose message is `{"a": value}`, `a` of `type`; `T` is the primary type unless named.
    static func typedData(
        type: String, value: String, primary: String = "T", extraTypes: String = "",
        domainType: String? = #"[{"name": "name", "type": "string"}]"#, domain: String = #"{"name": "N"}"#
    ) -> String {
        let domainTypeMember = domainType.map { #""EIP712Domain": \#($0), "# } ?? ""
        return #"{"types": {\#(domainTypeMember)"T": [{"name": "a", "type": "\#(type)"}]\#(extraTypes)}, "primaryType": "\#(primary)", "domain": \#(domain), "message": {"a": \#(value)}}"#
    }

    static func read(_ json: String, _ reading: Document.Reading) throws -> Document {
        try Document(json: json, reading: reading)
    }

    static func refused(_ json: String, _ reading: Document.Reading) -> Bool {
        (try? Document(json: json, reading: reading)) == nil
    }

    static func holdsAnAbsentStruct(_ value: Document.Value) -> Bool {
        switch value {
        case .absentStructure: return true
        case .structure(_, let fields): return fields.contains(where: holdsAnAbsentStruct)
        case .array(let entries): return entries.contains(where: holdsAnAbsentStruct)
        case .primitive: return false
        }
    }

    // MARK: Refused by both readings

    @Test(arguments: Document.Reading.allCases)
    func aRepeatedKeyIsRefused(_ reading: Document.Reading) {
        let inMessage = #"{"types": {"EIP712Domain": [{"name": "name", "type": "string"}], "T": [{"name": "a", "type": "uint8"}]}, "primaryType": "T", "domain": {"name": "N"}, "message": {"a": 1, "a": 2}}"#
        #expect(throws: EIP712DocumentError.invalidJSON(#"the key "a" twice"#)) { try Self.read(inMessage, reading) }
        let inTypes = #"{"types": {"EIP712Domain": [{"name": "name", "type": "string"}], "T": [{"name": "a", "type": "uint8"}], "T": []}, "primaryType": "T", "domain": {"name": "N"}, "message": {"a": 1}}"#
        #expect(throws: EIP712DocumentError.self) { try Self.read(inTypes, reading) }
        let inDomain = #"{"types": {"EIP712Domain": [{"name": "name", "type": "string"}], "T": []}, "primaryType": "T", "domain": {"name": "Harmless Mail", "name": "THAT Memberships"}, "message": {}}"#
        #expect(throws: EIP712DocumentError.self) { try Self.read(inDomain, reading) }
        // Two spellings of one character are one key twice (Swift compares canonically; JavaScript would keep both).
        let twoSpellings = #"{"types": {"EIP712Domain": [], "T": []}, "primaryType": "T", "domain": {}, "message": {"é": 1, "é": 2}}"#
        #expect(throws: EIP712DocumentError.self) { try Self.read(twoSpellings, reading) }
        // The same field twice in a type.
        #expect(throws: EIP712DocumentError.self) {
            try Self.read(Self.typedData(type: "uint8", value: "1", extraTypes: #", "U": [{"name": "x", "type": "bool"}, {"name": "x", "type": "bool"}]"#), reading)
        }
    }

    @Test(arguments: Document.Reading.allCases)
    func aNumberIsAWholeNumber(_ reading: Document.Reading) {
        // Refused by both: a fraction, a number string that is not decimal or 0x hex, and what is not a number.
        for value in ["1.5", "0.25e1", "1e-1", #""1.5""#, #""1e3""#, #""""#, #""0b1""#, #""-0x1""#, #""+0x1""#, #""1_000""#, #""1 2""#,
                      "true", "null", #""0x""#, "[1]"] {
            #expect(Self.refused(Self.typedData(type: "uint16", value: value), reading), "uint16 \(value)")
        }
        #expect(!Self.refused(Self.typedData(type: "uint16", value: "1"), reading))
        #expect(!Self.refused(Self.typedData(type: "uint16", value: #""007""#), reading))
        // A whole number written with a fraction or an exponent, a number string with space around it or a `+`: read for
        // the phone as the old web3swift and eth-sig-util 9 read them, written in full for the strict reading.
        for value in ["1.0", "1e3", "1E3", "12.0e0", "0.1e1", "-0.0", "1e+3", #"" 12 ""#, #""\t12\n""#, #""\u00a012""#, #""+12""#, #"" 0x0c ""#] {
            #expect(Self.refused(Self.typedData(type: "uint16", value: value), reading) == (reading == .strict), "uint16 \(value)")
        }
        let twelve = try? Self.read(Self.typedData(type: "uint16", value: "12"), .signTypedDataV4)
        for value in ["12.0e0", "1.2e1", "120e-1", #"" 12 ""#, #""+12""#, #""0x000c""#, #""\r\n0xc ""#] {
            #expect((try? Self.read(Self.typedData(type: "uint16", value: value), .signTypedDataV4))?.signingDigest == twelve?.signingDigest, "\(value)")
        }
    }

    @Test(arguments: Document.Reading.allCases)
    func anIntegerOutOfItsTypesRangeIsRefused(_ reading: Document.Reading) {
        let outOfRange: [(String, String)] = [
            ("uint8", "256"), ("uint8", "-1"), ("int8", "128"), ("int8", "-129"), ("int8", #""0xff""#),
            ("uint256", #""115792089237316195423570985008687907853269984665640564039457584007913129639936""#),
            ("int256", #""57896044618658097711785492504343953926634992332820282019728792003956564819968""#),
            ("int256", #""-57896044618658097711785492504343953926634992332820282019728792003956564819969""#),
            ("uint256", #""0x10000000000000000000000000000000000000000000000000000000000000000""#),
        ]
        for (type, value) in outOfRange {
            #expect(Self.refused(Self.typedData(type: type, value: value), reading), "\(type) \(value)")
        }
        let inRange: [(String, String)] = [
            ("uint8", "255"), ("int8", "127"), ("int8", "-128"), ("uint8", #""-0""#),
            ("uint256", #""115792089237316195423570985008687907853269984665640564039457584007913129639935""#),
            ("int256", #""-57896044618658097711785492504343953926634992332820282019728792003956564819968""#),
        ]
        for (type, value) in inRange {
            #expect(!Self.refused(Self.typedData(type: type, value: value), reading), "\(type) \(value)")
        }
    }

    @Test(arguments: Document.Reading.allCases)
    func bytesAreHex(_ reading: Document.Reading) {
        // Refused by both: longer than N, not hex, not text, an address that is not 40 digits.
        let refused: [(String, String)] = [
            ("bytes4", #""0x0102030405""#), ("bytes1", #""0x+1""#), ("bytes1", #""0x-1""#), ("bytes1", #""0x0101""#),
            ("address", #""0x11111111111111111111111111111111111111""#), ("address", #""11111111111111111111111111111111111111111""#),
            ("address", #""0x111111111111111111111111111111111111111""#), ("address", #""0x""#),
            ("bytes32", #""0x\#(String(repeating: "00", count: 33))""#), ("bytes", #""0xzz""#), ("bytes", #"" 0x12""#),
            ("bytes", #""hello""#), ("bytes", "10"), ("bytes", "1"), ("bytes2", "2"), ("bytes2", "-1"), ("address", "10"),
            ("string", "10"), ("string", "null"),
        ]
        for (type, value) in refused {
            #expect(Self.refused(Self.typedData(type: type, value: value), reading), "\(type) \(value)")
        }
        for (type, value) in [("bytes", #""0x""#), ("bytes4", #""0xA9059CBB""#), ("address", #""0x1111111111111111111111111111111111111111""#)] {
            #expect(!Self.refused(Self.typedData(type: type, value: value), reading), "\(type) \(value)")
        }
        // Read for the phone as the old web3swift and eth-sig-util read them: a short bytesN padded on the right, an odd
        // count of digits with a leading zero, a JSON 0 or 1 for a bytesN. The strict reading takes exactly N bytes.
        let phoneOnly: [(String, String, String)] = [
            ("bytes4", #""0x010203""#, #""0x01020300""#), ("bytes32", #""0x""#, #""0x\#(String(repeating: "00", count: 32))""#),
            ("bytes4", #""0x123""#, #""0x01230000""#), ("bytes", #""0x123""#, #""0x0123""#), ("bytes", #""0x5""#, #""0x05""#),
            ("bytes2", "1", #""0x0100""#), ("bytes2", "0", #""0x0000""#), ("bytes2", "1.0", #""0x0100""#), ("bytes2", "-0", #""0x0000""#),
        ]
        for (type, value, twin) in phoneOnly {
            #expect(Self.refused(Self.typedData(type: type, value: value), reading) == (reading == .strict), "\(type) \(value)")
            let read = try? Self.read(Self.typedData(type: type, value: value), .signTypedDataV4)
            let twinRead = try? Self.read(Self.typedData(type: type, value: twin), .signTypedDataV4)
            #expect(read != nil && read?.signingDigest == twinRead?.signingDigest, "\(type) \(value) reads as \(twin)")
        }
        guard reading == .signTypedDataV4,
              case .structure(_, let fields)? = (try? Self.read(Self.typedData(type: "bytes4", value: #""0x12""#), reading))?.message,
              case .primitive(let short)? = fields.first
        else { return }
        #expect(short.bytes == Data([0x12, 0, 0, 0]), "a short bytesN is its N bytes in the model")
    }

    @Test(arguments: Document.Reading.allCases)
    func aTypeIsDefinedAndWrittenTheOneWayEIP712WritesIt(_ reading: Document.Reading) throws {
        // Undefined, by value or only by type (an empty array of it).
        #expect(throws: EIP712DocumentError.self) { try Self.read(Self.typedData(type: "Foo", value: "{}"), reading) }
        #expect(throws: EIP712DocumentError.self) { try Self.read(Self.typedData(type: "Foo[]", value: "[]"), reading) }
        // The primary type undefined.
        #expect(throws: EIP712DocumentError.refused("the primary type Nope is not defined")) {
            try Self.read(Self.typedData(type: "uint8", value: "1", primary: "Nope"), reading)
        }
        // Written another way, a type is not its canonical self.
        for (type, value) in [("uint08", "1"), ("bytes04", #""0x01020304""#), ("uint8[02]", "[1, 2]"), ("byte", #""0x01""#),
                              ("uint7", "1"), ("bytes33", #""0x01""#), ("function", #""0x01""#), ("Uint8", "1"), ("uint8 ", "1"),
                              ("fixed128x18", "1"), ("uint ", "1"), ("Uint", "1")] {
            #expect(Self.refused(Self.typedData(type: type, value: value), reading), "\(type)")
        }
        // `uint` and `int`: eth-sig-util hashes them under their own text, ethers as uint256/int256, and the old
        // web3swift refused them. Readers disagree: refused by both readings.
        for (type, value) in [("uint", "1"), ("int", "-1"), ("uint[]", #"[1, "2"]"#), ("int[2]", "[0, 1]")] {
            #expect(throws: EIP712DocumentError.self, "\(type)") { try Self.read(Self.typedData(type: type, value: value), reading) }
        }
        // A struct of that name is a struct, as it is to eth-sig-util and the old web3swift.
        #expect(throws: Never.self) {
            try Self.read(Self.typedData(type: "uint", value: #"{"n": 1}"#, extraTypes: #", "uint": [{"name": "n", "type": "uint8"}]"#), reading)
        }
        #expect(!Self.refused(Self.typedData(type: "uint8[0]", value: "[]"), reading))
        // The domain as the primary type: eth-sig-util hashes the domain alone; EIP-712 defines no such digest.
        #expect(throws: EIP712DocumentError.refused("the domain as the primary type")) {
            try Self.read(Self.typedData(type: "uint8", value: "1", primary: "EIP712Domain"), reading)
        }
    }

    @Test(arguments: Document.Reading.allCases)
    func valuesHaveTheirTypesShape(_ reading: Document.Reading) {
        #expect(Self.refused(Self.typedData(type: "bool[2]", value: "[true, false, true]"), reading))
        #expect(Self.refused(Self.typedData(type: "bool[]", value: "true"), reading))
        #expect(Self.refused(Self.typedData(type: "uint8", value: "null"), reading))
        #expect(Self.refused(Self.typedData(type: "uint8[]", value: "[1, null]"), reading))
        #expect(Self.refused(Self.typedData(type: "U", value: #""a string""#, extraTypes: #", "U": []"#), reading))
        #expect(Self.refused(Self.typedData(type: "U", value: "[]", extraTypes: #", "U": []"#), reading))
        // A primitive left out.
        #expect(Self.refused(#"{"types": {"EIP712Domain": [], "T": [{"name": "a", "type": "string"}]}, "primaryType": "T", "domain": {}, "message": {}}"#, reading))
        // Thirty-three levels of arrays below the root.
        let deep = Self.typedData(type: "uint8" + String(repeating: "[]", count: 33), value: String(repeating: "[", count: 33) + String(repeating: "]", count: 33))
        #expect(throws: EIP712DocumentError.self) { try Self.read(deep, reading) }
        let shallow = Self.typedData(type: "uint8" + String(repeating: "[]", count: 31), value: String(repeating: "[", count: 31) + String(repeating: "]", count: 31))
        #expect(throws: Never.self) { try Self.read(shallow, reading) }
        // Not an object with types, primaryType, domain and message.
        for json in ["[]", #"{"types": {}, "primaryType": "T", "domain": {}}"#, #"{"types": [], "primaryType": "T", "domain": {}, "message": {}}"#,
                     #"{"types": {"EIP712Domain": [], "T": []}, "primaryType": "T", "domain": [], "message": {}}"#,
                     #"{"types": {"EIP712Domain": [], "T": {}}, "primaryType": "T", "domain": {}, "message": {}}"#,
                     #"{"types": {"EIP712Domain": [], "T": [{"name": "a"}]}, "primaryType": "T", "domain": {}, "message": {"a": 1}}"#,
                     #"{"types": {"EIP712Domain": [], "": []}, "primaryType": "", "domain": {}, "message": {}}"#] {
            #expect(throws: EIP712DocumentError.self, "\(json)") { try Self.read(json, reading) }
        }
    }

    @Test(arguments: Document.Reading.allCases)
    func theJSONIsOneDocumentOfRFC8259(_ reading: Document.Reading) {
        let good = Self.typedData(type: "string", value: #""x""#)
        #expect(throws: Never.self) { try Self.read(good, reading) }
        for json in [good + " x", "\u{FEFF}" + good, Self.typedData(type: "string", value: #""\ud800""#),
                     Self.typedData(type: "string", value: #""\udc00\ud800""#), Self.typedData(type: "string", value: "\"a\u{01}b\""),
                     Self.typedData(type: "string", value: #""\x41""#), Self.typedData(type: "uint8", value: "01"),
                     Self.typedData(type: "uint8", value: "-"), Self.typedData(type: "string", value: "'x'"),
                     String(repeating: "[", count: 66) + String(repeating: "]", count: 66)] {
            #expect(throws: EIP712DocumentError.self, "\(json.prefix(80))") { try Self.read(json, reading) }
        }
        // Bytes that are not UTF-8 inside a string (the value is the document's last "y").
        var bytes = Data(Self.typedData(type: "string", value: #""xy""#).utf8)
        let at = bytes.lastIndex(of: UInt8(ascii: "y"))!
        bytes[at] = 0xC3
        #expect(throws: EIP712DocumentError.invalidJSON("a string that is not UTF-8")) {
            try Document(jsonData: bytes, reading: reading)
        }
        // A string keeps every scalar it is written with: a byte-order mark at the start of a run of raw text (whole, or
        // after an escape) is part of the value (Foundation's UTF-8 decoding drops it).
        for written in ["\"\u{FEFF}abc\"", "\"\\n\u{FEFF}abc\""] {
            let document = try? Self.read(Self.typedData(type: "string", value: written), reading)
            guard case .structure(_, let fields)? = document?.message, case .primitive(let text)? = fields.first else {
                Issue.record("the premise: a string read from \(written)")
                continue
            }
            #expect(text.bytes.suffix(6) == Data([0xEF, 0xBB, 0xBF, 0x61, 0x62, 0x63]), "\(written)")
        }
        // An escaped pair is one scalar; written out it hashes the same, and both are eth-sig-util 4.0.1's digest
        // (independent-references.json, "an escaped surrogate pair").
        let escapedText = Self.typedData(type: "string", value: #""\ud83d\ude01""#)
        #expect(escapedText.contains("\\ud83d\\ude01") && !escapedText.unicodeScalars.contains { $0.value > 0x7F })
        let escaped = try? Self.read(escapedText, reading)
        let written = try? Self.read(Self.typedData(type: "string", value: "\"😁\""), reading)
        #expect(escaped?.signingDigest.toHexString() == "c57f773fb91b695fff328a49a21e4b2c296d8c76187f052b641c1fad0dd930a8")
        #expect(escaped != nil && escaped?.signingDigest == written?.signingDigest)
    }

    // MARK: Where the readings part ways

    @Test func noDomainTypeIsMadeFromTheDomainsFieldsInTheStrictReadingAndRefusedForThePhone() throws {
        let json = Self.typedData(type: "uint8", value: "7", domainType: nil, domain: #"{"chainId": 137, "name": "N"}"#)
        #expect(throws: EIP712DocumentError.refused("no EIP712Domain type")) { try Self.read(json, .signTypedDataV4) }
        let strict = try Self.read(json, .strict)
        #expect(strict.definition(of: "EIP712Domain")?.encodedAlone == "EIP712Domain(string name,uint256 chainId)")
        #expect(strict.types.map(\.name) == ["EIP712Domain", "T"])
    }

    /// Leading zeros at any length take time in proportion to the text (each was once a shift of the whole number).
    @Test(.timeLimit(.minutes(1)))
    func leadingZerosAtAnyLengthAreReadInLinearTime() throws {
        let zeros = String(repeating: "0", count: 300_000)
        let one = try Self.read(Self.typedData(type: "uint256", value: #""1""#), .signTypedDataV4)
        for value in ["0.\(zeros)1e300001", #""0x\#(zeros)1""#, #""\#(zeros)1""#] {
            let started = Date()
            let document = try Self.read(Self.typedData(type: "uint256", value: value), .signTypedDataV4)
            #expect(document.signingDigest == one.signingDigest, "\(value.prefix(12))…")
            #expect(Date().timeIntervalSince(started) < 20, "\(value.prefix(12))… took \(Date().timeIntervalSince(started)) s")
        }
        let zero = try Self.read(Self.typedData(type: "bytes32", value: "0.\(zeros)"), .signTypedDataV4)
        #expect(zero.signingDigest == (try Self.read(Self.typedData(type: "bytes32", value: "0"), .signTypedDataV4)).signingDigest)
    }

    @Test func aBoolIsTrueOrFalseForThePhoneAndAlsoZeroOrOneInTheStrictReading() throws {
        for value in ["1", "0", #""1""#, #""true""#, #""false""#] {
            #expect(Self.refused(Self.typedData(type: "bool", value: value), .signTypedDataV4), "\(value)")
        }
        let one = try Self.read(Self.typedData(type: "bool", value: "1"), .strict)
        let yes = try Self.read(Self.typedData(type: "bool", value: "true"), .signTypedDataV4)
        #expect(one.signingDigest == yes.signingDigest)
        #expect(Self.refused(Self.typedData(type: "bool", value: "2"), .strict))
        #expect(Self.refused(Self.typedData(type: "bool", value: #""true""#), .strict))
    }

    @Test func aJSONNumberNoDoubleHoldsIsRefusedForThePhoneAndReadExactlyInTheStrictReading() throws {
        // For the phone: a whole number a double holds exactly, at any size its type takes.
        for (type, value, text) in [("uint64", "9007199254740991", "9007199254740991"), ("uint64", "9007199254740992", "9007199254740992"),
                                    ("int64", "-9007199254740992", "-9007199254740992"), ("uint256", "1e+21", "1000000000000000000000"),
                                    ("uint256", "1000000000000000000", "1000000000000000000"), ("uint256", "18446744073709551616", "18446744073709551616"),
                                    ("uint256", "1e22", "10000000000000000000000")] {
            let number = try? Self.read(Self.typedData(type: type, value: value), .signTypedDataV4)
            let string = try? Self.read(Self.typedData(type: type, value: "\"\(text)\""), .signTypedDataV4)
            #expect(number != nil && number?.signingDigest == string?.signingDigest, "\(type) \(value)")
        }
        // Not an exact double: JavaScript would round it, so the text and the dapp disagree.
        #expect(throws: EIP712DocumentError.refused("a JSON number JavaScript cannot hold exactly at T.a")) {
            try Self.read(Self.typedData(type: "uint64", value: "9007199254740993"), .signTypedDataV4)
        }
        // JavaScript writes 2^64 as 18446744073709552000, a number no double is: refused, as its text is not its value.
        for value in ["12345678901234567890", "1e23", "18446744073709551617", "18446744073709552000", "1.8446744073709552e19",
                      "1e400", "1e-400", "123456789e-3"] {
            #expect(Self.refused(Self.typedData(type: "uint256", value: value), .signTypedDataV4), "\(value)")
        }
        // An exact double beyond its type is out of range, not rounded.
        #expect(Self.refused(Self.typedData(type: "uint64", value: "18446744073709551616"), .signTypedDataV4))
        #expect(Self.refused(Self.typedData(type: "uint256", value: "1e78"), .signTypedDataV4))
        // Strict: every digit kept, never through a double (2^64 + 1 is not a double).
        let literal = try Self.read(Self.typedData(type: "uint256", value: "18446744073709551617"), .strict)
        let text = try Self.read(Self.typedData(type: "uint256", value: #""18446744073709551617""#), .strict)
        let hex = try Self.read(Self.typedData(type: "uint256", value: #""0x010000000000000001""#), .strict)
        #expect(literal.signingDigest == text.signingDigest && text.signingDigest == hex.signingDigest)
        guard case .structure(_, let fields) = literal.message, case .primitive(let number) = fields.first else {
            Issue.record("the premise: a struct with one primitive")
            return
        }
        #expect(number.bytes == Data([0x01, 0, 0, 0, 0, 0, 0, 0, 0x01]))
    }

    @Test func aCapitalXPrefixIsReadOnlyInTheStrictReading() throws {
        for (type, value) in [("uint256", #""0X1f""#), ("bytes1", #""0XAB""#), ("address", #""0X1111111111111111111111111111111111111111""#)] {
            #expect(Self.refused(Self.typedData(type: type, value: value), .signTypedDataV4), "\(type) \(value)")
            #expect(!Self.refused(Self.typedData(type: type, value: value), .strict), "\(type) \(value)")
        }
    }

    @Test func aStructNameEthSigUtilWouldReadAnotherWayIsRefusedForThePhone() {
        // eth-sig-util finds a field's struct by the leading word characters of its type, looks a type up before it
        // asks whether it is atomic, and looks it up as a JavaScript property.
        for (name, field) in [("My-Type", "My-Type"), ("uint256", "uint256"), ("toString", "toString"), ("__proto__", "__proto__"),
                              ("Caf\u{e9}", "Caf\u{e9}")] {
            let json = Self.typedData(type: "U", value: "{}", extraTypes: #", "U": [{"name": "x", "type": "\#(field)"}], "\#(name)": []"#)
            #expect(Self.refused(json, .signTypedDataV4), "\(name)")
        }
        // An unused struct with such a name is refused all the same: a name is read before it is reached.
        #expect(Self.refused(Self.typedData(type: "uint8", value: "1", extraTypes: #", "My-Type": []"#), .signTypedDataV4))
        #expect(!Self.refused(Self.typedData(type: "uint8", value: "1", extraTypes: #", "My-Type": []"#), .strict))
        #expect(!Self.refused(Self.typedData(type: "uint8", value: "1", extraTypes: #", "_9Leg": []"#), .signTypedDataV4))
    }

    @Test func aDomainWithAStructTypedFieldIsRefusedForThePhone() {
        let json = #"{"types": {"EIP712Domain": [{"name": "who", "type": "P"}], "P": [{"name": "n", "type": "uint8"}], "T": []}, "primaryType": "T", "domain": {"who": {"n": 1}}, "message": {}}"#
        #expect(throws: EIP712DocumentError.refused("the domain's field who has a struct type")) { try Self.read(json, .signTypedDataV4) }
        #expect(throws: Never.self) { try Self.read(json, .strict) }
        // An array of atomic values in the domain is read by both.
        let array = #"{"types": {"EIP712Domain": [{"name": "ids", "type": "uint8[]"}], "T": []}, "primaryType": "T", "domain": {"ids": [1, 2]}, "message": {}}"#
        #expect(throws: Never.self) { try Self.read(array, .signTypedDataV4) }
    }

    @Test func aStructThatIsNullOrLeftOutIs32ZeroBytesForThePhoneAndRefusedInTheStrictReading() throws {
        let types = #""EIP712Domain": [], "P": [{"name": "n", "type": "uint8"}], "T": [{"name": "p", "type": "P"}, {"name": "ps", "type": "P[]"}, {"name": "c", "type": "uint8"}]"#
        let null = #"{"types": {\#(types)}, "primaryType": "T", "domain": {}, "message": {"p": null, "ps": [{"n": 1}, null], "c": 2}}"#
        let leftOut = #"{"types": {\#(types)}, "primaryType": "T", "domain": {}, "message": {"ps": [{"n": 1}, null], "c": 2}}"#
        let phoneNull = try Self.read(null, .signTypedDataV4)
        let phoneLeftOut = try Self.read(leftOut, .signTypedDataV4)
        #expect(phoneNull.signingDigest == phoneLeftOut.signingDigest)
        guard case .structure(_, let fields) = phoneNull.message, fields.count == 3, case .array(let entries) = fields[1] else {
            Issue.record("the premise: T's three fields")
            return
        }
        #expect(fields[0] == .absentStructure(type: "P"))
        #expect(entries.last == .absentStructure(type: "P"))
        #expect(try phoneNull.encoding(of: fields[0]) == Data(count: 32))
        // By hand: typeHash(T) ‖ 0³² ‖ keccak(hashStruct(P{1}) ‖ 0³²) ‖ word(2).
        let p1 = (Data(try phoneNull.typeHash(of: "P")) + Data(count: 31) + Data([1])).sha3(.keccak256)
        let byHand = (try phoneNull.typeHash(of: "T") + Data(count: 32) + (p1 + Data(count: 32)).sha3(.keccak256) + Data(count: 31) + Data([2])).sha3(.keccak256)
        #expect(phoneNull.messageHash == byHand)
        #expect(throws: EIP712DocumentError.self) { try Self.read(null, .strict) }
        #expect(throws: EIP712DocumentError.self) { try Self.read(leftOut, .strict) }
    }

    @Test func aStructLeftOutUnderANameEveryJavaScriptObjectHasIsRefusedForThePhone() {
        // eth-sig-util reads `data[name]`: under these names a value left out is the inherited member, not undefined.
        for name in ["constructor", "toString", "valueOf", "__proto__", "hasOwnProperty"] {
            let json = #"{"types": {"EIP712Domain": [], "P": [], "T": [{"name": "\#(name)", "type": "P"}]}, "primaryType": "T", "domain": {}, "message": {}}"#
            #expect(Self.refused(json, .signTypedDataV4), "\(name)")
            let null = #"{"types": {"EIP712Domain": [], "P": [], "T": [{"name": "\#(name)", "type": "P"}]}, "primaryType": "T", "domain": {}, "message": {"\#(name)": null}}"#
            #expect(!Self.refused(null, .signTypedDataV4), "\(name): null is its own value")
        }
    }

    // MARK: Keys matched scalar for scalar

    @Test func aKeyIsMatchedScalarForScalarAsJavaScriptMatchesIt() throws {
        // The field is "é" as one scalar; the message has it as "e" and a combining accent: another key.
        let primitive = #"{"types": {"EIP712Domain": [], "T": [{"name": "é", "type": "uint8"}]}, "primaryType": "T", "domain": {}, "message": {"é": 1}}"#
        #expect(Self.refused(primitive, .signTypedDataV4))
        #expect(Self.refused(primitive, .strict))
        let structure = #"{"types": {"EIP712Domain": [], "P": [], "T": [{"name": "é", "type": "P"}]}, "primaryType": "T", "domain": {}, "message": {"é": {}}}"#
        let absent = #"{"types": {"EIP712Domain": [], "P": [], "T": [{"name": "é", "type": "P"}]}, "primaryType": "T", "domain": {}, "message": {}}"#
        #expect(try Self.read(structure, .signTypedDataV4).signingDigest == (try Self.read(absent, .signTypedDataV4)).signingDigest)
        let present = #"{"types": {"EIP712Domain": [], "P": [], "T": [{"name": "é", "type": "P"}]}, "primaryType": "T", "domain": {}, "message": {"é": {}}}"#
        #expect(try Self.read(present, .signTypedDataV4).signingDigest != (try Self.read(absent, .signTypedDataV4)).signingDigest)
    }

    // MARK: The model

    @Test func theModelIsWhatAHardwareSignerIsSent() throws {
        let json = #"{"types": {"EIP712Domain": [{"name": "name", "type": "string"}, {"name": "chainId", "type": "uint256"}], "Z": [{"name": "b", "type": "B[2][]"}, {"name": "a", "type": "A"}, {"name": "n", "type": "int8[3]"}], "B": [{"name": "a", "type": "A[]"}, {"name": "x", "type": "bytes"}], "A": [{"name": "v", "type": "bytes4"}]}, "primaryType": "Z", "domain": {"name": "N", "chainId": "0x89"}, "message": {"b": [], "a": {"v": "0x01020304"}, "n": [1, -2, 127]}}"#
        for reading in Document.Reading.allCases {
            let document = try Self.read(json, reading)
            #expect(document.types.map(\.name) == ["A", "B", "EIP712Domain", "Z"])
            #expect(try document.encodeType(of: "Z") == "Z(B[2][] b,A a,int8[3] n)A(bytes4 v)B(A[] a,bytes x)")
            #expect(try document.encodeType(of: "B") == "B(A[] a,bytes x)A(bytes4 v)")
            #expect(document.definition(of: "Z")?.fields.map(\.type) == [
                .array(root: .structure("B"), levels: [2, nil]), .root(.structure("A")), .array(root: .primitive(.int(1)), levels: [3]),
            ])
            #expect(document.domain == .structure(type: "EIP712Domain", fields: [
                .primitive(.init(type: .string, bytes: Data("N".utf8))), .primitive(.init(type: .uint(32), bytes: Data([0x89]))),
            ]))
            #expect(document.message == .structure(type: "Z", fields: [
                .array([]),
                .structure(type: "A", fields: [.primitive(.init(type: .bytes(4), bytes: Data([1, 2, 3, 4])))]),
                .array([.primitive(.init(type: .int(1), bytes: Data([1]))), .primitive(.init(type: .int(1), bytes: Data([0xFE]))),
                        .primitive(.init(type: .int(1), bytes: Data([0x7F])))]),
            ]))
            #expect(throws: EIP712DocumentError.self) { try document.encodeType(of: "Nope") }
        }
    }

    @Test func anAtomicValueBecomesItsWord() {
        func word(_ bytes: [UInt8], _ type: Document.Primitive) -> String {
            Document.PrimitiveValue(type: type, bytes: Data(bytes)).encoded.toHexString()
        }
        let zeros = String(repeating: "00", count: 31), ones = String(repeating: "ff", count: 31)
        #expect(word([0x80], .uint(1)) == zeros + "80")
        // A signed value of its type's full width with the top bit set is negative; shorter, it is not.
        #expect(word([0x80], .int(1)) == ones + "80")
        #expect(word([0x80], .int(2)) == zeros + "80")
        #expect(word([0xFF, 0x80], .int(2)) == String(repeating: "ff", count: 30) + "ff80")
        #expect(word([0xA9, 0x05, 0x9C, 0xBB], .bytes(4)) == "a9059cbb" + String(repeating: "00", count: 28))
        #expect(word([0x01], .bool) == zeros + "01")
        #expect(Document.PrimitiveValue(type: .string, bytes: Data()).encoded == Data().sha3(.keccak256))
        #expect(Document.PrimitiveValue(type: .bytes(nil), bytes: Data([1])).encoded == Data([1]).sha3(.keccak256))
    }

    @Test func aTypeReadsAndWritesBackAsItsText() {
        for text in ["uint8", "int256", "bytes32", "bytes", "string", "bool", "address", "Leg", "Leg[2]", "uint8[2][]", "A[][3][]",
                     "uint08", "uint8[02]", "My-Type", "", "[2]", "x]", "uint8[2]x"] {
            #expect(Document.FieldType(parsing: text).text == text, "\(text)")
        }
        #expect(Document.FieldType(parsing: "uint8[2][]").elementType == .array(root: .primitive(.uint(1)), levels: [2]))
        #expect(Document.FieldType(parsing: "Leg[2]").elementType == .root(.structure("Leg")))
        #expect(Document.FieldType(parsing: "uint08") == .root(.structure("uint08")))
        #expect(Document.Primitive(parsing: "uint256") == .uint(32))
        #expect(Document.Primitive(parsing: "int8") == .int(1))
        #expect(Document.Primitive(parsing: "bytes1") == .bytes(1))
        #expect(Document.Primitive(parsing: "uint0") == nil && Document.Primitive(parsing: "uint264") == nil)
    }

    @Test func aStructValueIsReadWithTheDocumentsTypesAndReading() throws {
        let document = try Self.read(Self.typedData(type: "P", value: #"{"n": 1, "q": null}"#, extraTypes: #", "P": [{"name": "n", "type": "uint8"}, {"name": "q", "type": "P"}]"#), .signTypedDataV4)
        let value = try document.value(ofStruct: "P", json: #"{"n": 2}"#)
        #expect(value == .structure(type: "P", fields: [.primitive(.init(type: .uint(1), bytes: Data([2]))), .absentStructure(type: "P")]))
        #expect(throws: EIP712DocumentError.self) { try document.value(ofStruct: "Nope", json: "{}") }
        #expect(throws: EIP712DocumentError.self) { try document.value(ofStruct: "P", json: #"{"n": 1.5}"#) }
        #expect(throws: EIP712DocumentError.self) { try document.encodeData(of: .array([])) }
    }
}
