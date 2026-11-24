//
//  EIP712DifferentialTests.swift
//  localTests
//
//  The new hashing against the old (EIP712LegacyHasher, the fork's EIP712Parser at develop d1cef1b5). Over every
//  fixture, an input the old code hashed correctly hashes the same now, and the inputs it hashed wrongly are named.
//  Over THAT's own payloads the digest, and so the signature, is the same byte for byte:
//  - payments-core's ERC-2612 permit (`ERC2612PermitRequest.typedDataJSON()` is the fork's
//    `ERC2612.buildPermitTypedDataJSON`), at the four cast-authored goldens of that-names `permit_typed_data.tsv`;
//  - the username claim's permit (names-core `UsernameClaimSession`: THAT token, spender the Polygon controller);
//  - a 1inch Fusion+ order as swap-core hands it to the signer (swift-oneinch-fusion `Web3ProviderConnector`: the
//    limit-order SDK's `buildOrderTypedData` encoded by `Codec.encoder`; chainId a JSON number);
//  - rewards-core's membership Move and Check-In (as THATTests `WalletConnectTHATTypedDataCells` writes them);
//  - the WalletConnect Mail of THATTests `iOSWalletSignerTests.mailJSON` and swap-core `RunWalletOrderSigningCells`;
//  - dapp-core's real-world previews `DappPreviewInputs.permit2TypedData` (Uniswap Permit2) and `orderTypedData`.
//  Each reference digest not from a golden is the checker's (`eth-sig-util-v4-vectors.py`, pure Python).
//

import BigInt
import CryptoSwift
import Foundation
import Testing
import Web3Core
@testable import Web3Swift

@Suite("EIP-712: the old hasher against the new")
struct EIP712DifferentialTests {
    static let metaMaskKey = EIP712Fixtures.metaMaskKey

    static func oldDigest(_ json: String) -> Data? {
        try? LegacyEIP712Parser.parse(json).signHash()
    }

    static func signature(of digest: Data, key: Data) -> String? {
        guard var signature = SECP256K1.signForRecovery(hash: digest, privateKey: key, useExtraEntropy: false).serializedSignature else { return nil }
        Web3Signer.normalizeRecoveryByte(in: &signature)
        return "0x" + signature.toHexString()
    }

    /// The vectors the old code hashed wrongly, or threw on.
    static let oldWrongVectors: Set<String> = [
        "arrays, nested structs, negative and large numbers",   // bool[2] encoded in place
        "a fixed array of booleans",                            // bool[2] encoded in place
        "an array of arrays",                                   // uint8[2][] read as a uint8[2] array
        "a fixed array of structs",                             // Leg[2] throws
        "a struct reached only through another, whose name sorts first",
        "a struct reached by two ways",
        "a domain type the JSON leaves out",                    // throws; the phone-key reading refuses it too
    ]

    @Test func overTheVectorsTheOldHasherIsMatchedWhereverItWasRight() throws {
        var wrong = Set<String>()
        for vector in EIP712Fixtures.vectors {
            guard let old = Self.oldDigest(vector.typedData), old.toHexString() == vector.digest else {
                wrong.insert(vector.name)
                continue
            }
            #expect(try EIP712Parser.parse(vector.typedData).signHash() == old, "\(vector.name)")
            #expect(try EIP712Document(json: vector.typedData, reading: .strict).signingDigest == old, "\(vector.name)")
        }
        #expect(wrong == Self.oldWrongVectors)
        // Where the old code was wrong, the new one is the vector's.
        for vector in EIP712Fixtures.vectors where wrong.contains(vector.name) && !vector.leavesTheDomainTypeOut {
            #expect(try EIP712Parser.parse(vector.typedData).signHash().toHexString() == vector.digest, "\(vector.name)")
        }
    }

    /// What the old code gave for one of eth-sig-util's cases, and whether it was eth-sig-util's.
    static func oldOutcome(_ testCase: EIP712Fixtures.MetaMaskCase) -> (gave: Bool, right: Bool) {
        let expected = testCase.ethSigUtil
        guard let old = try? LegacyEIP712Parser.parse(testCase.typedData) else { return (false, false) }
        switch testCase.check {
        case "hashStruct":
            guard let hash = try? old.structHash() else { return (false, false) }
            return (true, hash.toHexString() == expected.hashStruct)
        case "eip712Hash":
            guard let hash = try? old.signHash() else { return (false, false) }
            return (true, hash.toHexString() == expected.eip712Hash)
        case "signTypedData":
            guard let hash = try? old.signHash() else { return (false, false) }
            return (true, signature(of: hash, key: metaMaskKey) == expected.signature)
        case "encodeType":
            guard let text = try? old.encodeType(testCase.encodeTypeOf ?? "") else { return (false, false) }
            return (true, text == expected.encodeType)
        default:
            return (false, false)
        }
    }

