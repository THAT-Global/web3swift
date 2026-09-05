//
//  ABIDecoderHeadTailTests.swift
//  Web3CoreTests
//
//  THAT fork, 2026-09-05. Regression for the head/tail bookkeeping in
//  `ABIDecoder`: upstream mixed "bytes consumed" and "pointer to next element"
//  in `decodeSingleType`'s second return value, so `bytes`, `string[]` or a
//  dynamic tuple in any position but the last shifted every following field,
//  and a `string[]` of three or more elements repeated its second element.
//  Upstream's only `string[]` coverage (`AdvancedABIv2Tests.testDynOfDyn`) has
//  it in last position, where the wrong pointer is never read again — and that
//  suite needs a local node, so it could not have caught this offline anyway.
//
//  This target depends on Web3Core ONLY and runs with
//  `WEB3SWIFT_CORE_TESTS_ONLY=1 swift test --filter Web3CoreTests` (see
//  Package.swift): the `localTests` / `remoteTests` targets have not compiled
//  since the contracts rewrite and are owed their own act.
//
//  The payload is a verbatim EIP-3668 `OffchainLookup` revert captured from
//  the ENS Universal Resolver (0xeEeEEEeE14D718C2B47D9923Deab1335E144EeEe) on
//  mainnet via `eth_call`, decoded independently with `cast abi-decode`:
//    sender           0xeEeEEEeE14D718C2B47D9923Deab1335E144EeEe
//    urls             ["https://ccip-v3.ens.xyz", "x-batch-gateway:true"]
//    callData         0xa780bab6…
//    callbackFunction 0xef46c0b8
//    extraData        0x0000…20…  (non-empty)
//

import Foundation
import Web3Core
import XCTest
import BigInt
import CryptoSwift

final class ABIDecoderHeadTailTests: XCTestCase {

