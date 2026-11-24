//
//  EIP712ParserRoutingTests.swift
//  localTests
//
//  The fork's entry points hash through `EIP712Document`, with no change at a call site: `EIP712Parser.parse(_:)`'s
//  result (`signHash()`, what swap-core's and payments-core's Android providers call), `Web3Signer.signTypedDataV4`
//  (the app's `iOSWalletSigner`, payments-core's `AndroidWalletSigner`) and `Web3Signer.signEIP712`. A document the
//  reading refuses throws before any key is read; the signature's shape is unchanged.
//

import CryptoSwift
import Foundation
import Testing
import Web3Core
@testable import Web3Swift

@Suite("EIP712Parser and Web3Signer hash through EIP712Document")
struct EIP712ParserRoutingTests {
    static let readVectors = EIP712Fixtures.vectors.filter { !$0.leavesTheDomainTypeOut }

    static func vector(_ name: String) throws -> EIP712Fixtures.Vector {
        try #require(EIP712Fixtures.vectors.first { $0.name == name })
    }

    @Test(arguments: readVectors)
    func theParsersHashesAreTheDocuments(_ vector: EIP712Fixtures.Vector) throws {
        let parsed = try EIP712Parser.parse(vector.typedData)
        let document = try #require(parsed.document)
        #expect(document.reading == .signTypedDataV4)
        #expect(try parsed.signHash().toHexString() == vector.digest)
        #expect(try parsed.structHash().toHexString() == vector.messageHash)
        #expect(try parsed.encodeData() == document.encodeData(of: document.message))
        #expect(try parsed.encodeType(parsed.primaryType) == document.encodeType(of: document.primaryType))
        #expect(try parsed.typeHash(parsed.primaryType) == "0x" + document.typeHash(of: document.primaryType).toHexString())
        #expect(try EIP712Parser.parse(Data(vector.typedData.utf8)).signHash().toHexString() == vector.digest)
        // The dictionaries Foundation read, written back and read with the document's types and reading.
        #expect(try parsed.structHash("EIP712Domain", data: parsed.domain).toHexString() == vector.domainHash)
        #expect(try parsed.structHash(parsed.primaryType, data: parsed.message).toHexString() == vector.messageHash)
        #expect(try parsed.encodeData(parsed.primaryType, data: parsed.message) == parsed.encodeData())
        // The types, as the JSON writes them.
        for definition in document.types {
            #expect(parsed.types[definition.name]?.map(\.type) == definition.fields.map(\.type.text))
            #expect(parsed.types[definition.name]?.map(\.name) == definition.fields.map(\.name))
        }
    }

    @Test func aDocumentLeftWithoutItsDomainTypeIsReadOnlyInTheStrictReading() throws {
        let vector = try Self.vector("a domain type the JSON leaves out")
        #expect(throws: Web3Error.self) { try EIP712Parser.parse(vector.typedData) }
        let strict = try EIP712Parser.parse(vector.typedData, reading: .strict)
        #expect(try strict.signHash().toHexString() == vector.digest)
        #expect(strict.types["EIP712Domain"]?.map(\.name) == ["name", "version", "chainId", "verifyingContract"])
        #expect(try EIP712Parser.parse(Data(vector.typedData.utf8), reading: .strict).signHash().toHexString() == vector.digest)
    }

    @Test func aRefusalIsAWeb3InputErrorWithTheReason() {
        let repeated = #"{"types": {"EIP712Domain": [], "T": []}, "primaryType": "T", "domain": {"name": "a", "name": "b"}, "message": {}}"#
        do {
            _ = try EIP712Parser.parse(repeated)
            Issue.record("a repeated key was read")
        } catch Web3Error.inputError(let desc) {
            #expect(desc == #"EIP712Parser. typed data: JSON: the key "name" twice"#)
        } catch {
            Issue.record("not an input error: \(error)")
        }
        #expect(throws: Web3Error.self) { try EIP712Parser.parse(Data([0x7B, 0xC3, 0x7D])) }
    }