    /// eth-sig-util's cases where the old code gave eth-sig-util's value and the phone-key reading refuses. Each is an
    /// `int8` given a value outside -128…127, which the old code and eth-sig-util both encode as a 256-bit word: a
    /// signature no contract can check, since an `int8` cannot hold the value it was signed over. None is a payload THAT
    /// builds.
    static let oldRightNowRefused: Set<String> = [
        "hashStruct int8 255 (number)", "hashStruct int8 -255 (number)", "hashStruct int8[] of every example",
        "signTypedData int8 255 (number)", "signTypedData int8 -255 (number)", "signTypedData int8[] of every example",
    ]

    /// eth-sig-util's cases where the old code gave a value other than eth-sig-util's and the phone-key reading reads
    /// the case (with eth-sig-util's value: EIP712DocumentMetaMaskTests): an odd count of hex digits, which the old code
    /// read as a last byte of one digit (`0x101` as 10 01) and eth-sig-util with a leading zero (01 01).
    static let oldWrongNowEthSigUtils: Set<String> = [
        "hashStruct bytes 0x101 (string)", "hashStruct bytes 0x1fffffffffffff1 (string)",
        "hashStruct bytes32 0x101 (string)", "hashStruct bytes32 0x1fffffffffffff1 (string)",
        "signTypedData bytes 0x101 (string)", "signTypedData bytes 0x1fffffffffffff1 (string)",
        "signTypedData bytes32 0x101 (string)", "signTypedData bytes32 0x1fffffffffffff1 (string)",
    ]

    @Test func overEthSigUtilsCasesTheOldHasherIsMatchedWhereverItWasRight() throws {
        var rightNowRefused = Set<String>()
        var wrongNowRead = Set<String>()
        var right = 0
        for testCase in EIP712Fixtures.metaMaskCases {
            let outcome = Self.oldOutcome(testCase)
            if outcome.gave, !outcome.right, testCase.isRead { wrongNowRead.insert(testCase.name) }
            guard outcome.right else { continue }
            right += 1
            guard testCase.isRead else {
                rightNowRefused.insert(testCase.name)
                continue
            }
            let old = try LegacyEIP712Parser.parse(testCase.typedData)
            if testCase.check == "encodeType" {
                let definitions = EIP712Fixtures.definitions(ofTypesIn: testCase.typedData)
                #expect(try EIP712Document.encodeType(of: testCase.encodeTypeOf ?? "", in: definitions) == old.encodeType(testCase.encodeTypeOf ?? ""))
                continue
            }
            let document = try EIP712Document(json: testCase.typedData, reading: .signTypedDataV4)
            switch testCase.check {
            case "hashStruct": #expect(document.messageHash == (try old.structHash()), "\(testCase.name)")
            default: #expect(document.signingDigest == (try old.signHash()), "\(testCase.name)")
            }
        }
        #expect(rightNowRefused == Self.oldRightNowRefused)
        #expect(wrongNowRead == Self.oldWrongNowEthSigUtils)
        #expect(right > 0)
    }

    // MARK: THAT's payloads

    struct Payload: Sendable, CustomTestStringConvertible {
        let name: String
        let json: String
        let digest: String
        var testDescription: String { name }
    }

    static let token = "0xd2E57e7019a8faea8b3E4a3738Ee5B269975008A"
    static let owner = "0x3f76222f93ad5D8347431E4023a4614de9A88baC"

    static func permit(spender: String, owner: String = owner, value: String, nonce: String, deadline: String) -> String {
        (try? ERC2612.buildPermitTypedDataJSON(
            name: "THAT", version: "1", chainId: 137, verifyingContract: token,
            owner: owner, spender: spender, value: value, nonce: nonce, deadline: deadline)) ?? ""
    }

