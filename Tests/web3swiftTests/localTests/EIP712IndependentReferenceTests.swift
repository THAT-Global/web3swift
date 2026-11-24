//
//  EIP712IndependentReferenceTests.swift
//  localTests
//
//  `EIP712Document` against digests that eth-sig-util 4.0.1 and ethers 6.17.0 computed on 25 Nov 2026
//  (`Tests/Fixtures/eip712/independent-references.json`):
//  - the 29 vectors, whose own digests came from this programme's Python hasher: eth-sig-util gives 28 of them (not the
//    document that leaves its domain type out, for which it hashes an empty domain type) and ethers all 29 (it builds
//    the missing domain type from the domain's keys, as the strict reading does);
//  - rows of the phone-key reading: every row it reads gives eth-sig-util's digest, of the row or of its twin (the
//    same value written as every reader takes it), and every row it refuses throws.
//

import Foundation
import Testing
import Web3Core

@Suite("EIP-712 document: digests of other implementations")
struct EIP712IndependentReferenceTests {
    @Test func everyReferenceIsRead() {
        #expect(EIP712Fixtures.referenceVectors.count == 29)
        #expect(EIP712Fixtures.referenceRows.count == 40)
        #expect(EIP712Fixtures.referenceRows.filter(\.isRead).count == 28)
    }

    @Test func eachVectorIsEthSigUtilsAndEthersDigest() throws {
        for (vector, reference) in zip(EIP712Fixtures.vectors, EIP712Fixtures.referenceVectors) {
            #expect(vector.name == reference.name)
            let strict = try EIP712Document(json: vector.typedData, reading: .strict)
            #expect(strict.signingDigest.toHexString() == vector.digest, "\(vector.name)")
            #expect(reference.ethers617.digest == vector.digest, "ethers: \(vector.name)")
            if vector.leavesTheDomainTypeOut {
                // eth-sig-util hashes an `EIP712Domain` with no fields; the phone-key reading refuses the document.
                #expect(reference.ethSigUtil401.digest != vector.digest)
                #expect(throws: EIP712DocumentError.self) { try EIP712Document(json: vector.typedData, reading: .signTypedDataV4) }
            } else {
                #expect(reference.ethSigUtil401.digest == vector.digest, "eth-sig-util: \(vector.name)")
                #expect(try EIP712Document(json: vector.typedData, reading: .signTypedDataV4).signingDigest == strict.signingDigest)
            }
        }
    }

    @Test(arguments: EIP712Fixtures.referenceRows)
    func aPhoneKeyRowIsEthSigUtilsDigestOrRefused(_ row: EIP712Fixtures.ReferenceRow) throws {
        guard row.isRead else {
            #expect(throws: EIP712DocumentError.self) { try EIP712Document(json: row.typedData, reading: .signTypedDataV4) }
            return
        }
        let reference = try #require(row.reference)
        let document = try EIP712Document(json: row.typedData, reading: .signTypedDataV4)
        #expect(document.signingDigest.toHexString() == reference)
        if let twin = row.twin {
            #expect(row.twinEthSigUtil401?.digest == reference)
            #expect(try EIP712Document(json: twin, reading: .signTypedDataV4).signingDigest == document.signingDigest)
        } else {
            #expect(row.ethSigUtil401.digest == reference)
        }
    }
}
