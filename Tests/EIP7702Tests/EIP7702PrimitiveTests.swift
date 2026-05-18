//
//  EIP7702PrimitiveTests.swift
//  EIP7702Tests
//
//  Sanity / invariant tests for the EIP-7702 + ERC-4337 v0.7 primitives
//  the THAT sponsored stack depends on. The intent here is to lock the
//  bearer-crypto behaviour against regressions, not to replace a full
//  vector-comparison test against AccountKit's reference (still
//  outstanding — see TODO at the bottom of this file).
//

import XCTest
import BigInt
@testable import Web3Core

final class EIP7702PrimitiveTests: XCTestCase {

    private let privateKey: Data = Data((1...32).map { UInt8($0) })

    // MARK: - EIP7702Authorization

    /// §5.6 universal-replay guard — signing with `chainID == 0` MUST throw.
    func testAuthorizationSignRejectsChainIDZero() {
        var auth = EIP7702Authorization(
            chainID: 0,
            address: EthereumAddress(Data(repeating: 0xab, count: 20))!,
            nonce: 0
        )
        XCTAssertThrowsError(try auth.sign(privateKey: privateKey)) { err in
            XCTAssertEqual(err as? EIP7702Error, .chainIDZero,
                          "sign(...) must throw .chainIDZero for chainID 0")
        }
        // No signature was produced.
        XCTAssertEqual(auth.r, 0)
        XCTAssertEqual(auth.s, 0)
    }

    /// The signing hash MUST bind every field in the tuple. Changing
    /// chainID, address, or nonce in isolation must change the hash —
    /// otherwise an attacker could swap one field after signing.
    func testAuthorizationSigningHashBindsAllFields() {
        let base = EIP7702Authorization(
            chainID: 137,
            address: EthereumAddress(Data(repeating: 0xab, count: 20))!,
            nonce: 5
        )
        let baseHash = base.signingHash()
        XCTAssertNotNil(baseHash)

        let chainChanged = EIP7702Authorization(
            chainID: 8453, address: base.address, nonce: base.nonce
        )
        let addrChanged = EIP7702Authorization(
            chainID: base.chainID,
            address: EthereumAddress(Data(repeating: 0xcd, count: 20))!,
            nonce: base.nonce
        )
        let nonceChanged = EIP7702Authorization(
            chainID: base.chainID, address: base.address, nonce: 6
        )

        XCTAssertNotEqual(chainChanged.signingHash(), baseHash, "chainID must bind into the hash")
        XCTAssertNotEqual(addrChanged.signingHash(), baseHash, "delegate address must bind into the hash")
        XCTAssertNotEqual(nonceChanged.signingHash(), baseHash, "nonce must bind into the hash")
    }

    /// Round-trip: signing then `recoverSigner` returns the address the
    /// private key derives to. Catches any regression in the magic-byte +
    /// RLP preimage construction.
    func testAuthorizationSignAndRecoverRoundtrip() throws {
        guard let pub = SECP256K1.privateToPublic(privateKey: privateKey),
              let expectedSigner = Utilities.publicToAddress(pub) else {
            XCTFail("could not derive expected signer from test private key")
            return
        }
        var auth = EIP7702Authorization(
            chainID: 137,
            address: EthereumAddress(Data(repeating: 0xab, count: 20))!,
            nonce: 7
        )
        try auth.sign(privateKey: privateKey)
        XCTAssertNotEqual(auth.r, 0, "r must be set after sign()")
        XCTAssertNotEqual(auth.s, 0, "s must be set after sign()")
        XCTAssertEqual(auth.recoverSigner(), expectedSigner,
                       "recovered signer must match the key derivation")
    }

    // MARK: - EIP7702SetCodeTransaction

