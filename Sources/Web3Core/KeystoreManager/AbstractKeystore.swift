//
//  Created by Alex Vlasov.
//  Copyright © 2018 Alex Vlasov. All rights reserved.
//

import Foundation

// Sendable so concrete classes (KeystoreManager, EthereumKeystoreV3,
// BIP32Keystore, PlainKeystore) can be threaded into nonisolated
// signing functions from @MainActor-isolated callers without the
// "sending non-Sendable" trap. The protocol surface is read-only at
// runtime — loading mutations happen at construction and are not
// concurrent with signing — so the concrete classes adopt
// `@unchecked Sendable` to vouch for that invariant.
public protocol AbstractKeystore: Sendable {
    var addresses: [EthereumAddress]? { get }
    var isHDKeystore: Bool { get }
    func UNSAFE_getPrivateKeyData(password: String, account: EthereumAddress) throws -> Data
}

public enum AbstractKeystoreError: LocalizedError {
    case noEntropyError(_ additionalDescription: String? = nil)
    case keyDerivationError(_ additionalDescription: String? = nil)
    case aesError(_ additionalDescription: String? = nil)
    case invalidAccountError(_ additionalDescription: String? = nil)
    case invalidPasswordError
    case encryptionError(_ additionalDescription: String? = nil)
    
    public var errorDescription: String? {
        var errorMessage: [String?]
        switch self {
            case .noEntropyError(let additionalDescription):
                errorMessage = ["Entropy error (e.g. failed to generate a random array of bytes).", additionalDescription]
            case .keyDerivationError(let additionalDescription):
                errorMessage = ["Key derivation error.", additionalDescription]
            case .aesError(let additionalDescription):
                errorMessage = ["AES error.", additionalDescription]
            case .invalidAccountError(let additionalDescription):
                errorMessage = ["Invalid account error.", additionalDescription]
            case .invalidPasswordError:
                errorMessage = ["Invalid password error."]
            case .encryptionError(let additionalDescription):
                errorMessage = ["Encryption error.", additionalDescription]
        }
        return errorMessage.compactMap { $0 }.joined(separator: " ")
    }
}
