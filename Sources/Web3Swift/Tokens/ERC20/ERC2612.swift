//
//  ERC2612.swift
//  web3swift
//
//  EIP-2612 gasless permit: support detection, domain reads,
//  domain separator computation, typed-data construction, and signing.
//

import BigInt
import CryptoSwift
import Foundation
import Web3Core

public enum ERC2612 {

    private static let permitReadABI = """
    [
      {"constant":true,"inputs":[{"name":"owner","type":"address"}],"name":"nonces","outputs":[{"name":"","type":"uint256"}],"type":"function"},
      {"constant":true,"inputs":[],"name":"DOMAIN_SEPARATOR","outputs":[{"name":"","type":"bytes32"}],"type":"function"},
      {"constant":true,"inputs":[],"name":"name","outputs":[{"name":"","type":"string"}],"type":"function"},
      {"constant":true,"inputs":[],"name":"version","outputs":[{"name":"","type":"string"}],"type":"function"}
    ]
    """

    public struct DomainInfo: Sendable {
        public let name: String
        public let version: String?
        public let nonce: BigUInt

        public init(name: String, version: String?, nonce: BigUInt) {
            self.name = name
            self.version = version
            self.nonce = nonce
        }
    }

    public struct PermitSignature: Sendable {
        public let v: UInt8
        public let r: Data
        public let s: Data
        public let deadline: BigUInt
        public let nonce: BigUInt

        public init(v: UInt8, r: Data, s: Data, deadline: BigUInt, nonce: BigUInt) {
            self.v = v
            self.r = r
            self.s = s
            self.deadline = deadline
            self.nonce = nonce
        }
    }

    // MARK: - Support check

    public static func supports(
        token: EthereumAddress,
        owner: EthereumAddress,
        chainId: BigUInt,
        using web3: Web3
    ) async -> Bool {
        do {
            _ = try await readNonce(token: token, owner: owner, chainId: chainId, using: web3)
            return true
        } catch {
            return false
        }
    }

    // MARK: - Domain reads

    public static func readDomainInfo(
        token: EthereumAddress,
        owner: EthereumAddress,
        chainId: BigUInt,
        using web3: Web3
    ) async throws -> DomainInfo {
        let c = try contract(token: token, chainId: chainId)

        let nameTx = try c.createReadTransaction(method: "name")
        let nameData = try await web3.eth.callTransaction(nameTx)
        let nameOut = try c.abi.decodeReturnData("name", data: nameData)
        let name = (nameOut["0"] as? String) ?? ""

        var version: String? = nil
        do {
            let verTx = try c.createReadTransaction(method: "version")
            let verData = try await web3.eth.callTransaction(verTx)
            let verOut = try c.abi.decodeReturnData("version", data: verData)
            version = verOut["0"] as? String
        } catch {
            version = nil
        }

        let nonce = try await readNonce(token: token, owner: owner, chainId: chainId, using: web3)

        return DomainInfo(name: name, version: version, nonce: nonce)
    }

    // MARK: - Domain separator

    public static func computeDomainSeparator(
        name: String,
        version: String,
        chainId: BigUInt,
        verifyingContract: EthereumAddress
    ) -> Data {
        let typeHash = Data("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)".utf8).sha3(.keccak256)
        let nameHash = Data(name.utf8).sha3(.keccak256)
        let versionHash = Data(version.utf8).sha3(.keccak256)

        var encoded = Data()
        encoded += typeHash
        encoded += nameHash
        encoded += versionHash
        encoded += chainId.uint256BE
        encoded += Data(repeating: 0, count: 12) + verifyingContract.addressData

        return encoded.sha3(.keccak256)
    }

    // MARK: - Typed data JSON

