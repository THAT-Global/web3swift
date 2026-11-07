import XCTest
import BigInt
import CryptoSwift
@testable import Web3Core
@testable import Web3Swift

/// The secp256k1 signing vectors (that-ios BITCOIN-PLAN.md B0): every primitive an EVM signature in THAT reaches, pinned
/// byte for byte in `Tests/Fixtures/secp256k1-signing-vectors.tsv`.
///
/// The fixture was written by this suite on swift-secp256k1 0.10.0 (libsecp256k1 of Dec 2022), before the library moved.
/// A swift-secp256k1 resolve that changes any key, address, signature, raw transaction or recovery fails here line by
/// line. ECDSA here is RFC 6979 deterministic, so the same inputs sign to the same bytes in any correct implementation.
///
/// Re-capture only on purpose: `TEST_RUNNER_SIGNING_VECTORS_OUT=<path> xcodebuild test …` writes the computed set, and a
/// diff against the fixture shows what moved. A moved line is a signing change, never fixture noise.
final class SigningVectorsTests: XCTestCase {

    static let fixtureURL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()   // localTests
        .deletingLastPathComponent()   // web3swiftTests
        .deletingLastPathComponent()   // Tests
        .appendingPathComponent("Fixtures/secp256k1-signing-vectors.tsv")

    func testEveryVectorMatchesTheFixture() throws {
        let lines = try SigningVectors.all()
        if let out = ProcessInfo.processInfo.environment["SIGNING_VECTORS_OUT"], !out.isEmpty {
            try (lines.joined(separator: "\n") + "\n").write(toFile: out, atomically: true, encoding: .utf8)
            print("signing vectors written: \(lines.count) lines")
        }
        let fixture = try String(contentsOf: Self.fixtureURL, encoding: .utf8)
        let expected = fixture.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
            .filter { !$0.hasPrefix("#") }
        XCTAssertGreaterThanOrEqual(expected.count, 871, "the fixture lost its vectors")
        XCTAssertEqual(lines.count, expected.count, "vector count moved")
        var mismatches = 0
        for (index, (got, want)) in zip(lines, expected).enumerated() where got != want {
            mismatches += 1
            if mismatches <= 10 { XCTFail("vector \(index + 1) moved\n got: \(got)\nwant: \(want)") }
        }
        XCTAssertEqual(mismatches, 0, "\(mismatches) vectors moved")
    }

