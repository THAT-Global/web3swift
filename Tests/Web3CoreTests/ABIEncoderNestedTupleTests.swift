//
//  ABIEncoderNestedTupleTests.swift
//  Web3CoreTests
//
//  ENS act debt sizing (ENS-SEND-FLOW-ASSESSMENT.md §10): the fork's ENCODER was
//  reported to trap on nested tuple values, which is why the decoder tests decode
//  `cast` fixtures instead of round-tripping. This pins what the encoder actually
//  does with a dynamic tuple in a middle position, against the same independent
//  oracle the decoder test uses:
//      cast abi-encode "f(uint256,(uint256,string),uint256)" 5 "(6,six)" 7
//

import XCTest
import BigInt
@testable import Web3Core

final class ABIEncoderNestedTupleTests: XCTestCase {

    private let oracle = Data(hex: "0000000000000000000000000000000000000000000000000000000000000005000000000000000000000000000000000000000000000000000000000000006000000000000000000000000000000000000000000000000000000000000000070000000000000000000000000000000000000000000000000000000000000006000000000000000000000000000000000000000000000000000000000000004000000000000000000000000000000000000000000000000000000000000000037369780000000000000000000000000000000000000000000000000000000000")

    private let types: [ABI.Element.ParameterType] = [.uint(bits: 256), .tuple(types: [.uint(bits: 256), .string]), .uint(bits: 256)]

    func testNestedDynamicTupleEncodesToTheCastOracle() {
        let encoded = ABIEncoder.encode(types: types, values: [BigUInt(5), [BigUInt(6), "six"] as [Any], BigUInt(7)])
        XCTAssertEqual(encoded?.toHexString(), oracle.toHexString())
    }

    func testNestedDynamicTupleWithIntegerLiteralsEncodesToTheCastOracle() {
        // The shape a caller writes by hand: Swift Int literals, not BigUInt.
        let encoded = ABIEncoder.encode(types: types, values: [5, [6, "six"] as [Any], 7])
        XCTAssertEqual(encoded?.toHexString(), oracle.toHexString())
    }

    /// `cast abi-encode "f(uint256,(uint256,string)[],string)" 1 "[(10,ten),(11,eleven),(12,twelve)]" end`
    /// — an ARRAY of dynamic tuples in a middle position, the other shape the
    /// decoder test takes from the oracle.
    func testArrayOfDynamicTuplesEncodesToTheCastOracle() {
        let tup: ABI.Element.ParameterType = .tuple(types: [.uint(bits: 256), .string])
        let types: [ABI.Element.ParameterType] = [.uint(bits: 256), .array(type: tup, length: 0), .string]
        // Each inner tuple is typed `[Any]` on purpose: `BigUInt` is
        // `ExpressibleByStringLiteral`, so an untyped nested literal like
        // `[BigUInt(10), "ten"]` is inferred as `[BigUInt]` and `"ten"` becomes
        // `BigUInt(stringLiteral:)` — which traps in BigInt's String Conversion.
        // That inference trap in TEST code is the "encoder traps on nested
        // tuple values" the E1 note recorded; the encoder itself is fine.
        let tuples: [Any] = [
            [BigUInt(10), "ten"] as [Any],
            [BigUInt(11), "eleven"] as [Any],
            [BigUInt(12), "twelve"] as [Any],
        ]
        let values: [Any] = [BigUInt(1), tuples, "end"]
        let oracle = "0000000000000000000000000000000000000000000000000000000000000001000000000000000000000000000000000000000000000000000000000000006000000000000000000000000000000000000000000000000000000000000002600000000000000000000000000000000000000000000000000000000000000003000000000000000000000000000000000000000000000000000000000000006000000000000000000000000000000000000000000000000000000000000000e00000000000000000000000000000000000000000000000000000000000000160000000000000000000000000000000000000000000000000000000000000000a0000000000000000000000000000000000000000000000000000000000000040000000000000000000000000000000000000000000000000000000000000000374656e0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000b00000000000000000000000000000000000000000000000000000000000000400000000000000000000000000000000000000000000000000000000000000006656c6576656e0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000c000000000000000000000000000000000000000000000000000000000000004000000000000000000000000000000000000000000000000000000000000000067477656c766500000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000003656e640000000000000000000000000000000000000000000000000000000000"
        let encoded = ABIEncoder.encode(types: types, values: values)
        XCTAssertEqual(encoded?.toHexString(), oracle)
    }
}
