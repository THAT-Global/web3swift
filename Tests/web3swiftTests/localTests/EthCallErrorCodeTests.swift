//
//  EthCallErrorCodeTests.swift
//  localTests
//
//  that-ios V440-CHECKPOINT-PROGRAMME.md A-01 (from A-12c's review, reading 6). An `eth_call` answered with a JSON-RPC
//  error whose code `JsonRpcErrorCode` does not classify reached `checkError`, which handed back revert data if it found
//  any and otherwise threw its fixed "…Transaction reverted without a reason string" wording with the CODE DROPPED — so a
//  provider's 429 answered inside an HTTP 200 reached every caller as the contract's revert. The wording is code 3's
//  alone now; any other unclassified code is rethrown as `rpcError`, its code kept. Nothing else is classified
//  differently: code 3 with or without data, and every other method, answer as before.
//
//  And the endpoint as the fallback walk logs it: its host alone (A-01), never the key its path or query carries.
//
//  Every node here is a script at a host of the cell's own; nothing reaches a network.
//

import Foundation
import Testing
import Web3Core
@testable import Web3Swift

/// A node the cell scripts at a host of its own: every request is answered with the JSON-RPC `error` member given, in an
/// HTTP 200, as a provider answers a call it refused.
final class ErrorBodyNodeProtocol: URLProtocol {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var errors: [String: String] = [:]

    /// A client over a node at a fresh host whose every answer is `error` (the JSON of the `error` member).
    static func client(answering error: String) -> (web3: Web3, host: String) {
        let host = "node-\(UUID().uuidString.lowercased()).a01.test"
        lock.withLock { errors[host] = error }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ErrorBodyNodeProtocol.self]
        let provider = Web3HttpProvider(url: URL(string: "https://\(host)/rpc")!, network: .Polygon, session: URLSession(configuration: configuration))
        return (Web3(provider: provider), host)
    }

    static func retire(_ host: String) { _ = lock.withLock { errors.removeValue(forKey: host) } }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}
    override func startLoading() {
        guard let error = Self.lock.withLock({ Self.errors[request.url?.host ?? ""] }) else {
            return client!.urlProtocol(self, didFailWithError: URLError(.cannotFindHost))
        }
        let body = "{\"jsonrpc\":\"2.0\",\"id\":1,\"error\":\(error)}"
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
}

@Suite("A-01 — an eth_call's JSON-RPC error keeps its code unless it is code 3's revert (that-ios V440-CHECKPOINT-PROGRAMME.md A-01)")
struct EthCallErrorCodeTests {
    static let revertWithoutDataWords = "Error data decoding failed: missing revert data in exception; Transaction reverted without a reason string."

    /// What an `eth_call` over a node answering `error` throws — nil when it returned.
    static func callError(_ error: String) async -> (thrown: Error?, returned: Data?) {
        let (web3, host) = ErrorBodyNodeProtocol.client(answering: error)
        defer { ErrorBodyNodeProtocol.retire(host) }
        let to = EthereumAddress("0x000000000000000000000000000000000000a001")!
        do {
            return (nil, try await web3.eth.callTransaction(CodableTransaction(to: to, value: 0, data: Data([0x01, 0x02, 0x03, 0x04]))))
        } catch {
            return (error, nil)
        }
    }

    @Test("a code the vendor does not classify — Alchemy's 429 answered inside a 200, a provider's own code — is rethrown as rpcError with its code and message (RED at f37519f7: the revert wording, the code dropped)")
    func anUnclassifiedCodeKeepsItsCode() async {
        let rows = [
            (429, "Your app has exceeded its compute units per second capacity."),
            (1, "gateway refused the request"),
        ]
        for (code, message) in rows {
            let (thrown, returned) = await Self.callError("{\"code\":\(code),\"message\":\"\(message)\"}")
            #expect(returned == nil, "\(code)")
            guard case .rpcError(let rpc)? = thrown as? Web3Error else {
                Issue.record("\(code): not rpcError: \(String(describing: thrown))")
                continue
            }
            #expect(rpc.code == code)
            #expect(rpc.message == message)
        }
    }

    @Test("code 3 without data is the revert wording, as before — a revert that brought nothing to hand back")
    func codeThreeWithoutDataIsTheRevertWording() async {
        let (thrown, _) = await Self.callError("{\"code\":3,\"message\":\"execution reverted\"}")
        guard case .nodeError(let words)? = thrown as? Web3Error else {
            Issue.record("not nodeError: \(String(describing: thrown))")
            return
        }
        #expect(words == Self.revertWithoutDataWords)
    }

    @Test("code 3 with its revert data hands the data back as the call's answer, as before")
    func codeThreeWithDataHandsItBack() async {
        let data = "0x08c379a0" + String(repeating: "0", count: 62) + "20" + String(repeating: "0", count: 64)
        let (thrown, returned) = await Self.callError("{\"code\":3,\"message\":\"execution reverted\",\"data\":\"\(data)\"}")
        #expect(thrown == nil, "\(String(describing: thrown))")
        #expect(returned == Data.fromHex(data))
    }

    @Test("another method's unclassified error is unchanged: eth_estimateGas's 429 is still the node error with the node's words")
    func anotherMethodIsUnchanged() async {
        let message = "Your app has exceeded its compute units per second capacity."
        let (web3, host) = ErrorBodyNodeProtocol.client(answering: "{\"code\":429,\"message\":\"\(message)\"}")
        defer { ErrorBodyNodeProtocol.retire(host) }
        let transaction = CodableTransaction(to: EthereumAddress("0x000000000000000000000000000000000000a001")!, value: 0, data: Data())
        do {
            _ = try await web3.eth.estimateGas(for: transaction)
            Issue.record("the estimate returned")
        } catch {
            guard case .nodeError(let words)? = error as? Web3Error else {
                Issue.record("not nodeError: \(error)")
                return
            }
            #expect(words == message)
        }
    }
}

@Suite("A-01 — the fallback walk logs an endpoint by its host, never its key (that-ios V440-CHECKPOINT-PROGRAMME.md A-01)")
struct EndpointLogLabelTests {
    /// Synthetic: no provider issued it.
    static let key = "A01w3SynthKey9f8e7d6c5b4a3Z2Y1X"

    @Test("a key in the path, a key in the query, a socket: the label is the host alone; an endpoint that does not parse names no host")
    func theLabelIsTheHost() {
        let rows = [
            ("https://polygon-mainnet.g.alchemy.com/v2/\(Self.key)", "polygon-mainnet.g.alchemy.com"),
            ("https://site1.moralis-nodes.com/polygon/\(Self.key)", "site1.moralis-nodes.com"),
            ("https://explorer.example/api?module=proxy&apikey=\(Self.key)", "explorer.example"),
            ("wss://polygon-mainnet.g.alchemy.com/v2/\(Self.key)", "polygon-mainnet.g.alchemy.com"),
            ("not an endpoint", "<no host>"),
        ]
        for (index, (endpoint, host)) in rows.enumerated() {
            let label = Web3ClientService.logLabel(endpoint)
            let keys = label.components(separatedBy: Self.key).count - 1
            #expect(keys == 0, "row \(index)")
            #expect(label == host, "row \(index)")
        }
    }
}