    /// Published vectors, independent of the fixture: EIP-155's example, EIP-712's `Mail`, BIP32 test vector 1.
    func testPublishedVectors() throws {
        // EIP-155 (https://eips.ethereum.org/EIPS/eip-155): nonce 9, 20 gwei, 21000 gas, 1 ether to 0x3535…, chain 1.
        var tx = CodableTransaction(
            type: .legacy, to: EthereumAddress("0x3535353535353535353535353535353535353535")!,
            nonce: 9, chainID: 1, value: BigUInt(10).power(18), gasLimit: 21000, gasPrice: BigUInt(20_000_000_000)
        )
        try tx.sign(privateKey: Data(repeating: 0x46, count: 32), useExtraEntropy: false)
        XCTAssertEqual(
            tx.encode(for: .transaction)?.toHexString(),
            "f86c098504a817c800825208943535353535353535353535353535353535353535880de0b6b3a76400008025a028ef61340bd939bc2195fe537567866003e1a15d3c71ff63e1590620aa636276a067cbe9d8997f761aecb703304b3800ccf555c9f3dc64214b297fb1966a3b6d83"
        )

        // EIP-712's example (`Mail`, signed by keccak256("cow")).
        let mail = try EIP712Parser.parse(SigningVectors.mailTypedData)
        XCTAssertEqual(try mail.signHash().toHexString(), "be609aee343fb3c4b28e1df9e632fca64fcfaede20f02e86244efddf30957bd2")
        let cow = Data("cow".utf8).sha3(.keccak256)
        let keystore = try XCTUnwrap(PlainKeystore(privateKey: cow))
        let account = try XCTUnwrap(keystore.addresses?.first)
        XCTAssertEqual(account.address, "0xCD2a3d9F938E13CD947Ec05AbC7FE734Df8DD826")
        let signature = try Web3Signer.signTypedDataV4(
            SigningVectors.mailTypedData, keystore: keystore, account: account, password: ""
        )
        XCTAssertEqual(
            signature,
            "0x4355c47d63924e8a72e509b65029052eb6c299d53a04e167c5775fd466751c9d"
                + "07299936d304c153f6443dfa05f40ff007d72911b6f72307f996231605b91562" + "1c"
        )

        // BIP32 test vector 1 (https://github.com/bitcoin/bips/blob/master/bip-0032.mediawiki#test-vector-1).
        let master = try XCTUnwrap(HDNode(seed: Data.fromHex("000102030405060708090a0b0c0d0e0f")!))
        XCTAssertEqual(
            master.serializeToString(serializePublic: false),
            "xprv9s21ZrQH143K3QTDL4LXw2F7HEK3wJUD2nW2nRk4stbPy6cq3jPPqjiChkVvvNKmPGJxWUtg6LnF5kejMRNNU3TGtRBeJgk33yuGBxrMPHi"
        )
        XCTAssertEqual(
            master.serializeToString(),
            "xpub661MyMwAqRbcFtXgS5sYJABqqG9YLmC4Q1Rdap9gSE8NqtwybGhePY2gZ29ESFjqJoCu1Rupje8YtGqsefD265TMg7usUDFdp6W1EGMcet8"
        )
        let m0h = try XCTUnwrap(master.derive(path: "m/0'"))
        XCTAssertEqual(
            m0h.serializeToString(),
            "xpub68Gmy5EdvgibQVfPdqkBBCHxA5htiqg55crXYuXoQRKfDBFA1WEjWgP6LHhwBZeNK1VTsfTFUHCdrfp1bgwQ9xv5ski8PX9rL2dZXvgGDnw"
        )
        let m0h1 = try XCTUnwrap(master.derive(path: "m/0'/1"))
        XCTAssertEqual(
            m0h1.serializeToString(),
            "xpub6ASuArnXKPbfEwhqN6e3mwBcDTgzisQN1wXN9BJcM47sSikHjJf3UFHKkNAWbWMiGj7Wf5uMash7SyYq527Hqck2AxYysAA7xmALppuCkwQ"
        )
    }

    /// The randomised path (`useExtraEntropy: true`) cannot be pinned; it must still verify against the signer.
    func testExtraEntropySignaturesRecoverTheSigner() throws {
        for i in 0..<16 {
            let key = SigningVectors.key(i)
            let hash = SigningVectors.hash(i)
            let (signature, _) = SECP256K1.signForRecovery(hash: hash, privateKey: key, useExtraEntropy: true)
            let serialized = try XCTUnwrap(signature)
            XCTAssertEqual(serialized.count, 65)
            XCTAssertEqual(
                SECP256K1.recoverPublicKey(hash: hash, signature: serialized),
                SECP256K1.privateToPublic(privateKey: key)
            )
            let deterministic = SECP256K1.signForRecovery(hash: hash, privateKey: key).serializedSignature
            XCTAssertNotEqual(serialized, deterministic, "extra entropy produced the RFC 6979 signature")
        }
    }
}

/// The vector set. Each line is `group<TAB>id<TAB>fields…`, hex lowercase without `0x`, `-` for nil.
enum SigningVectors {

    static let curveOrder = BigUInt("FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEBAAEDCE6AF48A03BBFD25E8CD0364141", radix: 16)!

    static func key(_ i: Int) -> Data { Data("THAT B0 secp256k1 vector key \(i)".utf8).sha3(.keccak256) }
    static func hash(_ i: Int) -> Data { Data("THAT B0 secp256k1 vector message \(i)".utf8).sha3(.keccak256) }

