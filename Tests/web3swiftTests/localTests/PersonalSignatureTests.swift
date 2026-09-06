//
//  Created by Alex Vlasov.
//  Copyright © 2018 Alex Vlasov. All rights reserved.
//

import XCTest
import CryptoSwift
import BigInt
import Web3Core

@testable import Web3Swift

class PersonalSignatureTests: XCTestCase {

    /// ENS act debt A: the node-backed `web3.personal` round trip became the
    /// static signer + recover pair THAT actually calls — same keystore, same
    /// personal-message prefix, no `Web3.new(url)`. The contract half of the
    /// old file (`hashPersonalMessage` / `recoverSigner` on a deployed
    /// contract) needed a local node and was deleted with the other
    /// contract-wrapper suites.
    func testPersonalSignatureRoundTrip() throws {
        let keystore = try XCTUnwrap(try EthereumKeystoreV3(password: ""))
        let account = try XCTUnwrap(keystore.addresses?.first)
        let message = Data("Hello World".utf8)

        let signature = try XCTUnwrap(
            Web3Signer.signPersonalMessage(message, keystore: keystore, account: account, password: "")
        )
        XCTAssertEqual(signature.count, 65)
        XCTAssertNotNil(SECP256K1.unmarshalSignature(signatureData: signature))

        let signer = Utilities.personalECRecover(message, signature: signature)
        XCTAssertEqual(signer, account, "Failed to recover the personal-message signer")

        // A different message must not recover the same signer.
        let other = Utilities.personalECRecover(Data("Hello Worlds".utf8), signature: signature)
        XCTAssertNotEqual(other, account)
    }

    /// The prefix hash the signer commits to is the EIP-191 personal one.
    func testPersonalMessageHashIsPrefixed() throws {
        let message = Data("Hello World".utf8)
        let hash = try XCTUnwrap(Utilities.hashPersonalMessage(message))
        let prefixed = Data("\u{19}Ethereum Signed Message:\n\(message.count)".utf8) + message
        XCTAssertEqual(hash, prefixed.sha3(.keccak256))
    }
}