    public static func buildPermitTypedDataJSON(
        name: String, version: String,
        chainId: BigUInt, verifyingContract: String,
        owner: String, spender: String,
        value: String, nonce: String, deadline: String
    ) throws -> String {
        let dict: [String: Any] = [
            "types": [
                "EIP712Domain": [
                    ["name": "name", "type": "string"],
                    ["name": "version", "type": "string"],
                    ["name": "chainId", "type": "uint256"],
                    ["name": "verifyingContract", "type": "address"]
                ],
                "Permit": [
                    ["name": "owner", "type": "address"],
                    ["name": "spender", "type": "address"],
                    ["name": "value", "type": "uint256"],
                    ["name": "nonce", "type": "uint256"],
                    ["name": "deadline", "type": "uint256"]
                ]
            ],
            "primaryType": "Permit",
            "domain": [
                "name": name, "version": version,
                "chainId": chainId.description,
                "verifyingContract": verifyingContract
            ],
            "message": [
                "owner": owner, "spender": spender,
                "value": value, "nonce": nonce, "deadline": deadline
            ]
        ]
        let data = try JSONSerialization.data(withJSONObject: dict, options: [.sortedKeys])
        guard let json = String(data: data, encoding: .utf8) else {
            throw Web3Error.dataError
        }
        return json
    }

    // MARK: - Full sign flow

    public static func signPermit(
        token: EthereumAddress,
        owner: EthereumAddress,
        spender: EthereumAddress,
        value: BigUInt,
        deadline: BigUInt,
        chainId: BigUInt,
        keystore: AbstractKeystore,
        password: String,
        using web3: Web3
    ) async throws -> PermitSignature? {
        guard await supports(token: token, owner: owner, chainId: chainId, using: web3) else {
            return nil
        }

        let info = try await readDomainInfo(token: token, owner: owner, chainId: chainId, using: web3)
        let usedVersion = info.version ?? "1"

        if let onChain = try? await readDomainSeparator(token: token, chainId: chainId, using: web3) {
            let computed = computeDomainSeparator(
                name: info.name, version: usedVersion,
                chainId: chainId, verifyingContract: token
            )
            if onChain != computed { return nil }
        }

        let typedJSON = try buildPermitTypedDataJSON(
            name: info.name, version: usedVersion,
            chainId: chainId, verifyingContract: token.address,
            owner: owner.address, spender: spender.address,
            value: value.description, nonce: info.nonce.description,
            deadline: deadline.description
        )

        let eip712 = try EIP712Parser.parse(typedJSON)
        var sig = try Web3Signer.signEIP712(
            eip712, keystore: keystore, account: owner, password: password
        )
        Web3Signer.normalizeRecoveryByte(in: &sig)
        guard sig.count == 65 else { return nil }

        return PermitSignature(
            v: sig[64],
            r: sig.subdata(in: 0..<32),
            s: sig.subdata(in: 32..<64),
            deadline: deadline,
            nonce: info.nonce
        )
    }

    // MARK: - Private

    private static func contract(token: EthereumAddress, chainId: BigUInt) throws -> Contract {
        try Contract(abiString: permitReadABI, address: token, chainId: chainId)
    }

    private static func readNonce(
        token: EthereumAddress, owner: EthereumAddress,
        chainId: BigUInt, using web3: Web3
    ) async throws -> BigUInt {
        let c = try contract(token: token, chainId: chainId)
        let tx = try c.createReadTransaction(method: "nonces", parameters: [owner])
        let data = try await web3.eth.callTransaction(tx)
        let out = try c.abi.decodeReturnData("nonces", data: data)
        guard let n = out["0"] as? BigUInt else { throw Web3Error.dataError }
        return n
    }

    private static func readDomainSeparator(
        token: EthereumAddress, chainId: BigUInt, using web3: Web3
    ) async throws -> Data {
        let c = try contract(token: token, chainId: chainId)
        let tx = try c.createReadTransaction(method: "DOMAIN_SEPARATOR")
        let data = try await web3.eth.callTransaction(tx)
        let out = try c.abi.decodeReturnData("DOMAIN_SEPARATOR", data: data)
        guard let sep = out["0"] as? Data else { throw Web3Error.dataError }
        return sep
    }

}