    static func be32(_ value: BigUInt) -> Data {
        let raw = value.serialize()
        return Data(repeating: 0, count: max(0, 32 - raw.count)) + raw.suffix(32)
    }

    static func hex(_ data: Data?) -> String { data.map { $0.toHexString() } ?? "-" }

    /// Keys with a meaning of their own, then 48 derived ones.
    static var signingKeys: [(String, Data)] {
        var keys: [(String, Data)] = [
            ("one", be32(1)),
            ("two", be32(2)),
            ("three", be32(3)),
            ("n-1", be32(curveOrder - 1)),
            ("n-2", be32(curveOrder - 2)),
            ("half-n", be32(curveOrder / 2)),
            ("eip155", Data(repeating: 0x46, count: 32)),
            ("cow", Data("cow".utf8).sha3(.keccak256)),
            ("hardhat0", Data.fromHex("ac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80")!),
            ("leading-zero", Data([0x00, 0x00]) + Data("leading".utf8).sha3(.keccak256).prefix(30)),
        ]
        for i in 0..<48 { keys.append(("k\(i)", key(i))) }
        return keys
    }

    static var messageHashes: [(String, Data)] {
        var hashes: [(String, Data)] = [
            ("zero", Data(repeating: 0, count: 32)),
            ("ff", Data(repeating: 0xff, count: 32)),
            ("n", be32(curveOrder)),
            ("n-1", be32(curveOrder - 1)),
            ("one", be32(1)),
            ("keccak-empty", Data().sha3(.keccak256)),
        ]
        for i in 0..<10 { hashes.append(("h\(i)", hash(i))) }
        return hashes
    }

    static func all() throws -> [String] {
        var lines: [String] = []
        lines += keyLines()
        lines += signatureLines()
        lines += malformedSignatureLines()
        lines += combineLines()
        lines += try personalLines()
        lines += try typedDataLines()
        lines += try transactionLines()
        lines += try eip7702Lines()
        lines += try userOperationAndClientSigLines()
        lines += hdLines()
        return lines
    }

    // MARK: - Keys

    static func keyLines() -> [String] {
        var lines = signingKeys.map { label, key -> String in
            let uncompressed = SECP256K1.privateToPublic(privateKey: key)
            let compressed = SECP256K1.privateToPublic(privateKey: key, compressed: true)
            let address = uncompressed.flatMap { Utilities.publicToAddress($0) }?.address ?? "-"
            return ["key", label, hex(key), "\(SECP256K1.verifyPrivateKey(privateKey: key))",
                    hex(uncompressed), hex(compressed), address].joined(separator: "\t")
        }
        let invalid: [(String, Data)] = [
            ("zero", Data(repeating: 0, count: 32)),
            ("n", be32(curveOrder)),
            ("n+1", be32(curveOrder + 1)),
            ("max", Data(repeating: 0xff, count: 32)),
            ("31-bytes", Data(repeating: 0x11, count: 31)),
            ("33-bytes", Data(repeating: 0x11, count: 33)),
        ]
        for (label, key) in invalid {
            let signature = SECP256K1.signForRecovery(hash: hash(0), privateKey: key)
            lines.append(["badkey", label, "\(SECP256K1.verifyPrivateKey(privateKey: key))",
                          hex(SECP256K1.privateToPublic(privateKey: key)),
                          hex(signature.serializedSignature), hex(signature.rawSignature)].joined(separator: "\t"))
        }
        return lines
    }

    // MARK: - Raw hash signatures and recovery

    static func withV(_ signature: Data, _ v: UInt8) -> Data { signature.prefix(64) + Data([v]) }

