import XCTest
import BigInt
import CryptoSwift
import Web3Core
@testable import Web3Swift

final class SigningPinTests: XCTestCase {

    // MARK: - Domain separator

    func testDomainSeparatorKnownOutput() {
        let separator = ERC2612.computeDomainSeparator(
            name: "THAT Token",
            version: "1",
            chainId: BigUInt(137),
            verifyingContract: EthereumAddress("0xd2E57e7019a8faea8b3E4a3738Ee5B269975008A")!
        )
        XCTAssertEqual(separator.count, 32)
        // Pin: if v-normalisation or encoding changes, this breaks.
        let expected = computeExpectedDomainSeparator()
        XCTAssertEqual(separator, expected, "Domain separator diverged from pinned value")
    }

    private func computeExpectedDomainSeparator() -> Data {
        let typeHash = Data("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)".utf8).sha3(.keccak256)
        let nameHash = Data("THAT Token".utf8).sha3(.keccak256)
        let versionHash = Data("1".utf8).sha3(.keccak256)

        var encoded = Data()
        encoded += typeHash
        encoded += nameHash
        encoded += versionHash
        encoded += BigUInt(137).uint256BE
        encoded += Data(repeating: 0, count: 12) + EthereumAddress("0xd2E57e7019a8faea8b3E4a3738Ee5B269975008A")!.addressData
        return encoded.sha3(.keccak256)
    }

    // MARK: - Client signature digest

    func testClientSigDigestKnownOutput() {
        let user = EthereumAddress("0x1111111111111111111111111111111111111111")!
        let recipient = EthereumAddress("0x2222222222222222222222222222222222222222")!
        let amount = BigUInt("1000000000000000000")!   // 1e18
        let chainId = BigUInt(137)
        let contract = EthereumAddress("0xc55897D0285D855B2C56F202145d6FC101B1f7dC")!

        let digest = RewardsManager.encodeClientSigDigest(
            user: user, recipient: recipient,
            amount: amount, chainId: chainId, contract: contract
        )
        XCTAssertEqual(digest.count, 32)

        // Recompute independently to pin
        var packed = Data()
        packed.append(user.addressData)
        packed.append(recipient.addressData)
        packed.append(amount.uint256BE)
        packed.append(chainId.uint256BE)
        packed.append(contract.addressData)
        let expected = Data(packed.sha3(.keccak256))
        XCTAssertEqual(digest, expected, "clientSig digest diverged from pinned value")
    }

    func testClientSigRoundTrip() throws {
        let keystore = try EthereumKeystoreV3(password: "test")!
        let account = keystore.addresses![0]
        var privateKey = try keystore.UNSAFE_getPrivateKeyData(password: "test", account: account)
        defer { Data.zero(&privateKey) }

        let user = EthereumAddress("0x1111111111111111111111111111111111111111")!
        let recipient = EthereumAddress("0x2222222222222222222222222222222222222222")!
        let amount = BigUInt("1000000000000000000")!
        let chainId = BigUInt(137)
        let contract = EthereumAddress("0xc55897D0285D855B2C56F202145d6FC101B1f7dC")!

        let sig = try RewardsManager.signClientSig(
            privateKey: privateKey,
            user: user, recipient: recipient,
            amount: amount, chainId: chainId, contract: contract
        )
        XCTAssertEqual(sig.count, 65)
        XCTAssert(sig[64] == 27 || sig[64] == 28, "v must be 27 or 28, got \(sig[64])")
    }

    // MARK: - Recovery byte normalisation

    func testNormalizeRecoveryByte() {
        var sigV0 = Data(repeating: 0xAA, count: 64) + Data([0])
        Web3Signer.normalizeRecoveryByte(in: &sigV0)
        XCTAssertEqual(sigV0[64], 27)

        var sigV1 = Data(repeating: 0xBB, count: 64) + Data([1])
        Web3Signer.normalizeRecoveryByte(in: &sigV1)
        XCTAssertEqual(sigV1[64], 28)

        var sigV27 = Data(repeating: 0xCC, count: 64) + Data([27])
        Web3Signer.normalizeRecoveryByte(in: &sigV27)
        XCTAssertEqual(sigV27[64], 27, "Already-normalised v should be unchanged")

        var sigV28 = Data(repeating: 0xDD, count: 64) + Data([28])
        Web3Signer.normalizeRecoveryByte(in: &sigV28)
        XCTAssertEqual(sigV28[64], 28, "Already-normalised v should be unchanged")

        var shortSig = Data(repeating: 0xEE, count: 32)
        Web3Signer.normalizeRecoveryByte(in: &shortSig)
        XCTAssertEqual(shortSig.count, 32, "Non-65-byte data should be untouched")
    }

    // MARK: - uint256BE

    func testUint256BE() {
        XCTAssertEqual(BigUInt(0).uint256BE, Data(repeating: 0, count: 32))
        XCTAssertEqual(BigUInt(1).uint256BE, Data(repeating: 0, count: 31) + Data([1]))
        XCTAssertEqual(BigUInt(256).uint256BE, Data(repeating: 0, count: 30) + Data([1, 0]))

        let maxU256 = BigUInt(2).power(256) - 1
        XCTAssertEqual(maxU256.uint256BE, Data(repeating: 0xFF, count: 32))
    }
}