    @Test func theEncodeTypeOfANestedStructIsEIP712s() throws {
        let vector = try Self.vector("a struct reached only through another, whose name sorts first")
        let parsed = try EIP712Parser.parse(vector.typedData)
        let expected = "Probe(Middle m)Alpha(bytes4 v)Middle(Alpha a,uint8 n)"
        #expect(try parsed.encodeType("Probe") == expected)
        #expect(try parsed.typeHash("Probe") == "0x" + Data(expected.utf8).sha3(.keccak256).toHexString())
        #expect(try Self.madeFromDictionaries(parsed).encodeType("Probe") == expected)
        let twoWays = try EIP712Parser.parse(try Self.vector("a struct reached by two ways").typedData)
        #expect(try twoWays.encodeType("Probe") == "Probe(Middle m,Alpha a)Alpha(bytes4 v)Middle(Alpha[] a)")
        #expect(throws: Web3Error.self) { try parsed.encodeType("Nope") }
    }

    /// The deprecated initialiser's value: no JSON text, so its hashes throw rather than guess.
    @available(*, deprecated)
    static func madeFromDictionaries(_ parsed: EIP712TypedData) throws -> EIP712TypedData {
        try EIP712TypedData(types: parsed.types, primaryType: parsed.primaryType, domain: parsed.domain, message: parsed.message)
    }

    @Test func aValueMadeFromDictionariesIsNeverHashed() throws {
        let parsed = try EIP712Parser.parse(try Self.vector("the EIP-712 Mail example").typedData)
        let made = try Self.madeFromDictionaries(parsed)
        #expect(made.document == nil)
        #expect(throws: Web3Error.self) { try made.signHash() }
        #expect(throws: Web3Error.self) { try made.structHash() }
        #expect(throws: Web3Error.self) { try made.encodeData() }
        #expect(throws: Web3Error.self) { try made.encodeData("Person", data: parsed.domain) }
        #expect(throws: Web3Error.self) { try made.structHash("EIP712Domain", data: parsed.domain) }
        #expect(throws: Web3Error.self) { try Web3Signer.signEIP712(made, keystore: SpyKeystore(), account: SpyKeystore.account) }
        #expect(try made.encodeType("Mail") == "Mail(Person from,Person to,string contents)Person(string name,address wallet)")
    }

    @Test func aDictionaryJSONCannotCarryIsRefusedNotWrittenOut() throws {
        let parsed = try EIP712Parser.parse(try Self.vector("the EIP-712 Mail example").typedData)
        let person: [String: AnyObject] = ["name": "Cow" as NSString, "wallet": Data(count: 20) as NSData]
        #expect(throws: Web3Error.self) { try parsed.encodeData("Person", data: person) }
        let rounded: [String: AnyObject] = ["name": "Cow" as NSString, "wallet": "0xCD2a3d9F938E13CD947Ec05AbC7FE734Df8DD826" as NSString]
        #expect(try parsed.structHash("Person", data: rounded).toHexString() == "fc71e5fa27ff56c350aa531bc129ebdf613b772b6604664f5d8dbe21b85eb0c8")
    }