    static func signatureLines() -> [String] {
        var lines: [String] = []
        for (keyLabel, key) in signingKeys.prefix(26) {
            for (hashLabel, hash) in messageHashes {
                let (serialized, raw) = SECP256K1.signForRecovery(hash: hash, privateKey: key)
                var fields = ["sig", "\(keyLabel)/\(hashLabel)", hex(serialized), hex(raw)]
                if let serialized {
                    let recId = serialized[64] - 27
                    fields.append(hex(SECP256K1.recoverPublicKey(hash: hash, signature: serialized)))
                    fields.append(hex(SECP256K1.recoverPublicKey(hash: hash, signature: serialized, compressed: true)))
                    // A `v` of 4…26 or 39+ is not exercised: `parseSignature` hands it to libsecp256k1 as a recovery id,
                    // whose argument check aborts the process (both 0.10.0 and 0.24.0 do this).
                    for v in [recId, recId + 31, recId + 35, (recId ^ 1) + 27, 2, 3] {
                        fields.append(hex(SECP256K1.recoverPublicKey(hash: hash, signature: withV(serialized, v))))
                    }
                    fields.append(hex(SECP256K1.recoverPublicKey(hash: hash.dropLast() + Data([hash.last! ^ 1]), signature: serialized)))
                    fields.append(Utilities.personalECRecover(hash, signature: serialized)?.address ?? "-")
                }
                lines.append(fields.joined(separator: "\t"))
            }
        }
        return lines
    }

    static func malformedSignatureLines() -> [String] {
        var lines: [String] = []
        let hash = hash(7)
        let good = SECP256K1.signForRecovery(hash: hash, privateKey: key(7)).serializedSignature!
        let r = BigUInt(good.prefix(32))
        let s = BigUInt(good[32..<64])
        let v = good[64]
        let cases: [(String, Data)] = [
            ("high-s", be32(r) + be32(curveOrder - s) + Data([v ^ 1])),
            ("high-s-same-v", be32(r) + be32(curveOrder - s) + Data([v])),
            ("r-zero", be32(0) + be32(s) + Data([v])),
            ("s-zero", be32(r) + be32(0) + Data([v])),
            ("r-n", be32(curveOrder) + be32(s) + Data([v])),
            ("s-n", be32(r) + be32(curveOrder) + Data([v])),
            ("r-max", Data(repeating: 0xff, count: 32) + be32(s) + Data([v])),
            ("all-zero", Data(repeating: 0, count: 65)),
            ("short", good.prefix(64)),
            ("long", good + Data([0])),
        ]
        for (label, signature) in cases {
            lines.append(["badsig", label, hex(signature),
                          hex(SECP256K1.recoverPublicKey(hash: hash, signature: signature)),
                          hex(SECP256K1.parseSignature(signature: signature).map { Data(SECP256K1.toByteArray($0)) })]
                .joined(separator: "\t"))
        }
        return lines
    }

    // MARK: - Public-key combination (BIP32 public derivation)

    static func combineLines() -> [String] {
        var lines: [String] = []
        let keys = signingKeys.map(\.1)
        for i in 0..<12 {
            let a = SECP256K1.privateToPublic(privateKey: keys[i])!
            let b = SECP256K1.privateToPublic(privateKey: keys[i + 1], compressed: true)!
            let c = SECP256K1.privateToPublic(privateKey: keys[i + 2])!
            lines.append(["combine", "\(i)/pair",
                          hex(SECP256K1.combineSerializedPublicKeys(keys: [a, b])),
                          hex(SECP256K1.combineSerializedPublicKeys(keys: [a, b], outputCompressed: true))]
                .joined(separator: "\t"))
            lines.append(["combine", "\(i)/triple",
                          hex(SECP256K1.combineSerializedPublicKeys(keys: [a, b, c], outputCompressed: true))]
                .joined(separator: "\t"))
        }
        let one = SECP256K1.privateToPublic(privateKey: be32(1), compressed: true)!
        let minusOne = SECP256K1.privateToPublic(privateKey: be32(curveOrder - 1), compressed: true)!
        let offCurve = Data([0x02]) + Data(repeating: 0x00, count: 31) + Data([0x05])
        let badPrefix = Data([0x05]) + one.dropFirst()
        lines.append(["combine", "P+(-P)", hex(SECP256K1.combineSerializedPublicKeys(keys: [one, minusOne]))].joined(separator: "\t"))
        lines.append(["combine", "single", hex(SECP256K1.combineSerializedPublicKeys(keys: [one]))].joined(separator: "\t"))
        lines.append(["combine", "empty", hex(SECP256K1.combineSerializedPublicKeys(keys: []))].joined(separator: "\t"))
        lines.append(["combine", "off-curve", hex(SECP256K1.combineSerializedPublicKeys(keys: [one, offCurve]))].joined(separator: "\t"))
        lines.append(["combine", "bad-prefix", hex(SECP256K1.combineSerializedPublicKeys(keys: [badPrefix]))].joined(separator: "\t"))
        return lines
    }