    static let payloads: [Payload] = [
        // that-names goldens/permit_typed_data.tsv permit_1 … permit_4 (cast), as payments-core's tests take them.
        Payload(name: "ERC-2612 permit_1", json: permit(spender: "0x00000000000000000000000000000000000C0BA1", value: "1000000000000000000000", nonce: "0", deadline: "1750000000"),
                digest: "e67871bbf99798e9b5c48e2e71dbc12197123db0fac984f464029a69da4131d3"),
        Payload(name: "ERC-2612 permit_2", json: permit(spender: "0x00000000000000000000000000000000000C0BA1", value: "100000000000000000000", nonce: "1", deadline: "1789040000"),
                digest: "1e70d4b214d3c39169df26afa2353540545f8db18e67c31b8bcce863bc6a055c"),
        Payload(name: "ERC-2612 permit_3", json: permit(spender: "0x00000000000000000000000000000000000C0BA1", owner: "0x000000000000000000000000000000000000dEaD", value: "10000000000000000000000000", nonce: "7", deadline: "4102444800"),
                digest: "7ac826be5b9c4a322aea5182bf57fdb1ddbed42b3284e1a7ab50463df0338830"),
        Payload(name: "ERC-2612 permit_4", json: permit(spender: "0xc55897D0285D855B2C56F202145d6FC101B1f7dC", value: "1000000000000000000000", nonce: "0", deadline: "1750000000"),
                digest: "c56c0da874602284e50710d2ef65df51b5679b0d9f6211a33fda067a22e784a7"),
        // names-core THATNamesDeployment.polygon's controller as the spender, a 5 THAT price.
        Payload(name: "the username claim's permit", json: permit(spender: "0xD434fe798BA3EC91B593056D020025D1530c2c2B", value: "5000000000000000000", nonce: "3", deadline: "1795000000"),
                digest: "f4243d79dd325f092250700aff925a6e2bd99e21e0bd678d1028789825c09dd6"),
        Payload(name: "a 1inch Fusion+ order",
                json: #"{"types":{"EIP712Domain":[{"name":"name","type":"string"},{"name":"version","type":"string"},{"name":"chainId","type":"uint256"},{"name":"verifyingContract","type":"address"}],"Order":[{"name":"salt","type":"uint256"},{"name":"maker","type":"address"},{"name":"receiver","type":"address"},{"name":"makerAsset","type":"address"},{"name":"takerAsset","type":"address"},{"name":"makingAmount","type":"uint256"},{"name":"takingAmount","type":"uint256"},{"name":"makerTraits","type":"uint256"}]},"domain":{"name":"1inch Aggregation Router","version":"6","chainId":137,"verifyingContract":"0x111111125421ca6dc452d289314280a0f8842a65"},"message":{"salt":"9445680545936410419330284706951757224702878670220689583677680607556412140293","maker":"0x3f76222f93ad5d8347431e4023a4614de9a88bac","receiver":"0x0000000000000000000000000000000000000000","makerAsset":"0x3c499c542cef5e3811e1192ce70d8cc03d5c3359","takerAsset":"0x7ceb23fd6bc0add59e62ac25578270cff1b9f619","makingAmount":"25000000","takingAmount":"7351126459043371","makerTraits":"62419173104490761595518734106557662061518414611782227068396304425790442831872"},"primaryType":"Order"}"#,
                digest: "1e4c592d0daa748723d546771500a6fd1a21f057dbfaee387be5863e2557527d"),
        Payload(name: "a membership Move",
                json: #"{"domain":{"name":"THAT Memberships","version":"1","chainId":137,"verifyingContract":"0x169c4b5e8dCE68Ba3f36B3916d916595A9B2C1Bd"},"message":{"membershipId":"4","successor":"0x2222222222222222222222222222222222222222","deadline":"1794097800"},"primaryType":"Move","types":{"EIP712Domain":[{"name":"name","type":"string"},{"name":"version","type":"string"},{"name":"chainId","type":"uint256"},{"name":"verifyingContract","type":"address"}],"Move":[{"name":"membershipId","type":"uint256"},{"name":"successor","type":"address"},{"name":"deadline","type":"uint256"}]}}"#,
                digest: "32a43f6c8cbf4f65be4b65b500833b50b4b7155f263e6c3f0167b24cb3579a75"),
        Payload(name: "a membership Check-In",
                json: #"{"domain":{"chainId":"137","name":"THAT Check-In","verifyingContract":"0x169c4b5e8dCE68Ba3f36B3916d916595A9B2C1Bd","version":"1"},"message":{"holder":"0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266","issuedAt":"1794096000","merchantId":"319"},"primaryType":"CheckIn","types":{"CheckIn":[{"name":"holder","type":"address"},{"name":"merchantId","type":"uint256"},{"name":"issuedAt","type":"uint256"}],"EIP712Domain":[{"name":"name","type":"string"},{"name":"version","type":"string"},{"name":"chainId","type":"uint256"},{"name":"verifyingContract","type":"address"}]}}"#,
                digest: "40121638f6eadd80da9a0e75619805912421c3cd950c52daa2980f77fe29063a"),
        Payload(name: "a WalletConnect Mail",
                json: #"{"types":{"EIP712Domain":[{"name":"name","type":"string"},{"name":"chainId","type":"uint256"}],"Mail":[{"name":"contents","type":"string"}]},"primaryType":"Mail","domain":{"name":"THAT","chainId":1},"message":{"contents":"Hi"}}"#,
                digest: "f9e0f525196b618e6bd5a657c4a6c527859e60f2d93fd0cdd62de2ab5cf3769e"),
        Payload(name: "a Uniswap Permit2 single",
                json: #"{"types":{"EIP712Domain":[{"name":"name","type":"string"},{"name":"chainId","type":"uint256"},{"name":"verifyingContract","type":"address"}],"PermitSingle":[{"name":"details","type":"PermitDetails"},{"name":"spender","type":"address"},{"name":"sigDeadline","type":"uint256"}],"PermitDetails":[{"name":"token","type":"address"},{"name":"amount","type":"uint160"},{"name":"expiration","type":"uint48"},{"name":"nonce","type":"uint48"}]},"domain":{"name":"Permit2","chainId":1,"verifyingContract":"0x000000000022d473030f116ddee9f6b43ac78ba3"},"primaryType":"PermitSingle","message":{"details":{"token":"0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48","amount":"1461501637330902918203684832716283019655932542975","expiration":"1791390000","nonce":"0"},"spender":"0x66a9893cc07d91d95644aedd05d03f95e1dba8af","sigDeadline":"1788795600"}}"#,
                digest: "c543a973b1ff45109e50d8653a09988f0c734b990437c1a80890603bacc4a253"),
        Payload(name: "a marketplace order with an array of structs",
                json: #"{"types":{"EIP712Domain":[{"name":"name","type":"string"},{"name":"version","type":"string"},{"name":"chainId","type":"uint256"},{"name":"verifyingContract","type":"address"}],"Order":[{"name":"maker","type":"address"},{"name":"amount","type":"uint256"},{"name":"items","type":"Item[]"}],"Item":[{"name":"id","type":"uint256"},{"name":"price","type":"uint256"}]},"domain":{"name":"Marketplace","version":"2","chainId":8453,"verifyingContract":"0x1111111111111111111111111111111111111111"},"primaryType":"Order","message":{"maker":"0x7b9d24ece83066220ad7872599df05cc61faa234","amount":"2","items":[{"id":"7","price":"1000000000000000000"},{"id":"9","price":"2500000000000000000"}]}}"#,
                digest: "dee64172de219147365994b30ee500f9eff614736b217489294b51ab4b5f4886"),
    ]