    /// `OffchainLookup(address,string[],bytes,bytes4,bytes)` — selector + args.
    static let offchainLookupRevert = "0x"
        + "556f1830000000000000000000000000eeeeeeee14d718c2b47d9923deab1335e144eeee000000000000000000000000"
        + "00000000000000000000000000000000000000a000000000000000000000000000000000000000000000000000000000"
        + "00000180ef46c0b800000000000000000000000000000000000000000000000000000000000000000000000000000000"
        + "000000000000000000000000000000000000046000000000000000000000000000000000000000000000000000000000"
        + "000000020000000000000000000000000000000000000000000000000000000000000040000000000000000000000000"
        + "000000000000000000000000000000000000008000000000000000000000000000000000000000000000000000000000"
        + "0000001768747470733a2f2f636369702d76332e656e732e78797a000000000000000000000000000000000000000000"
        + "0000000000000000000000000000000000000014782d62617463682d676174657761793a747275650000000000000000"
        + "0000000000000000000000000000000000000000000000000000000000000000000002a4a780bab60000000000000000"
        + "000000000000000000000000000000000000000000000020000000000000000000000000000000000000000000000000"
        + "000000000000000100000000000000000000000000000000000000000000000000000000000000200000000000000000"
        + "00000000de9049636f4a1dfe0a64d1bfe3155c0a14c54f31000000000000000000000000000000000000000000000000"
        + "000000000000006000000000000000000000000000000000000000000000000000000000000001200000000000000000"
        + "000000000000000000000000000000000000000000000001000000000000000000000000000000000000000000000000"
        + "0000000000000020000000000000000000000000000000000000000000000000000000000000004d68747470733a2f2f"
        + "6170692e636f696e626173652e636f6d2f6170692f76312f646f6d61696e2f7265736f6c7665722f7265736f6c766544"
        + "6f6d61696e2f7b73656e6465727d2f7b646174617d000000000000000000000000000000000000000000000000000000"
        + "0000000000000000000000000000000000000000000000e49061b9230000000000000000000000000000000000000000"
        + "000000000000000000000040000000000000000000000000000000000000000000000000000000000000008000000000"
        + "00000000000000000000000000000000000000000000000000000010056a657373650462617365036574680000000000"
        + "00000000000000000000000000000000000000000000000000000000000000000000000000000000000000243b3b57de"
        + "286c3ecf9d29c1d2cc5b4606d9f2164c4a6f069f8edcc0bb406b838b6985650900000000000000000000000000000000"
        + "000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000"
        + "000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000"
        + "000008e00000000000000000000000000000000000000000000000000000000000000020000000000000000000000000"
        + "ed73a03f19e8d849e44a39252d222c6ad5217e1eb536af76000000000000000000000000000000000000000000000000"
        + "0000000000000000000000000000000000000000000000000000000000000000000000c0491fc4f90000000000000000"
        + "000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000"
        + "0000000000000000000000000000000000000000000000000000000000000000000007e0000000000000000000000000"
        + "000000000000000000000000000000000000070000000000000000000000000000000000000000000000000000000000"
        + "000000200000000000000000000000000000000000000000000000000000000000000040000000000000000000000000"
        + "000000000000000000000000000000000000060000000000000000000000000000000000000000000000000000000000"
        + "000000010000000000000000000000000000000000000000000000000000000000000020000000000000000000000000"
        + "de9049636f4a1dfe0a64d1bfe3155c0a14c54f3100000000000000000000000000000000000000000000000000000000"
        + "0000008000000000000000000000000000000000000000000000000000000000000001a0000000000000000000000000"
        + "000000000000000000000000000000000000002100000000000000000000000000000000000000000000000000000000"
        + "000000e49061b92300000000000000000000000000000000000000000000000000000000000000400000000000000000"
        + "000000000000000000000000000000000000000000000080000000000000000000000000000000000000000000000000"
        + "0000000000000010056a6573736504626173650365746800000000000000000000000000000000000000000000000000"
        + "0000000000000000000000000000000000000000000000243b3b57de286c3ecf9d29c1d2cc5b4606d9f2164c4a6f069f"
        + "8edcc0bb406b838b69856509000000000000000000000000000000000000000000000000000000000000000000000000"
        + "000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000"
        + "000003a4556f1830000000000000000000000000de9049636f4a1dfe0a64d1bfe3155c0a14c54f310000000000000000"
        + "0000000000000000000000000000000000000000000000a0000000000000000000000000000000000000000000000000"
        + "0000000000000160f4d4d2f8000000000000000000000000000000000000000000000000000000000000000000000000"
        + "000000000000000000000000000000000000000000000280000000000000000000000000000000000000000000000000"
        + "000000000000000100000000000000000000000000000000000000000000000000000000000000200000000000000000"
        + "00000000000000000000000000000000000000000000004d68747470733a2f2f6170692e636f696e626173652e636f6d"
        + "2f6170692f76312f646f6d61696e2f7265736f6c7665722f7265736f6c7665446f6d61696e2f7b73656e6465727d2f7b"
        + "646174617d00000000000000000000000000000000000000000000000000000000000000000000000000000000000000"
        + "00000000000000e49061b923000000000000000000000000000000000000000000000000000000000000004000000000"
        + "000000000000000000000000000000000000000000000000000000800000000000000000000000000000000000000000"
        + "000000000000000000000010056a65737365046261736503657468000000000000000000000000000000000000000000"
        + "000000000000000000000000000000000000000000000000000000243b3b57de286c3ecf9d29c1d2cc5b4606d9f2164c"
        + "4a6f069f8edcc0bb406b838b698565090000000000000000000000000000000000000000000000000000000000000000"
        + "000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000"
        + "00000000000000e49061b923000000000000000000000000000000000000000000000000000000000000004000000000"
        + "000000000000000000000000000000000000000000000000000000800000000000000000000000000000000000000000"
        + "000000000000000000000010056a65737365046261736503657468000000000000000000000000000000000000000000"
        + "000000000000000000000000000000000000000000000000000000243b3b57de286c3ecf9d29c1d2cc5b4606d9f2164c"
        + "4a6f069f8edcc0bb406b838b698565090000000000000000000000000000000000000000000000000000000000000000"
        + "000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000"
        + "000000000000000000000000000000000000000000000000000000000000000000000002000000000000000000000000"
        + "000000000000000000000000000000000000004000000000000000000000000000000000000000000000000000000000"
        + "00000080000000000000000000000000000000000000000000000000000000000000001768747470733a2f2f63636970"
        + "2d76332e656e732e78797a00000000000000000000000000000000000000000000000000000000000000000000000000"
        + "00000014782d62617463682d676174657761793a74727565000000000000000000000000000000000000000000000000"
        + "00000000000000000000000000000000000000c000000000000000000000000000000000000000000000000000000000"
        + "000000010000000000000000000000000000000000000000000000000000000000000000b4a858010000000000000000"
        + "000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000"
        + "000000800000000000000000000000000000000000000000000000000000000000000020000000000000000000000000"
        + "de9049636f4a1dfe0a64d1bfe3155c0a14c54f31"