    // MARK: - personal_sign (EIP-191)

    static func personalLines() throws -> [String] {
        let messages: [(String, Data)] = [
            ("empty", Data()),
            ("hello", Data("hello".utf8)),
            ("greeting", Data("Hello, THAT!".utf8)),
            ("unicode", Data("héllo wörld 🌏 — ✓".utf8)),
            ("hex-text", Data("0xdeadbeef".utf8)),
            ("hash-bytes", hash(3)),
            ("binary", Data((0..<256).map { UInt8($0) })),
            ("long", Data(String(repeating: "THAT ", count: 400).utf8)),
            ("siwe", Data("""
                example.com wants you to sign in with your Ethereum account:
                0x0000000000000000000000000000000000000001

                Sign in to THAT.

                URI: https://example.com
                Version: 1
                Chain ID: 137
                Nonce: 32891756
                Issued At: 2026-11-08T00:00:00Z
                """.utf8)),
        ]
        var lines: [String] = []
        for (keyLabel, key) in signingKeys.prefix(12) {
            let keystore = PlainKeystore(privateKey: key)!
            let account = keystore.addresses![0]
            for (label, message) in messages {
                let signature = try Web3Signer.signPersonalMessage(message, keystore: keystore, account: account, password: "")
                lines.append(["personal", "\(keyLabel)/\(label)", hex(Utilities.hashPersonalMessage(message)), hex(signature),
                              signature.flatMap { Utilities.personalECRecover(message, signature: $0) }?.address ?? "-"]
                    .joined(separator: "\t"))
            }
        }
        return lines
    }

    // MARK: - EIP-712

    static let mailTypedData = """
        {"types":{"EIP712Domain":[{"name":"name","type":"string"},{"name":"version","type":"string"},\
        {"name":"chainId","type":"uint256"},{"name":"verifyingContract","type":"address"}],\
        "Person":[{"name":"name","type":"string"},{"name":"wallet","type":"address"}],\
        "Mail":[{"name":"from","type":"Person"},{"name":"to","type":"Person"},{"name":"contents","type":"string"}]},\
        "primaryType":"Mail","domain":{"name":"Ether Mail","version":"1","chainId":1,\
        "verifyingContract":"0xCcCCccccCCCCcCCCCCCcCcCccCcCCCcCcccccccC"},\
        "message":{"from":{"name":"Cow","wallet":"0xCD2a3d9F938E13CD947Ec05AbC7FE734Df8DD826"},\
        "to":{"name":"Bob","wallet":"0xbBbBBBBbbBBBbbbBbbBbbbbBBbBbbbbBbBbbBBbB"},"contents":"Hello, Bob!"}}
        """

