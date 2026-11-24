//
//  EIP712DocumentVectorTests.swift
//  localTests
//
//  `EIP712Document` pinned to values this package did not compute (EIP712Fixtures):
//  - the 29 vectors of an independent hasher, in both readings: the strict reading gives every vector's three hashes;
//    the phone-key reading gives them for the 28 with a domain type and refuses the one that leaves it out;
//  - MetaMask eth-sig-util's own V4 cases: every case the phone-key reading reads gives eth-sig-util's hashStruct,
//    eip712Hash, encodeType (from the types alone, as eth-sig-util answers it) or signature (through
//    `Web3Signer.signTypedDataV4`, byte for byte, with eth-sig-util's test key); every case it refuses throws, through
//    the document and through `EIP712Parser` and the signer.
//

import CryptoSwift
import Foundation
import Testing
import Web3Core
import Web3Swift

@Suite("EIP-712 document: the 29 vectors")
struct EIP712DocumentVectorTests {
    @Test func everyVectorIsRead() {
        #expect(EIP712Fixtures.vectors.count == 29)
        #expect(EIP712Fixtures.vectors.first?.digest == "be609aee343fb3c4b28e1df9e632fca64fcfaede20f02e86244efddf30957bd2")
        #expect(EIP712Fixtures.vectors.filter(\.leavesTheDomainTypeOut).count == 1)
    }

    @Test(arguments: EIP712Fixtures.vectors)
    func theStrictReadingGivesEveryVectorsHashes(_ vector: EIP712Fixtures.Vector) throws {
        let document = try EIP712Document(json: vector.typedData, reading: .strict)
        #expect(document.domainHash.toHexString() == vector.domainHash)
        #expect(document.messageHash.toHexString() == vector.messageHash)
        #expect(document.signingDigest.toHexString() == vector.digest)
        #expect(document.reading == .strict)
    }

    @Test(arguments: EIP712Fixtures.vectors)
    func thePhoneKeyReadingGivesTheVectorsHashesOrRefusesNoDomainType(_ vector: EIP712Fixtures.Vector) throws {
        guard !vector.leavesTheDomainTypeOut else {
            #expect(throws: EIP712DocumentError.refused("no EIP712Domain type")) {
                try EIP712Document(json: vector.typedData, reading: .signTypedDataV4)
            }
            return
        }
        let document = try EIP712Document(json: vector.typedData, reading: .signTypedDataV4)
        #expect(document.domainHash.toHexString() == vector.domainHash)
        #expect(document.messageHash.toHexString() == vector.messageHash)
        #expect(document.signingDigest.toHexString() == vector.digest)
    }

    @Test(arguments: EIP712Fixtures.vectors)
    func theDocumentsOwnEncodersAgreeWithItsHashes(_ vector: EIP712Fixtures.Vector) throws {
        let document = try EIP712Document(json: vector.typedData, reading: .strict)
        #expect(try document.hashStruct(of: document.domain) == document.domainHash)
        #expect(try document.hashStruct(of: document.message) == document.messageHash)
        #expect(try document.encoding(of: document.message) == document.messageHash)
        let encoded = try document.encodeData(of: document.message)
        #expect(encoded.prefix(32) == (try document.typeHash(of: document.primaryType)))
        #expect(encoded.sha3(.keccak256) == document.messageHash)
    }
}

@Suite("EIP-712 document: eth-sig-util's own V4 cases")
struct EIP712DocumentMetaMaskTests {
    static let key = EIP712Fixtures.metaMaskKey

    @Test func everyCaseIsRead() {
        #expect(EIP712Fixtures.metaMaskCommit == "9e0cdc2be912415e0cc9159b52d26db76ffe99b0")
        #expect(EIP712Fixtures.metaMaskCases.count == 248)
        #expect(EIP712Fixtures.metaMaskCases.filter(\.isRead).count == 113)
        #expect(EIP712Fixtures.metaMaskCases.filter { $0.v4 == "refused" }.count == 135)
        #expect(Self.key.count == 32)
    }

    @Test(arguments: EIP712Fixtures.metaMaskCases.filter { $0.check == "encodeType" })
    func anEncodeTypeCaseIsAnsweredFromTheTypesAlone(_ testCase: EIP712Fixtures.MetaMaskCase) throws {
        let definitions = EIP712Fixtures.definitions(ofTypesIn: testCase.typedData)
        #expect(!definitions.isEmpty)
        if testCase.isRead {
            #expect(try EIP712Document.encodeType(of: testCase.encodeTypeOf ?? "", in: definitions) == testCase.ethSigUtil.encodeType)
        } else {
            #expect(throws: EIP712DocumentError.self) { try EIP712Document.encodeType(of: testCase.encodeTypeOf ?? "", in: definitions) }
        }
    }

    @Test(arguments: EIP712Fixtures.metaMaskCases.filter { $0.isRead && $0.check != "encodeType" })
    func aCaseThePhoneKeyReadingReadsGivesEthSigUtilsValue(_ testCase: EIP712Fixtures.MetaMaskCase) throws {
        let document = try EIP712Document(json: testCase.typedData, reading: .signTypedDataV4)
        let expected = testCase.ethSigUtil
        switch testCase.check {
        case "hashStruct":
            #expect(document.messageHash.toHexString() == expected.hashStruct)
        case "eip712Hash":
            #expect(document.signingDigest.toHexString() == expected.eip712Hash)
        case "signTypedData":
            #expect(document.signingDigest.toHexString() == testCase.digest)
            let keystore = try #require(PlainKeystore(privateKey: Self.key))
            let account = try #require(keystore.addresses?.first)
            let signature = try Web3Signer.signTypedDataV4(testCase.typedData, keystore: keystore, account: account, password: "")
            #expect(signature == expected.signature, "eth-sig-util's signature, byte for byte")
        default:
            Issue.record("a check this suite does not know: \(testCase.check)")
        }
        #expect(expected.throwsMessage == nil, "eth-sig-util throws on a case the phone-key reading reads")
    }

    @Test(arguments: EIP712Fixtures.metaMaskCases.filter { !$0.isRead && $0.check != "encodeType" })
    func aCaseThePhoneKeyReadingRefusesThrowsEverywhere(_ testCase: EIP712Fixtures.MetaMaskCase) throws {
        #expect(throws: EIP712DocumentError.self) {
            try EIP712Document(json: testCase.typedData, reading: .signTypedDataV4)
        }
        #expect(throws: Web3Error.self) { try EIP712Parser.parse(testCase.typedData) }
        let keystore = try #require(PlainKeystore(privateKey: Self.key))
        let account = try #require(keystore.addresses?.first)
        #expect(throws: Web3Error.self) {
            try Web3Signer.signTypedDataV4(testCase.typedData, keystore: keystore, account: account, password: "")
        }
    }

    /// The two readings never give two digests for one document: where both read it they agree, value for value.
    @Test(arguments: EIP712Fixtures.metaMaskCases.filter { $0.isRead && $0.check != "encodeType" })
    func theStrictReadingAgreesWhereItReads(_ testCase: EIP712Fixtures.MetaMaskCase) throws {
        let phone = try EIP712Document(json: testCase.typedData, reading: .signTypedDataV4)
        guard let strict = try? EIP712Document(json: testCase.typedData, reading: .strict) else { return }
        #expect(strict.signingDigest == phone.signingDigest)
        #expect(strict.types == phone.types && strict.domain == phone.domain && strict.message == phone.message)
    }
}