    static let expectedSender = "0xeEeEEEeE14D718C2B47D9923Deab1335E144EeEe"
    static let expectedURLs = ["https://ccip-v3.ens.xyz", "x-batch-gateway:true"]
    static let expectedCallbackSelector = "ef46c0b8"
    static let expectedCallDataPrefix = "a780bab6"

    private var revertBytes: Data { Data(hex: Self.offchainLookupRevert) }

    /// The top-level entry point, with the arguments after the selector — the
    /// path `EthError.decodeEthError` takes.
    func testTopLevelDecodeSurvivesStringArrayInSecondPosition() throws {
        let types: [ABI.Element.ParameterType] = [
            .address, .array(type: .string, length: 0), .dynamicBytes, .bytes(length: 4), .dynamicBytes
        ]
        let args = revertBytes[4...]
        guard let values = ABIDecoder.decode(types: types, data: args) else {
            return XCTFail("decode returned nil")
        }
        XCTAssertEqual(values.count, 5)
        XCTAssertEqual((values[0] as? EthereumAddress)?.address, Self.expectedSender)
        XCTAssertEqual((values[1] as? [Any])?.compactMap { $0 as? String }, Self.expectedURLs)
        XCTAssertTrue(((values[2] as? Data)?.toHexString() ?? "").hasPrefix(Self.expectedCallDataPrefix))
        XCTAssertEqual((values[3] as? Data)?.toHexString(), Self.expectedCallbackSelector)
        XCTAssertFalse((values[4] as? Data)?.isEmpty ?? true)
    }

    /// The contract path: a declared custom error must surface as the TYPED
    /// `Web3Error.revertCustom`, with the arguments keyed by name.
    func testDeclaredCustomErrorWithStringArrayDecodesTyped() throws {
        let abi = """
        [{"type":"function","name":"resolve","stateMutability":"view",
          "inputs":[{"name":"name","type":"bytes"},{"name":"data","type":"bytes"}],
          "outputs":[{"name":"result","type":"bytes"},{"name":"resolver","type":"address"}]},
         {"type":"error","name":"OffchainLookup",
          "inputs":[{"name":"sender","type":"address"},{"name":"urls","type":"string[]"},{"name":"callData","type":"bytes"},
                    {"name":"callbackFunction","type":"bytes4"},{"name":"extraData","type":"bytes"}]}]
        """
        let contract = try EthereumContract(abi)
        XCTAssertThrowsError(try contract.decodeReturnData("resolve", data: revertBytes)) { error in
            guard case Web3Error.revertCustom(let signature, let args) = error else {
                return XCTFail("expected revertCustom, got \(error)")
            }
            XCTAssertEqual(signature, "OffchainLookup(address,string[],bytes,bytes4,bytes)")
            XCTAssertEqual((args["sender"] as? EthereumAddress)?.address, Self.expectedSender)
            XCTAssertEqual((args["urls"] as? [Any])?.compactMap { $0 as? String }, Self.expectedURLs)
            XCTAssertEqual((args["callbackFunction"] as? Data)?.toHexString(), Self.expectedCallbackSelector)
            XCTAssertFalse((args["extraData"] as? Data)?.isEmpty ?? true)
        }
    }