    @Test(arguments: payloads)
    func aTHATPayloadHashesAndSignsAsItDidByteForByte(_ payload: Payload) throws {
        #expect(!payload.json.isEmpty)
        let old = try LegacyEIP712Parser.parse(payload.json).signHash()
        let new = try EIP712Parser.parse(payload.json).signHash()
        #expect(new == old)
        #expect(new.toHexString() == payload.digest)
        #expect(try EIP712Document(json: payload.json, reading: .strict).signingDigest == new)
        // The signature, byte for byte: what the old code signed and what Web3Signer signs now.
        let key = Data("web3swift 5.1.0 EIP-712 differential key".utf8).sha3(.keccak256)
        let keystore = try #require(PlainKeystore(privateKey: key))
        let account = try #require(keystore.addresses?.first)
        let signed = try Web3Signer.signTypedDataV4(payload.json, keystore: keystore, account: account, password: "")
        #expect(signed == Self.signature(of: old, key: key))
    }

    @Test func theUsernameClaimsPermitIsTheTokensOwnDigest() throws {
        // keccak256(0x1901 ‖ DOMAIN_SEPARATOR ‖ keccak256(abi.encode(PERMIT_TYPEHASH, owner, spender, value, nonce, deadline))),
        // as the token computes it, with no typed data at all.
        let typeHash = Data("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)".utf8).sha3(.keccak256)
        let owner = try #require(EthereumAddress(Self.owner)), spender = try #require(EthereumAddress("0xD434fe798BA3EC91B593056D020025D1530c2c2B"))
        let structHash = (typeHash + Data(count: 12) + owner.addressData + Data(count: 12) + spender.addressData
            + (BigUInt(5) * BigUInt(10).power(18)).uint256BE + BigUInt(3).uint256BE + BigUInt(1_795_000_000).uint256BE).sha3(.keccak256)
        let separator = ERC2612.computeDomainSeparator(name: "THAT", version: "1", chainId: 137, verifyingContract: try #require(EthereumAddress(Self.token)))
        let digest = (Data([0x19, 0x01]) + separator + structHash).sha3(.keccak256)
        let claim = try #require(Self.payloads.first { $0.name == "the username claim's permit" })
        #expect(try EIP712Parser.parse(claim.json).signHash() == digest)
        #expect(digest.toHexString() == claim.digest)
    }
}