    static let nestedTypedData = """
        {"types":{"EIP712Domain":[{"name":"name","type":"string"},{"name":"version","type":"string"},\
        {"name":"chainId","type":"uint256"},{"name":"verifyingContract","type":"address"},{"name":"salt","type":"bytes32"}],\
        "Order":[{"name":"maker","type":"address"},{"name":"amounts","type":"uint256[]"},{"name":"tags","type":"string[]"},\
        {"name":"legs","type":"Leg[]"},{"name":"flag","type":"bool"},{"name":"memo","type":"bytes"},{"name":"delta","type":"int256"}],\
        "Leg":[{"name":"token","type":"address"},{"name":"amount","type":"uint256"}]},\
        "primaryType":"Order","domain":{"name":"THAT Vectors","version":"2","chainId":80002,\
        "verifyingContract":"0x1111111111111111111111111111111111111111",\
        "salt":"0x0000000000000000000000000000000000000000000000000000000000000abc"},\
        "message":{"maker":"0x2222222222222222222222222222222222222222","amounts":["1","1000000000000000000",\
        "115792089237316195423570985008687907853269984665640564039457584007913129639935"],"tags":["a","","ünï"],\
        "legs":[{"token":"0x3333333333333333333333333333333333333333","amount":"42"},\
        {"token":"0x4444444444444444444444444444444444444444","amount":"0"}],"flag":true,"memo":"0xdeadbeef","delta":"-7"}}
        """

    static func typedDataLines() throws -> [String] {
        let permit = try ERC2612.buildPermitTypedDataJSON(
            name: "THAT", version: "1", chainId: BigUInt(137),
            verifyingContract: "0xd2E57e7019a8faea8b3E4a3738Ee5B269975008A",
            owner: "0x5555555555555555555555555555555555555555", spender: "0x6666666666666666666666666666666666666666",
            value: "1000000000000000000", nonce: "3", deadline: "1893456000"
        )
        let payloads: [(String, String)] = [
            ("mail", mailTypedData), ("nested", nestedTypedData), ("permit", permit),
            ("web3swift-fixture", EIP712TestData.testTypedDataPayload),
        ]
        var lines: [String] = []
        for (label, json) in payloads {
            let typed = try EIP712Parser.parse(json)
            let digest = try typed.signHash()
            for (keyLabel, key) in signingKeys.prefix(8) {
                let keystore = PlainKeystore(privateKey: key)!
                let account = keystore.addresses![0]
                let signature = try Web3Signer.signTypedDataV4(json, keystore: keystore, account: account, password: "")
                lines.append(["eip712", "\(label)/\(keyLabel)", hex(digest), signature].joined(separator: "\t"))
            }
        }
        return lines
    }

    // MARK: - Transactions (legacy, EIP-155, EIP-2930, EIP-1559)

    static func accessList(_ json: String) throws -> [AccessListEntry] {
        try JSONDecoder().decode([AccessListEntry].self, from: Data(json.utf8))
    }