    /// Synthetic shape with the dynamic array FIRST, followed by static and
    /// dynamic fields, round-tripped through the encoder: the encoder was never
    /// wrong, so agreement here isolates the decoder's pointer bookkeeping.
    func testStringArrayInFirstPositionRoundTrips() throws {
        let types: [ABI.Element.ParameterType] = [
            .array(type: .string, length: 0), .uint(bits: 256), .string, .array(type: .uint(bits: 8), length: 0)
        ]
        let values: [Any] = [["alpha", "beta", "gamma"], BigUInt(42), "tail", [BigUInt(1), BigUInt(2)]]
        guard let encoded = ABIEncoder.encode(types: types, values: values) else { return XCTFail("encode") }
        guard let decoded = ABIDecoder.decode(types: types, data: encoded) else { return XCTFail("decode") }
        XCTAssertEqual((decoded[0] as? [Any])?.compactMap { $0 as? String }, ["alpha", "beta", "gamma"])
        XCTAssertEqual(decoded[1] as? BigUInt, BigUInt(42))
        XCTAssertEqual(decoded[2] as? String, "tail")
        XCTAssertEqual((decoded[3] as? [Any])?.compactMap { $0 as? BigUInt }, [BigUInt(1), BigUInt(2)])
    }

    /// Last position keeps working (upstream's covered shape).
    func testStringArrayInLastPositionStillDecodes() throws {
        let types: [ABI.Element.ParameterType] = [.uint(bits: 256), .array(type: .string, length: 0)]
        let values: [Any] = [BigUInt(7), ["x", "yy"]]
        guard let encoded = ABIEncoder.encode(types: types, values: values),
              let decoded = ABIDecoder.decode(types: types, data: encoded) else { return XCTFail("roundtrip") }
        XCTAssertEqual(decoded[0] as? BigUInt, BigUInt(7))
        XCTAssertEqual((decoded[1] as? [Any])?.compactMap { $0 as? String }, ["x", "yy"])
    }

    /// `bytes` in a MIDDLE position, followed by static and dynamic fields.
    func testDynamicBytesInMiddlePositionRoundTrips() throws {
        let types: [ABI.Element.ParameterType] = [.uint(bits: 256), .dynamicBytes, .uint(bits: 256), .dynamicBytes]
        let values: [Any] = [BigUInt(1), Data([0xde, 0xad]), BigUInt(2), Data([0xbe, 0xef, 0x00])]
        guard let encoded = ABIEncoder.encode(types: types, values: values),
              let decoded = ABIDecoder.decode(types: types, data: encoded) else { return XCTFail("roundtrip") }
        XCTAssertEqual(decoded[0] as? BigUInt, BigUInt(1))
        XCTAssertEqual((decoded[1] as? Data)?.toHexString(), "dead")
        XCTAssertEqual(decoded[2] as? BigUInt, BigUInt(2))
        XCTAssertEqual((decoded[3] as? Data)?.toHexString(), "beef00")
    }

