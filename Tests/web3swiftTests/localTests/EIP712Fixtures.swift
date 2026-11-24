//
//  EIP712Fixtures.swift
//  localTests
//
//  The typed-data fixtures in `Tests/Fixtures/eip712`, each with the Python checker beside it that re-derives it with
//  nothing from this package (`python3 -I <checker>.py <fixture>.json`):
//  - `typed-data-vectors.json`: 29 vectors of an independent EIP-712 hasher, copied from ledger-core (develop 980773a,
//    `Tests/LedgerCoreTests/Fixtures/ethereum`), with its checker `typed-data-vectors.py`.
//  - `eth-sig-util-v4-vectors.json`: MetaMask eth-sig-util's own V4 test cases (repository, commit and file in its
//    header; each case names its test line and snapshot key), with what the phone-key reading does with each ("v4",
//    "why") and, for a signature case it reads, the digest. `eth-sig-util-v4-vectors.py` re-derives every value, signs
//    with its own secp256k1, and emulates eth-sig-util to show each refusal is of something eth-sig-util signs or throws on.
//  - `independent-references.json`: digests from @metamask/eth-sig-util 4.0.1 and ethers 6.17.0 as installed on this
//    machine (25 Nov 2026), for the 29 vectors and for rows of the phone-key reading (numbers, short and odd bytes,
//    trimmed strings, the `uint` abbreviation), each row's verdict beside them.
//

import CryptoSwift
import Foundation
import Testing
import Web3Core

enum EIP712Fixtures {
    static let directory = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()   // localTests
        .deletingLastPathComponent()   // web3swiftTests
        .deletingLastPathComponent()   // Tests
        .appendingPathComponent("Fixtures/eip712")

    /// One of the 29 vectors: hex without `0x`.
    struct Vector: Decodable, Sendable, CustomTestStringConvertible {
        let name: String
        let typedData: String
        let domainHash: String
        let messageHash: String
        let digest: String

        var testDescription: String { name }
        /// The one vector whose JSON leaves the domain type out.
        var leavesTheDomainTypeOut: Bool { name == "a domain type the JSON leaves out" }
    }

    /// One of eth-sig-util's cases.
    struct MetaMaskCase: Decodable, Sendable, CustomTestStringConvertible {
        struct Expected: Decodable, Sendable {
            let hashStruct: String?
            let eip712Hash: String?
            let signature: String?
            let encodeType: String?
            let throwsMessage: String?

            enum CodingKeys: String, CodingKey {
                case hashStruct, eip712Hash, signature, encodeType
                case throwsMessage = "throws"
            }
        }

        let name: String
        let source: String
        /// `hashStruct`, `eip712Hash`, `signTypedData` or `encodeType`.
        let check: String
        let typedData: String
        let ethSigUtil: Expected
        /// `same` (the phone-key reading gives eth-sig-util's value) or `refused`.
        let v4: String
        let why: String?
        /// The digest of a signature case the phone-key reading reads (the checker's).
        let digest: String?
        let encodeTypeOf: String?

        var testDescription: String { name }
        var isRead: Bool { v4 == "same" }
    }

    /// A digest one implementation gave, or its refusal.
    enum Outcome: Decodable, Sendable, Equatable {
        case digest(String)
        case error(String)

        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let digest = try? container.decode(String.self) {
                self = .digest(digest)
            } else {
                struct Failure: Decodable { let error: String }
                self = .error((try? container.decode(Failure.self))?.error ?? "")
            }
        }

        var digest: String? { if case .digest(let digest) = self { return digest }; return nil }
    }

    struct ReferenceVector: Decodable, Sendable {
        let name: String
        let ethSigUtil401: Outcome
        let ethers617: Outcome
    }

    struct ReferenceRow: Decodable, Sendable, CustomTestStringConvertible {
        let name: String
        let typedData: String
        /// `read`, or `refused: <why>`.
        let phoneKeyReading: String
        let ethSigUtil401: Outcome
        let ethers617: Outcome
        let twin: String?
        let twinEthSigUtil401: Outcome?
        /// eth-sig-util 4.0.1's digest of the twin, else of the row (rows the phone-key reading reads).
        let reference: String?

        var testDescription: String { name }
        var isRead: Bool { phoneKeyReading == "read" }
    }

    private struct VectorFile: Decodable { let vectors: [Vector] }
    private struct ReferenceFile: Decodable { let vectors: [ReferenceVector]; let rows: [ReferenceRow] }
    private struct MetaMaskFile: Decodable {
        struct Source: Decodable { let repository: String; let commit: String; let privateKey: String }
        let source: Source
        let cases: [MetaMaskCase]
    }

    static let vectors: [Vector] = {
        guard let data = try? Data(contentsOf: directory.appendingPathComponent("typed-data-vectors.json")),
              let file = try? JSONDecoder().decode(VectorFile.self, from: data)
        else { return [] }
        return file.vectors
    }()

    private static let metaMaskFile: MetaMaskFile? = {
        guard let data = try? Data(contentsOf: directory.appendingPathComponent("eth-sig-util-v4-vectors.json")) else { return nil }
        return try? JSONDecoder().decode(MetaMaskFile.self, from: data)
    }()

    static let metaMaskCases: [MetaMaskCase] = metaMaskFile?.cases ?? []

    private static let referenceFile: ReferenceFile? = {
        guard let data = try? Data(contentsOf: directory.appendingPathComponent("independent-references.json")) else { return nil }
        return try? JSONDecoder().decode(ReferenceFile.self, from: data)
    }()

    static let referenceVectors: [ReferenceVector] = referenceFile?.vectors ?? []
    static let referenceRows: [ReferenceRow] = referenceFile?.rows ?? []

    /// The struct definitions a document's `types` spells, read by Foundation (field order is the arrays', so exact):
    /// for an encodeType case, which eth-sig-util answers from the types alone.
    static func definitions(ofTypesIn json: String) -> [EIP712Document.StructDefinition] {
        guard let object = try? JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any],
              let types = object["types"] as? [String: [[String: String]]]
        else { return [] }
        return types.map { name, fields in
            EIP712Document.StructDefinition(name: name, fields: fields.map {
                EIP712Document.Field(name: $0["name"] ?? "", type: EIP712Document.FieldType(parsing: $0["type"] ?? ""))
            })
        }
    }
    static let metaMaskCommit: String = metaMaskFile?.source.commit ?? ""

    /// eth-sig-util's test key (its test file, line 26): a published constant, never a wallet's.
    static let metaMaskKey: Data = {
        guard let text = metaMaskFile?.source.privateKey.components(separatedBy: ": ").last else { return Data() }
        return Data(hex: text)
    }()
}