    static func transactionLines() throws -> [String] {
        let list = try accessList("""
            [{"address":"0x1111111111111111111111111111111111111111","storageKeys":[]},\
            {"address":"0x2222222222222222222222222222222222222222","storageKeys":\
            ["0x0000000000000000000000000000000000000000000000000000000000000001",\
            "0x8a35acfbc15ff81a39ae7d344fd709f28e8600b4aa8c65c6b64bfe7fe36bd19b"]}]
            """)
        let transfer = Data.fromHex(
            "a9059cbb0000000000000000000000003535353535353535353535353535353535353535"
                + "0000000000000000000000000000000000000000000000000de0b6b3a7640000")!
        let large = Data((0..<4096).map { UInt8(truncatingIfNeeded: $0 &* 7) })
        let to = [EthereumAddress("0x3535353535353535353535353535353535353535")!,
                  EthereumAddress("0xc2132D05D31c914a87C6611C10748AEb04B58e8F")!]
        let values: [BigUInt] = [0, 1, BigUInt(10).power(18), BigUInt(2).power(255)]
        let nonces: [BigUInt] = [0, 1, 127, 128, BigUInt(1) << 32, (BigUInt(1) << 64) - 1]
        let datas = [Data(), transfer, large]

        struct Shape { let label: String; let type: TransactionType; let chain: BigUInt; let access: Bool }
        let shapes = [
            Shape(label: "legacy-nochain", type: .legacy, chain: 0, access: false),
            Shape(label: "legacy-1", type: .legacy, chain: 1, access: false),
            Shape(label: "legacy-137", type: .legacy, chain: 137, access: false),
            Shape(label: "legacy-80002", type: .legacy, chain: 80002, access: false),
            Shape(label: "2930-137", type: .eip2930, chain: 137, access: false),
            Shape(label: "2930-137-list", type: .eip2930, chain: 137, access: true),
            Shape(label: "1559-1", type: .eip1559, chain: 1, access: false),
            Shape(label: "1559-137", type: .eip1559, chain: 137, access: false),
            Shape(label: "1559-80002", type: .eip1559, chain: 80002, access: false),
            Shape(label: "1559-8453-list", type: .eip1559, chain: 8453, access: true),
        ]
        var lines: [String] = []
        for (s, shape) in shapes.enumerated() {
            for variant in 0..<6 {
                let keyLabel = signingKeys[(s + variant) % signingKeys.count]
                var tx = CodableTransaction(
                    type: shape.type, to: to[variant % 2], nonce: nonces[variant], chainID: shape.chain,
                    value: values[variant % 4], data: datas[variant % 3], gasLimit: BigUInt(21000 + 7919 * variant),
                    maxFeePerGas: shape.type == .eip1559 ? BigUInt(250_000_000_000 + variant) : nil,
                    maxPriorityFeePerGas: shape.type == .eip1559 ? BigUInt(30_000_000_000 + variant) : nil,
                    gasPrice: shape.type == .eip1559 ? nil : BigUInt(20_000_000_000 + variant),
                    accessList: shape.access ? list : (shape.type == .legacy ? nil : [])
                )
                let unsigned = tx.encode(for: .signature)
                try tx.sign(privateKey: keyLabel.1, useExtraEntropy: false)
                lines.append(["tx", "\(shape.label)/\(variant)/\(keyLabel.0)",
                              hex(unsigned.map { $0.sha3(.keccak256) }), hex(tx.encode(for: .transaction)), hex(tx.hash),
                              "\(tx.v)", tx.sender?.address ?? "-"]
                    .joined(separator: "\t"))
            }
        }
        return lines
    }

    // MARK: - EIP-7702 authorizations and SetCode transactions

    static func eip7702Lines() throws -> [String] {
        var lines: [String] = []
        let delegate = EthereumAddress("0x69007702764179f14F51cdce752f4f775d74E139")!
        for (i, (keyLabel, key)) in signingKeys.prefix(10).enumerated() {
            for chain in [BigUInt(137), BigUInt(80002)] {
                var auth = EIP7702Authorization(chainID: chain, address: delegate, nonce: BigUInt(i))
                try auth.sign(privateKey: key)
                lines.append(["auth7702", "\(keyLabel)/\(chain)", hex(auth.signingHash()), "\(auth.yParity)",
                              hex(be32(auth.r)), hex(be32(auth.s)), auth.recoverSigner()?.address ?? "-"]
                    .joined(separator: "\t"))
            }
            var auth = EIP7702Authorization(chainID: 137, address: delegate, nonce: BigUInt(i + 1))
            try auth.sign(privateKey: key)
            var tx = EIP7702SetCodeTransaction(
                chainID: 137, nonce: BigUInt(i), maxPriorityFeePerGas: 30_000_000_000, maxFeePerGas: 250_000_000_000,
                gasLimit: 120_000, to: SECP256K1.privateToPublic(privateKey: key).flatMap { Utilities.publicToAddress($0) }!,
                value: 0, data: Data(), authorizationList: [auth]
            )
            try tx.sign(privateKey: key)
            lines.append(["settx7702", keyLabel, hex(tx.signingHash()), hex(tx.encode(for: .transaction)),
                          "\(tx.yParity)"].joined(separator: "\t"))
        }
        return lines
    }

    // MARK: - ERC-4337 user operations and the rewards client signature