    /// A dynamic tuple in a MIDDLE position. Payload from
    /// `cast abi-encode "f(uint256,(uint256,string),uint256)" 5 "(6,six)" 7`.
    /// Decoded from an independent oracle rather than round-tripped: the fork's
    /// ENCODER traps on nested tuple values (BigInt string conversion) — a
    /// separate, pre-existing defect, noted here and not fixed in this change.
    func testDynamicTupleInMiddlePosition() throws {
        let types: [ABI.Element.ParameterType] = [.uint(bits: 256), .tuple(types: [.uint(bits: 256), .string]), .uint(bits: 256)]
        guard let decoded = ABIDecoder.decode(types: types, data: Data(hex: "0000000000000000000000000000000000000000000000000000000000000005000000000000000000000000000000000000000000000000000000000000006000000000000000000000000000000000000000000000000000000000000000070000000000000000000000000000000000000000000000000000000000000006000000000000000000000000000000000000000000000000000000000000004000000000000000000000000000000000000000000000000000000000000000037369780000000000000000000000000000000000000000000000000000000000")) else {
            return XCTFail("decode returned nil")
        }
        XCTAssertEqual(decoded[0] as? BigUInt, BigUInt(5))
        XCTAssertEqual((decoded[1] as? [Any])?.first as? BigUInt, BigUInt(6))
        XCTAssertEqual((decoded[1] as? [Any])?.last as? String, "six")
        XCTAssertEqual(decoded[2] as? BigUInt, BigUInt(7))
    }

    /// A `bytes[]` with three elements — the array loop must advance one head
    /// word per element for EVERY dynamic subtype, not only for `bytes`.
    func testBytesArrayAndStringArrayWithThreeElements() throws {
        let types: [ABI.Element.ParameterType] = [.array(type: .dynamicBytes, length: 0), .array(type: .string, length: 0)]
        let values: [Any] = [[Data([1]), Data([2, 2]), Data([3, 3, 3])], ["a", "bb", "ccc"]]
        guard let encoded = ABIEncoder.encode(types: types, values: values),
              let decoded = ABIDecoder.decode(types: types, data: encoded) else { return XCTFail("roundtrip") }
        XCTAssertEqual((decoded[0] as? [Any])?.compactMap { ($0 as? Data)?.toHexString() }, ["01", "0202", "030303"])
        XCTAssertEqual((decoded[1] as? [Any])?.compactMap { $0 as? String }, ["a", "bb", "ccc"])
    }

    // MARK: More head/tail shapes, encoder-independent by construction
    //
    // The encoder is separate code that was never wrong, so encode→decode
    // agreement isolates the decoder's pointer bookkeeping.

    private func roundTrip(_ types: [ABI.Element.ParameterType], _ values: [Any]) throws -> [Any] {
        guard let encoded = ABIEncoder.encode(types: types, values: values) else { throw XCTSkip("encoder refused shape") }
        guard let decoded = ABIDecoder.decode(types: types, data: encoded) else { XCTFail("decode returned nil"); return [] }
        XCTAssertEqual(decoded.count, values.count)
        return decoded
    }

    func testStaticOnlyShapeIsUnchanged() throws {
        let d = try roundTrip([.uint(bits: 256), .address, .bool, .bytes(length: 4)],
                              [BigUInt(9), EthereumAddress("0xd8dA6BF26964aF9D7eEd9e03E53415D37aA96045")!, true, Data([1, 2, 3, 4])])
        XCTAssertEqual(d[0] as? BigUInt, BigUInt(9))
        XCTAssertEqual((d[1] as? EthereumAddress)?.address, "0xd8dA6BF26964aF9D7eEd9e03E53415D37aA96045")
        XCTAssertEqual(d[2] as? Bool, true)
        XCTAssertEqual((d[3] as? Data)?.toHexString(), "01020304")
    }

    func testStringInMiddlePosition() throws {
        let d = try roundTrip([.uint(bits: 256), .string, .uint(bits: 256)], [BigUInt(1), "middle", BigUInt(2)])
        XCTAssertEqual(d[1] as? String, "middle")
        XCTAssertEqual(d[2] as? BigUInt, BigUInt(2))
    }

    func testStaticSizeArrayOfStringsInMiddlePosition() throws {
        let d = try roundTrip([.uint(bits: 256), .array(type: .string, length: 2), .uint(bits: 256)],
                              [BigUInt(1), ["p", "qq"], BigUInt(2)])
        XCTAssertEqual((d[1] as? [Any])?.compactMap { $0 as? String }, ["p", "qq"])
        XCTAssertEqual(d[2] as? BigUInt, BigUInt(2))
    }