    /// A dictionary is written back to JSON and read for the phone: a number Foundation holds rounded (past 38 digits) is
    /// no exact double, so it is refused, never hashed; a strictly read document refuses the dictionary path outright.
    @Test func aDictionaryIsReadForThePhoneSoARoundedNumberIsRefused() throws {
        let json = #"{"types":{"EIP712Domain":[],"T":[{"name":"a","type":"uint256"}]},"primaryType":"T","domain":{},"message":{"a":"1"}}"#
        let parsed = try EIP712Parser.parse(json)
        let rounded: [String: AnyObject] = ["a": NSDecimalNumber(string: "340282366920938463463374607431768211457")]
        #expect(throws: Web3Error.self) { try parsed.encodeData("T", data: rounded) }
        let exact: [String: AnyObject] = ["a": NSNumber(value: UInt64(1) << 60)]
        let twin = try EIP712Document(json: #"{"types":{"EIP712Domain":[],"T":[{"name":"a","type":"uint256"}]},"primaryType":"T","domain":{},"message":{"a":"1152921504606846976"}}"#, reading: .strict)
        #expect(try parsed.structHash("T", data: exact) == twin.messageHash)
        let strict = try EIP712Parser.parse(json, reading: .strict)
        #expect(throws: Web3Error.self) { try strict.encodeData("T", data: ["a": "1" as NSString]) }
        #expect(throws: Web3Error.self) { try strict.structHash("T", data: ["a": "1" as NSString]) }
        #expect(try strict.signHash() == parsed.signHash())
    }

    @Test func aTypePropertyReadsEveryArray() {
        let cases: [(String, Bool, String)] = [
            ("bool[2]", true, "bool"), ("uint8[2][]", true, "uint8[2]"), ("Leg[2]", true, "Leg"), ("Leg[]", true, "Leg"),
            ("string", false, "string"), ("Person", false, "Person"), ("uint8[02]", false, "uint8[02]"),
        ]
        for (type, isArray, coreType) in cases {
            let property = EIP712TypeProperty(name: "x", type: type)
            #expect(property.isArray == isArray && property.coreType == coreType, "\(type)")
        }
        #expect(EIP712TypeProperty(name: " x ", type: " bool[2] ").type == "bool[2]")
    }

    // MARK: Signing

    /// A synthetic key, never a wallet's: Keccak-256 of a fixed phrase.
    static let key = Data("web3swift 5.1.0 EIP-712 routing test key".utf8).sha3(.keccak256)

    @Test(arguments: ["a fixed array of booleans", "a fixed array of structs", "the EIP-712 Mail example", "an ERC-2612 permit"])
    func signTypedDataV4SignsTheVectorsDigestWithTheSameShape(_ name: String) throws {
        let vector = try Self.vector(name)
        let keystore = try #require(PlainKeystore(privateKey: Self.key))
        let address = try #require(keystore.addresses?.first)
        let hex = try Web3Signer.signTypedDataV4(vector.typedData, keystore: keystore, account: address, password: "")
        #expect(hex.hasPrefix("0x") && hex.count == 132)
        let signature = try #require(Data.fromHex(hex))
        #expect(signature.count == 65 && [27, 28].contains(signature[64]))
        let digest = Data(hex: vector.digest)
        #expect(Utilities.hashECRecover(hash: digest, signature: signature) == address)
        // The bytes are a signature of the digest itself: no prefix, low s, v normalised to 27 or 28.
        var direct = try #require(SECP256K1.signForRecovery(hash: digest, privateKey: Self.key, useExtraEntropy: false).serializedSignature)
        Web3Signer.normalizeRecoveryByte(in: &direct)
        #expect(direct == signature)
        // signEIP712 (ERC2612.signPermit's tail) gives the same bytes before its recovery byte is normalised.
        var viaSignEIP712 = try Web3Signer.signEIP712(try EIP712Parser.parse(vector.typedData), keystore: keystore, account: address, password: "")
        Web3Signer.normalizeRecoveryByte(in: &viaSignEIP712)
        #expect(viaSignEIP712 == signature)
    }

    @Test func aRefusedDocumentNeverReachesTheKey() throws {
        let keystore = SpyKeystore()
        let noDomainType = try Self.vector("a domain type the JSON leaves out").typedData
        #expect(throws: Web3Error.self) {
            try Web3Signer.signTypedDataV4(noDomainType, keystore: keystore, account: SpyKeystore.account, password: "")
        }
        #expect(keystore.reads.value == 0)
        _ = try Web3Signer.signTypedDataV4(try Self.vector("the EIP-712 Mail example").typedData, keystore: keystore, account: SpyKeystore.account, password: "")
        #expect(keystore.reads.value == 1)
    }
}

/// A keystore that counts its key reads.
final class SpyKeystore: AbstractKeystore, @unchecked Sendable {
    final class Count: @unchecked Sendable {
        private let lock = NSLock()
        private var count = 0
        var value: Int { lock.lock(); defer { lock.unlock() }; return count }
        func add() { lock.lock(); count += 1; lock.unlock() }
    }

    static let key = Data("web3swift 5.1.0 EIP-712 spy key".utf8).sha3(.keccak256)
    static let account = Utilities.publicToAddress(Utilities.privateToPublic(key)!)!
    let reads = Count()
    var addresses: [EthereumAddress]? { [Self.account] }
    var isHDKeystore: Bool { false }

    func UNSAFE_getPrivateKeyData(password: String, account: EthereumAddress) throws -> Data {
        reads.add()
        return Self.key
    }
}