    /// SetCode tx (type 0x04) signing hash MUST bind chainID — cross-chain
    /// replay protection at the outer tx layer (defence-in-depth on top of
    /// the auth tuple's own chainID binding).
    func testSetCodeTransactionSigningHashBindsChainID() throws {
        let pub = SECP256K1.privateToPublic(privateKey: privateKey)!
        let signer = Utilities.publicToAddress(pub)!
        var auth = EIP7702Authorization(chainID: 137, address: signer, nonce: 1)
        try auth.sign(privateKey: privateKey)

        let tx1 = EIP7702SetCodeTransaction(
            chainID: 137, nonce: 1,
            maxPriorityFeePerGas: 1, maxFeePerGas: 2,
            gasLimit: 100_000, to: signer, value: 0, data: Data(),
            authorizationList: [auth]
        )
        let tx2 = EIP7702SetCodeTransaction(
            chainID: 8453, nonce: 1,
            maxPriorityFeePerGas: 1, maxFeePerGas: 2,
            gasLimit: 100_000, to: signer, value: 0, data: Data(),
            authorizationList: [auth]
        )
        XCTAssertNotEqual(tx1.signingHash(), tx2.signingHash(),
                          "SetCode tx signing hash must bind chainID")
    }

    // MARK: - PackedUserOperation

    /// `PackedUserOperation.hash(entryPoint:chainID:)` MUST be deterministic
    /// for identical inputs. Catches any non-determinism that would break
    /// signature verification on the bundler side.
    func testPackedUserOperationHashIsDeterministic() {
        let op = makeSampleOp()
        let entryPoint = EthereumAddress("0x0000000071727De22E5E9d8BAf0edAc6f37da032")!
        let h1 = op.hash(entryPoint: entryPoint, chainID: 137)
        let h2 = op.hash(entryPoint: entryPoint, chainID: 137)
        XCTAssertEqual(h1, h2, "same inputs must produce same hash")
    }

    /// The hash MUST bind chainID — same user-op submitted to a different
    /// chain must hash differently.
    func testPackedUserOperationHashBindsChainID() {
        let op = makeSampleOp()
        let entryPoint = EthereumAddress("0x0000000071727De22E5E9d8BAf0edAc6f37da032")!
        XCTAssertNotEqual(
            op.hash(entryPoint: entryPoint, chainID: 137),
            op.hash(entryPoint: entryPoint, chainID: 8453),
            "userOpHash must bind chainID"
        )
    }

    /// The hash MUST bind the entry point address — same user-op routed
    /// through a different EntryPoint must hash differently.
    func testPackedUserOperationHashBindsEntryPoint() {
        let op = makeSampleOp()
        let ep1 = EthereumAddress("0x0000000071727De22E5E9d8BAf0edAc6f37da032")!
        let ep2 = EthereumAddress(Data(repeating: 0xff, count: 20))!
        XCTAssertNotEqual(
            op.hash(entryPoint: ep1, chainID: 137),
            op.hash(entryPoint: ep2, chainID: 137),
            "userOpHash must bind entry point"
        )
    }