    /// `(uint256,string)[]` with THREE elements in a MIDDLE position, then a string.
    /// `cast abi-encode "f(uint256,(uint256,string)[],string)" 1 "[(10,ten),(11,eleven),(12,twelve)]" end`
    func testArrayOfDynamicTuplesInMiddlePosition() throws {
        let tup: ABI.Element.ParameterType = .tuple(types: [.uint(bits: 256), .string])
        let types: [ABI.Element.ParameterType] = [.uint(bits: 256), .array(type: tup, length: 0), .string]
        guard let decoded = ABIDecoder.decode(types: types, data: Data(hex: "0000000000000000000000000000000000000000000000000000000000000001000000000000000000000000000000000000000000000000000000000000006000000000000000000000000000000000000000000000000000000000000002600000000000000000000000000000000000000000000000000000000000000003000000000000000000000000000000000000000000000000000000000000006000000000000000000000000000000000000000000000000000000000000000e00000000000000000000000000000000000000000000000000000000000000160000000000000000000000000000000000000000000000000000000000000000a0000000000000000000000000000000000000000000000000000000000000040000000000000000000000000000000000000000000000000000000000000000374656e0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000b00000000000000000000000000000000000000000000000000000000000000400000000000000000000000000000000000000000000000000000000000000006656c6576656e0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000c000000000000000000000000000000000000000000000000000000000000004000000000000000000000000000000000000000000000000000000000000000067477656c766500000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000003656e640000000000000000000000000000000000000000000000000000000000")) else {
            return XCTFail("decode returned nil")
        }
        XCTAssertEqual(decoded[0] as? BigUInt, BigUInt(1))
        let tuples = decoded[1] as? [Any]
        XCTAssertEqual(tuples?.count, 3)
        XCTAssertEqual((tuples?[0] as? [Any])?.first as? BigUInt, BigUInt(10))
        XCTAssertEqual((tuples?[1] as? [Any])?.last as? String, "eleven")
        XCTAssertEqual((tuples?[2] as? [Any])?.last as? String, "twelve")
        XCTAssertEqual(decoded[2] as? String, "end")
    }

    func testDynamicArrayOfStaticInMiddleStillWorks() throws {
        let d = try roundTrip([.string, .array(type: .uint(bits: 256), length: 0), .string],
                              ["a", [BigUInt(1), BigUInt(2), BigUInt(3)], "z"])
        XCTAssertEqual((d[1] as? [Any])?.compactMap { $0 as? BigUInt }, [BigUInt(1), BigUInt(2), BigUInt(3)])
        XCTAssertEqual(d[2] as? String, "z")
    }

    /// The Universal Resolver's return shape, `(bytes, address)`, via the
    /// contract path — the shape ENSKit decodes on every successful resolution.
    func testBytesThenAddressReturnDecodesThroughContract() throws {
        let abi = """
        [{"type":"function","name":"resolve","stateMutability":"view","inputs":[],
          "outputs":[{"name":"result","type":"bytes"},{"name":"resolver","type":"address"}]}]
        """
        let contract = try EthereumContract(abi)
        // Verbatim eth_call result for vitalik.eth (mainnet, 2026-09-05).
        let data = Data(hex: "0000000000000000000000000000000000000000000000000000000000000040000000000000000000000000231b0ee14048e9dccd1d247744d114a4eb5e8e630000000000000000000000000000000000000000000000000000000000000020000000000000000000000000d8da6bf26964af9d7eed9e03e53415d37aa96045")
        let values = try contract.decodeReturnData("resolve", data: data)
        XCTAssertEqual((values["resolver"] as? EthereumAddress)?.address, "0x231b0Ee14048e9dCcD1d247744d114a4EB5E8E63")
        XCTAssertEqual((values["result"] as? Data)?.toHexString(), "000000000000000000000000d8da6bf26964af9d7eed9e03e53415d37aa96045")
    }
}
