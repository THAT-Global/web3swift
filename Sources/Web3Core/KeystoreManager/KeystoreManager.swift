//
//  Created by Alex Vlasov.
//  Copyright © 2018 Alex Vlasov. All rights reserved.
//

import Foundation

// `@unchecked` because the internal `_keystores` / `_bip32keystores` /
// `_plainKeystores` arrays are `var` — they're appended-to during disk
// load (`pathToKeystores`-bearing inits + `KeystoreV3-loaded` callers).
// In actual use across this app the manager is loaded once and read
// thereafter (private-key derivation, address listing, EIP-712
// signing). No concurrent write path mutates these arrays. Marking
// Sendable lets MainActor-isolated callers pass the keystore into
// nonisolated package functions (e.g. `ERC2612.signPermit`,
// `TransactionExecutor.resolveAndSignTransaction`) without copying.
extension KeystoreManager: @unchecked Sendable {}

public class KeystoreManager: AbstractKeystore {
    public var isHDKeystore: Bool = false
    
    public var addresses: [EthereumAddress]? {
        var result: [EthereumAddress] = []
        
        for keystore in _keystores {
            if let key = keystore.addresses?.first, key.isValid {
                result.append(key)
            }
        }
        for keystore in _bip32keystores {
            guard let allAddresses = keystore.addresses else { continue }
            for addr in allAddresses where addr.isValid {
                result.append(addr)
            }
        }
        for keystore in _plainKeystores {
            if let key = keystore.addresses?.first, key.isValid {
                result.append(key)
            }
        }
        return result
    }
    
    public func UNSAFE_getPrivateKeyData(password: String, account: EthereumAddress) throws -> Data {
        guard let keystore = walletForAddress(account) else {
            throw AbstractKeystoreError.invalidAccountError(
                "KeystoreManager: no keystore/wallet found for given address. Address `\(account.address)`."
            )
        }
        return try keystore.UNSAFE_getPrivateKeyData(password: password, account: account)
    }
    
    public var path: String
    
    public func walletForAddress(_ address: EthereumAddress) -> AbstractKeystore? {
        for keystore in _keystores {
            if let key = keystore.addresses?.first, key == address && key.isValid {
                return keystore
            }
        }
        for keystore in _bip32keystores {
            guard let allAddresses = keystore.addresses else { continue }
            for addr in allAddresses where addr == address && addr.isValid {
                return keystore
            }
        }
        for keystore in _plainKeystores {
            if let key = keystore.addresses?.first, key == address && key.isValid {
                return keystore
            }
        }
        return nil
    }
    
    var _keystores: [EthereumKeystoreV3] = []
    var _bip32keystores: [BIP32Keystore] = []
    var _plainKeystores: [PlainKeystore] = []
    
    public var keystores: [EthereumKeystoreV3] { _keystores }
    public var bip32keystores: [BIP32Keystore] { _bip32keystores }
    public var plainKeystores: [PlainKeystore] { _plainKeystores }
    
    public init(_ keystores: [EthereumKeystoreV3]) {
        self.isHDKeystore = false
        self._keystores = keystores
        self.path = ""
    }
    
    public init(_ keystores: [BIP32Keystore]) {
        self.isHDKeystore = true
        self._bip32keystores = keystores
        self.path = "bip32"
    }
    
    public init(_ keystores: [PlainKeystore]) {
        self.isHDKeystore = false
        self._plainKeystores = keystores
        self.path = "plain"
    }
    
    // Make this fileprivate so the registry can call it
    internal init?(_ path: String, scanForHDwallets: Bool = false, suffix: String? = nil) throws {
        if scanForHDwallets {
            self.isHDKeystore = true
        }
        self.path = path
        
        let fileManager = FileManager.default
        var isDir: ObjCBool = false
        var exists = fileManager.fileExists(atPath: path, isDirectory: &isDir)
        if !exists && !isDir.boolValue {
            try fileManager.createDirectory(atPath: path, withIntermediateDirectories: true, attributes: nil)
            exists = fileManager.fileExists(atPath: path, isDirectory: &isDir)
        }
        if !isDir.boolValue {
            return nil
        }
        
        let allFiles = try fileManager.contentsOfDirectory(atPath: path)
        
        func loadFile(_ file: String) {
            var filePath = path
            if !path.hasSuffix("/") {
                filePath += "/"
            }
            filePath += file
            guard let content = fileManager.contents(atPath: filePath) else { return }
            
            if !scanForHDwallets {
                guard let keystore = EthereumKeystoreV3(content) else { return }
                _keystores.append(keystore)
            } else {
                guard let bipkeystore = BIP32Keystore(content) else { return }
                _bip32keystores.append(bipkeystore)
            }
        }
        
        if let suffix {
            for file in allFiles where file.hasSuffix(suffix) {
                loadFile(file)
            }
        } else {
            for file in allFiles {
                loadFile(file)
            }
        }
    }
}