    /// Every input field MUST bind — this catches subtle bugs in the
    /// hash preimage where one of the fields might have been omitted.
    func testPackedUserOperationHashBindsEveryField() {
        let entryPoint = EthereumAddress("0x0000000071727De22E5E9d8BAf0edAc6f37da032")!
        let baseHash = makeSampleOp().hash(entryPoint: entryPoint, chainID: 137)

        var senderChanged = makeSampleOp()
        senderChanged.sender = EthereumAddress(Data(repeating: 0xee, count: 20))!
        XCTAssertNotEqual(senderChanged.hash(entryPoint: entryPoint, chainID: 137), baseHash, "sender")

        var nonceChanged = makeSampleOp()
        nonceChanged.nonce = 42
        XCTAssertNotEqual(nonceChanged.hash(entryPoint: entryPoint, chainID: 137), baseHash, "nonce")

        var callDataChanged = makeSampleOp()
        callDataChanged.callData = Data([0xde, 0xad, 0xbe, 0xef])
        XCTAssertNotEqual(callDataChanged.hash(entryPoint: entryPoint, chainID: 137), baseHash, "callData")

        var initCodeChanged = makeSampleOp()
        initCodeChanged.initCode = Data([0x01, 0x02])
        XCTAssertNotEqual(initCodeChanged.hash(entryPoint: entryPoint, chainID: 137), baseHash, "initCode")

        var verGasChanged = makeSampleOp()
        verGasChanged.verificationGasLimit = 999_999
        XCTAssertNotEqual(verGasChanged.hash(entryPoint: entryPoint, chainID: 137), baseHash, "verificationGasLimit")

        var callGasChanged = makeSampleOp()
        callGasChanged.callGasLimit = 999_999
        XCTAssertNotEqual(callGasChanged.hash(entryPoint: entryPoint, chainID: 137), baseHash, "callGasLimit")

        var preGasChanged = makeSampleOp()
        preGasChanged.preVerificationGas = 999_999
        XCTAssertNotEqual(preGasChanged.hash(entryPoint: entryPoint, chainID: 137), baseHash, "preVerificationGas")

        var maxPrioChanged = makeSampleOp()
        maxPrioChanged.maxPriorityFeePerGas = 31_000_000_000  // sample default is 30 gwei
        XCTAssertNotEqual(maxPrioChanged.hash(entryPoint: entryPoint, chainID: 137), baseHash, "maxPriorityFeePerGas")

        var maxFeeChanged = makeSampleOp()
        maxFeeChanged.maxFeePerGas = 100_000_000_000        // sample default is 60 gwei
        XCTAssertNotEqual(maxFeeChanged.hash(entryPoint: entryPoint, chainID: 137), baseHash, "maxFeePerGas")

        var pmChanged = makeSampleOp()
        pmChanged.paymasterAndData = Data([0xab, 0xcd])
        XCTAssertNotEqual(pmChanged.hash(entryPoint: entryPoint, chainID: 137), baseHash, "paymasterAndData")
    }

    /// Signature MUST NOT bind into the hash (4337 v0.7 spec: signature is
    /// computed FROM the hash, never IN it).
    func testPackedUserOperationHashIgnoresSignatureField() {
        let entryPoint = EthereumAddress("0x0000000071727De22E5E9d8BAf0edAc6f37da032")!
        let baseHash = makeSampleOp().hash(entryPoint: entryPoint, chainID: 137)

        var sigChanged = makeSampleOp()
        sigChanged.signature = Data(repeating: 0xff, count: 65)
        XCTAssertEqual(sigChanged.hash(entryPoint: entryPoint, chainID: 137), baseHash,
                       "signature field MUST NOT bind into the user-op hash")
    }