    static func userOperationAndClientSigLines() throws -> [String] {
        var lines: [String] = []
        let entryPoint = EthereumAddress("0x0000000071727De22E5E9d8BAf0edAc6f37da032")!
        for (keyLabel, key) in signingKeys.prefix(8) {
            let sender = SECP256K1.privateToPublic(privateKey: key).flatMap { Utilities.publicToAddress($0) }!
            var op = PackedUserOperation(
                sender: sender, nonce: 5, callData: Data.fromHex("b61d27f6")!, verificationGasLimit: 150_000,
                callGasLimit: 90_000, preVerificationGas: 50_000, maxPriorityFeePerGas: 30_000_000_000,
                maxFeePerGas: 250_000_000_000
            )
            try op.sign(entryPoint: entryPoint, chainID: 137, privateKey: key, useExtraEntropy: false)
            lines.append(["userop", keyLabel, hex(op.hash(entryPoint: entryPoint, chainID: 137)), hex(op.signature)]
                .joined(separator: "\t"))
            let clientSig = try RewardsManager.signClientSig(
                privateKey: key, user: sender, recipient: EthereumAddress("0x2222222222222222222222222222222222222222")!,
                amount: BigUInt(10).power(18), chainId: 137,
                contract: EthereumAddress("0xc55897D0285D855B2C56F202145d6FC101B1f7dC")!
            )
            lines.append(["clientsig", keyLabel, hex(clientSig)].joined(separator: "\t"))
        }
        return lines
    }

    // MARK: - BIP39 → BIP32 → addresses (the three derive templates wallet-core uses)

    static func hdLines() -> [String] {
        var lines: [String] = []
        let phrases: [(String, String, String)] = [
            ("abandon", "abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about", ""),
            ("abandon-trezor", "abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about", "TREZOR"),
            ("legal", "legal winner thank year wave sausage worth useful legal winner thank yellow", ""),
            ("zoo24", Array(repeating: "zoo", count: 23).joined(separator: " ") + " vote", ""),
        ]
        for (label, phrase, passphrase) in phrases {
            guard let seed = BIP39.seedFromMmemonics(phrase, password: passphrase, language: .english),
                  let root = HDNode(seed: seed) else {
                lines.append(["hd", label, "-"].joined(separator: "\t"))
                continue
            }
            var paths: [String] = []
            paths += (0..<10).map { "m/44'/60'/0'/0/\($0)" }   // bip44
            paths += (0..<5).map { "m/44'/60'/\($0)'/0/0" }     // ledgerLive
            paths += (0..<5).map { "m/44'/60'/0'/\($0)" }       // legacy
            for path in paths {
                let node = root.derive(path: path)
                lines.append(["hd", "\(label)/\(path)", hex(node?.privateKey), hex(node?.publicKey),
                              node.flatMap { Utilities.publicToAddress(SECP256K1.privateToPublic(privateKey: $0.privateKey!)!) }?.address ?? "-",
                              node?.serializeToString() ?? "-"]
                    .joined(separator: "\t"))
            }
            // Public-only derivation from the account node's xpub: the non-hardened children through point addition.
            if let account = root.derive(path: "m/44'/60'/0'/0"),
               let xpub = account.serialize(), let publicNode = HDNode(xpub) {
                for i in UInt32(0)..<5 {
                    let child = publicNode.derive(index: i, derivePrivateKey: false)
                    lines.append(["hdpub", "\(label)/\(i)", hex(child?.publicKey), child?.serializeToString() ?? "-"]
                        .joined(separator: "\t"))
                }
            }
        }
        let vector1 = HDNode(seed: Data.fromHex("000102030405060708090a0b0c0d0e0f")!)!
        for path in ["m", "m/0'", "m/0'/1", "m/0'/1/2'", "m/0'/1/2'/2", "m/0'/1/2'/2/1000000000"] {
            let node = path == "m" ? vector1 : vector1.derive(path: path)
            lines.append(["bip32", "v1/\(path)", node?.serializeToString(serializePublic: false) ?? "-",
                          node?.serializeToString() ?? "-"].joined(separator: "\t"))
        }
        return lines
    }
}
