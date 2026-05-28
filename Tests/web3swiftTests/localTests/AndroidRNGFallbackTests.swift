//
//  AndroidRNGFallbackTests.swift
//  localTests
//
//  Wiring verification for the non-Apple `Data.randomBytes` fallback that
//  ships in R-19 (Pattern B). On Apple platforms `Data.randomBytes` calls
//  `SecRandomCopyBytes`; on non-Apple platforms it falls back to Swift
//  stdlib `SystemRandomNumberGenerator` (kernel CSPRNG via `getrandom(2)`
//  on Android). These tests verify the fallback produces *non-trivial*
//  output — they are intentionally NOT cryptographic-strength validation;
//  they catch a wiring error (e.g. a fallback that always returns zeros)
//  not an entropy-quality bug.
//
//  The whole file is gated by `#if !canImport(Security)`, so it compiles
//  only on platforms that actually take the fallback path (Linux,
//  Android). On Apple platforms this test target is unaffected.
//

#if !canImport(Security)

import XCTest
@testable import Web3Core

final class AndroidRNGFallbackTests: XCTestCase {

    /// 32 bytes from the fallback must not be all-zero.
    func test_randomBytes32_isNotAllZero() throws {
        let data = try XCTUnwrap(Data.randomBytes(length: 32), "Data.randomBytes returned nil")
        XCTAssertEqual(data.count, 32, "randomBytes(length: 32) returned \(data.count) bytes")
        XCTAssertFalse(data.allSatisfy { $0 == 0x00 }, "fallback produced all-zero output")
    }

    /// 32 bytes from the fallback must not be all-0xFF.
    func test_randomBytes32_isNotAllFF() throws {
        let data = try XCTUnwrap(Data.randomBytes(length: 32))
        XCTAssertFalse(data.allSatisfy { $0 == 0xFF }, "fallback produced all-0xFF output")
    }

    /// 32 bytes from the fallback must not be a repeating 4-byte pattern.
    /// (A 4-byte stride covers e.g. a misuse of `arc4random()` truncated
    /// to one uint32 and broadcast.)
    func test_randomBytes32_isNotRepeatingFourBytePattern() throws {
        let data = try XCTUnwrap(Data.randomBytes(length: 32))
        let bytes = [UInt8](data)
        let firstBlock = Array(bytes.prefix(4))
        let allRepeats = stride(from: 0, to: bytes.count, by: 4).allSatisfy { offset in
            offset + 4 <= bytes.count && Array(bytes[offset ..< offset + 4]) == firstBlock
        }
        XCTAssertFalse(allRepeats, "fallback produced a 4-byte repeating pattern (likely a wiring bug, not random output)")
    }

    /// Two consecutive calls should not produce identical 32-byte blocks.
    /// A wiring bug that returns a fixed buffer would trip this.
    func test_consecutiveCalls_areNotIdentical() throws {
        let a = try XCTUnwrap(Data.randomBytes(length: 32))
        let b = try XCTUnwrap(Data.randomBytes(length: 32))
        XCTAssertNotEqual(a, b, "two consecutive randomBytes calls returned identical output")
    }

    /// Length parameter is honored across a few common sizes used in the
    /// codebase (32 = wallet entropy, 12 = nonce, 16 = AES-GCM IV).
    func test_lengthParameterIsHonored() throws {
        for length in [12, 16, 32, 64] {
            let data = try XCTUnwrap(Data.randomBytes(length: length))
            XCTAssertEqual(data.count, length, "randomBytes(length: \(length)) returned \(data.count) bytes")
        }
    }
}

#endif // !canImport(Security)