    /// Pin `PackedUserOperation.hash(entryPoint:chainID:)` against
    /// AccountKit's reference computation for a fixed input. The reference
    /// values below come from running `aa-sdk`'s `getUserOperationHash`
    /// (entrypoint 0.7) — which uses `viem`'s `keccak256` /
    /// `encodeAbiParameters` / `pad` / `concat` primitives — over the same
    /// vector this test constructs. If this test ever fails, our preimage
    /// layout has diverged from the bundler's expected wire format and
    /// every sponsored user-op's signature will be invalid.
    ///
    /// Reference vector inputs:
    ///   sender                = 0xa1a1...a1a1 (20 × 0xa1)
    ///   nonce                 = 1
    ///   initCode              = 0x (empty)
    ///   callData              = 0xb61d27f6  (`execute` selector)
    ///   verificationGasLimit  = 100_000
    ///   callGasLimit          = 200_000
    ///   preVerificationGas    = 50_000
    ///   maxPriorityFeePerGas  = 30 gwei
    ///   maxFeePerGas          = 60 gwei
    ///   paymasterAndData      = 0x (empty)
    ///   entryPoint            = 0x0000000071727De22E5E9d8BAf0edAc6f37da032
    ///   chainId               = 137  (Polygon)
    ///
    /// To regenerate after a deliberate change, run a Node script using
    /// `viem`'s primitives that mirrors
    /// `aa-sdk/core/src/entrypoint/0.7.ts:packUserOperation` +
    /// `getUserOperationHash`, pass the same inputs, and copy the result
    /// here.
    func testPackedUserOperationHashMatchesAccountKitReference() {
        let entryPoint = EthereumAddress("0x0000000071727De22E5E9d8BAf0edAc6f37da032")!
        let op = makeReferenceVectorOp()
        let actual = op.hash(entryPoint: entryPoint, chainID: 137)

        // viem.keccak256(viem.encodeAbiParameters([8 fields above]))
        let expectedPackedKeccak = Data.fromHex(
            "78133c6041594472eb7bf9531f156dda91e022e16f88945165d07904b78b2a57"
        )!
        // viem.keccak256(viem.encodeAbiParameters([packedKeccak, entryPoint, chainId]))
        let expectedUserOpHash = Data.fromHex(
            "dd3881aabb10ef451614f9a7bf9fd147cc508afb285344c240f4f2b7e80b72d5"
        )!

        // Cross-check the inner keccak too — if both diverge, the bug is
        // in the outer envelope; if only the outer one diverges, the bug is
        // in how we splice entryPoint / chainId on top.
        var innerPreimage = Data()
        innerPreimage.append(PackedUserOperation.padAddress(op.sender))
        innerPreimage.append(PackedUserOperation.padUint256(op.nonce))
        innerPreimage.append(op.initCode.sha3(.keccak256))
        innerPreimage.append(op.callData.sha3(.keccak256))
        innerPreimage.append(op.accountGasLimits)
        innerPreimage.append(PackedUserOperation.padUint256(op.preVerificationGas))
        innerPreimage.append(op.gasFees)
        innerPreimage.append(op.paymasterAndData.sha3(.keccak256))
        XCTAssertEqual(
            innerPreimage.sha3(.keccak256), expectedPackedKeccak,
            "inner keccak256(abi.encode(packed)) diverges from AccountKit reference"
        )

        XCTAssertEqual(
            actual, expectedUserOpHash,
            "userOpHash diverges from AccountKit reference — wire format broken"
        )
    }

    // MARK: - Helpers

    private func makeSampleOp() -> PackedUserOperation {
        PackedUserOperation(
            sender: EthereumAddress(Data(repeating: 0xa1, count: 20))!,
            nonce: 1,
            initCode: Data(),
            callData: Data([0xb6, 0x1d, 0x27, 0xf6]),
            verificationGasLimit: 100_000,
            callGasLimit: 200_000,
            preVerificationGas: 50_000,
            maxPriorityFeePerGas: 30_000_000_000,
            maxFeePerGas: 60_000_000_000,
            paymasterAndData: Data(),
            signature: Data(repeating: 0, count: 65)
        )
    }

    /// Identical to `makeSampleOp()` today, but called out as a separate
    /// helper so the wire-compatibility vector test can't be accidentally
    /// invalidated by an unrelated tweak to the "sample" op used in the
    /// structural tests above.
    private func makeReferenceVectorOp() -> PackedUserOperation {
        PackedUserOperation(
            sender: EthereumAddress(Data(repeating: 0xa1, count: 20))!,
            nonce: 1,
            initCode: Data(),
            callData: Data([0xb6, 0x1d, 0x27, 0xf6]),
            verificationGasLimit: 100_000,
            callGasLimit: 200_000,
            preVerificationGas: 50_000,
            maxPriorityFeePerGas: 30_000_000_000,
            maxFeePerGas: 60_000_000_000,
            paymasterAndData: Data(),
            signature: Data(repeating: 0, count: 65)
        )
    }
}
