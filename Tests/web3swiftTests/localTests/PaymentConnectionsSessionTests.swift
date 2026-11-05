//
//  PaymentConnectionsSessionTests.swift
//  localTests
//
//  PAYMENT-CONNECTIONS-PLAN.md T4 and N3, at the fork: a provider rides an injected session, else the
//  process's installed one, else a session of its own (today's, Android's); its credentials go on each request
//  and never on the session; the service's clients ride the installed session; the endpoint preference is one
//  the app's send ladder can read and write, and a preference that left the registered list is ignored; the
//  polling floor is a block's cadence. `.serialized`: the installed session and the service's endpoint
//  registry are process-wide, and every cell that touches them resets what it installed.
//

import BigInt
import Foundation
import Testing
import Web3Core
@testable import Web3Swift

/// A URLProtocol that records every request it saw and answers each with one JSON-RPC result.
final class RecordingRPCProtocol: URLProtocol {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var _seen: [URLRequest] = []
    nonisolated(unsafe) static var result = "\"0x10\""

    static var seen: [URLRequest] { lock.withLock { _seen } }
    static func reset() { lock.withLock { _seen = [] } }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}
    override func startLoading() {
        Self.lock.withLock { Self._seen.append(request) }
        let body = "{\"jsonrpc\":\"2.0\",\"id\":1,\"result\":\(Self.result)}"
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    static func session() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [RecordingRPCProtocol.self]
        return URLSession(configuration: configuration)
    }
}

@Suite("Web3HttpProvider and the installed session (N1, R-C5 — T4)", .serialized)
struct Web3HttpProviderSessionTests {
    static func url() -> URL { URL(string: "https://node-\(UUID().uuidString.lowercased()).example/v2/k")! }

    @Test("an injected session is the provider's; with nothing injected and nothing installed the provider keeps a session of its own, with the 15 s timeout")
    func injectedOrOwn() {
        Web3ClientService.resetInstalledSessionForTesting()
        let injected = URLSession(configuration: .ephemeral)
        let provider = Web3HttpProvider(url: Self.url(), network: .Polygon, session: injected)
        #expect(provider.session === injected)
        let own = Web3HttpProvider(url: Self.url(), network: .Polygon)
        #expect(own.session !== injected)
        #expect(own.session.configuration.timeoutIntervalForRequest == 15)
        #expect(Web3ClientService.providersWithOwnSession == 1, "the one provider that built its own")
        Web3ClientService.resetInstalledSessionForTesting()
    }

    @Test("an installed session is every provider's that injects none, and every client's the service creates; an injected one still wins")
    func installedSession() async throws {
        Web3ClientService.resetInstalledSessionForTesting()
        defer { Web3ClientService.resetInstalledSessionForTesting() }
        let pool = URLSession(configuration: .ephemeral)
        Web3ClientService.installSession(pool)
        #expect(Web3ClientService.installedSession === pool)
        #expect(Web3HttpProvider(url: Self.url(), network: .Polygon).session === pool)
        let injected = URLSession(configuration: .ephemeral)
        #expect(Web3HttpProvider(url: Self.url(), network: .Polygon, session: injected).session === injected)
        let endpoint = Self.url().absoluteString
        let client = try await Web3ClientService.shared.web3Client(for: .Polygon, endpoint: endpoint)
        #expect(client.provider.session === pool)
        #expect(Web3ClientService.providersWithOwnSession == 0, "nothing built its own once the pool was installed")
    }

    @Test("credentials ride each request as Authorization, and the session's configuration carries no header")
    func credentialsPerRequest() async throws {
        Web3ClientService.resetInstalledSessionForTesting()
        let session = RecordingRPCProtocol.session()
        let credentials = BasicAuthCredentials(username: "u", password: "p")
        let provider = Web3HttpProvider(url: Self.url(), network: .Polygon, credentials: credentials, session: session)
        #expect(session.configuration.httpAdditionalHeaders == nil)
        #expect(provider.requestHeaders == ["Authorization": credentials.authorizationHeader])
        #expect(Web3HttpProvider(url: Self.url(), network: .Polygon, session: session).requestHeaders.isEmpty)
        RecordingRPCProtocol.reset()
        let block = try await Web3(provider: provider).eth.blockNumber()
        #expect(block == 16)
        let request = try #require(RecordingRPCProtocol.seen.first)
        #expect(request.value(forHTTPHeaderField: "Authorization") == credentials.authorizationHeader)
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
    }

    // Lives here, not with the preference cells: it installs a session, and every cell that touches the
    // installed session must share ONE serialized suite — a second suite runs in parallel and would reset it
    // (which is exactly what happened on the first run).
    @Test("the fallback walk tries the preferred endpoint first, and one that left the list not at all")
    func fallbackWalkHonoursThePreference() async throws {
        Web3ClientService.resetInstalledSessionForTesting()
        defer { Web3ClientService.resetInstalledSessionForTesting() }
        Web3ClientService.installSession(RecordingRPCProtocol.session())
        let network = Web3ClientServicePreferenceTests.network(880_002)
        let a = Web3ClientServicePreferenceTests.endpoint("a"), b = Web3ClientServicePreferenceTests.endpoint("b")
        let service = Web3ClientService.shared
        await service.registerEndpoints([a, b], for: network)
        await service.setPreferredEndpoint(b, for: network)
        RecordingRPCProtocol.reset()
        let result = try await service.performWithRPCFallback(for: network) { web3 in try await web3.eth.blockNumber() }
        #expect(result.endpointUsed == b && result.result == 16)
        #expect(RecordingRPCProtocol.seen.map { $0.url?.host } == [URL(string: b)?.host])
        await service.setPreferredEndpoint(Web3ClientServicePreferenceTests.endpoint("gone"), for: network)
        RecordingRPCProtocol.reset()
        let again = try await service.performWithRPCFallback(for: network) { web3 in try await web3.eth.blockNumber() }
        #expect(again.endpointUsed == a, "the list's own order once the preference is stale")
        #expect(RecordingRPCProtocol.seen.map { $0.url?.host } == [URL(string: a)?.host])
    }

    // MARK: F-07 — a cancelled read stops the walk (RUNTIME-SCALE-AUDIT-FINDINGS.md F-07, N3)

    /// The real shape: the calling task is cancelled while the first endpoint's request is on the wire. URLSession
    /// stops the request and throws `.cancelled`; the walk used to take that for the endpoint's failure and ask the
    /// next two. Counted at the protocol: one request reached a node, and the second endpoint was never asked.
    @Test("a task cancelled mid-request asks no further endpoint, and the preference stays")
    func cancelledMidRequestStopsTheWalk() async throws {
        Web3ClientService.resetInstalledSessionForTesting()
        defer { Web3ClientService.resetInstalledSessionForTesting() }
        Web3ClientService.installSession(HangingRPCProtocol.session())
        HangingRPCProtocol.reset()
        let network = Web3ClientServicePreferenceTests.network(880_010)
        let a = Web3ClientServicePreferenceTests.endpoint("a"), b = Web3ClientServicePreferenceTests.endpoint("b"), c = Web3ClientServicePreferenceTests.endpoint("c")
        let service = Web3ClientService.shared
        await service.registerEndpoints([a, b, c], for: network)
        let read = Task { try await service.performWithRPCFallback(for: network) { web3 in try await web3.eth.blockNumber() } }
        // Bounded: the request reaches the protocol within milliseconds; 2 s of 10 ms polls is the ceiling.
        for _ in 0..<200 where HangingRPCProtocol.seen.isEmpty { try await Task.sleep(for: .milliseconds(10)) }
        #expect(HangingRPCProtocol.seen.map { $0.url?.host } == [URL(string: a)?.host], "the first endpoint is on the wire")
        read.cancel()
        let outcome = await read.result
        guard case .failure(let error) = outcome else { Issue.record("a cancelled read returned a result"); return }
        #expect(Web3ClientService.isCancellation(error) || (error as? URLError)?.code == .cancelled, "the cancellation goes back as it came: \(error)")
        // Long enough for a walk to have reached the second endpoint, had it continued.
        try await Task.sleep(for: .milliseconds(300))
        #expect(HangingRPCProtocol.seen.count == 1, "no fallback endpoint was asked after the cancel")
        #expect(await service.preferredEndpoint(for: network) == a, "a cancellation moves no preference")
    }

    /// Each cancellation shape, thrown by the read itself with the calling task NOT cancelled, stops the walk at one
    /// attempt; a timeout — an endpoint's failure — still walks on (the positive control).
    @Test("CancellationError and URLError.cancelled stop at one attempt; a timeout still walks to the next endpoint")
    func cancellationShapesStopTimeoutsWalk() async throws {
        Web3ClientService.resetInstalledSessionForTesting()
        defer { Web3ClientService.resetInstalledSessionForTesting() }
        Web3ClientService.installSession(RecordingRPCProtocol.session())
        let service = Web3ClientService.shared
        let cases: [(UInt, Error, Int)] = [
            (880_011, CancellationError(), 1),
            (880_012, URLError(.cancelled), 1),
            (880_013, URLError(.timedOut), 3),
        ]
        for (id, thrown, expectedAttempts) in cases {
            let network = Web3ClientServicePreferenceTests.network(id)
            let endpoints = ["a", "b", "c"].map(Web3ClientServicePreferenceTests.endpoint)
            await service.registerEndpoints(endpoints, for: network)
            let attempts = AttemptCounter()
            do {
                _ = try await service.performWithRPCFallback(for: network) { web3 -> Int in
                    attempts.note(web3.provider.url.host)
                    throw thrown
                }
                Issue.record("every attempt threw, so the walk must throw")
            } catch {
                #expect(ObjectIdentifier(type(of: error)) == ObjectIdentifier(type(of: thrown)), "the last error comes back: \(error)")
            }
            #expect(attempts.hosts.count == expectedAttempts, "\(thrown): \(attempts.hosts.count) attempts")
            #expect(attempts.hosts.first == URL(string: endpoints[0])?.host)
        }
    }

    /// The calling task is cancelled and the read fails with something that is not a cancellation (a server's 503
    /// that raced the cancel): the failure says nothing about the endpoint once nobody is waiting, so the walk stops.
    @Test("any failure once the calling task is cancelled stops the walk at one attempt")
    func failureAfterTaskCancelStops() async throws {
        Web3ClientService.resetInstalledSessionForTesting()
        defer { Web3ClientService.resetInstalledSessionForTesting() }
        Web3ClientService.installSession(RecordingRPCProtocol.session())
        let service = Web3ClientService.shared
        let network = Web3ClientServicePreferenceTests.network(880_014)
        let endpoints = ["a", "b", "c"].map(Web3ClientServicePreferenceTests.endpoint)
        await service.registerEndpoints(endpoints, for: network)
        let attempts = AttemptCounter()
        let gate = AsyncGate()
        let read = Task {
            try await service.performWithRPCFallback(for: network) { web3 -> Int in
                attempts.note(web3.provider.url.host)
                await gate.wait()
                throw Web3Error.serverError(code: 503)
            }
        }
        for _ in 0..<200 where attempts.hosts.isEmpty { try await Task.sleep(for: .milliseconds(10)) }
        read.cancel()
        await gate.open()
        _ = await read.result
        #expect(attempts.hosts.count == 1, "one attempt, then the walk stopped: \(attempts.hosts.count)")
    }
}

/// Attempts the walk made, by host.
final class AttemptCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var _hosts: [String?] = []
    var hosts: [String?] { lock.withLock { _hosts } }
    func note(_ host: String?) { lock.withLock { _hosts.append(host) } }
}

/// Holds a read until the test lets it go.
actor AsyncGate {
    private var isOpen = false
    private var waiters: [CheckedContinuation<Void, Never>] = []
    func wait() async {
        if isOpen { return }
        await withCheckedContinuation { waiters.append($0) }
    }
    func open() {
        isOpen = true
        waiters.forEach { $0.resume() }
        waiters = []
    }
}

/// A node that takes the request and never answers: the only way out is the caller's cancel, which URLSession turns
/// into `stopLoading` and a `.cancelled` failure.
final class HangingRPCProtocol: URLProtocol {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var _seen: [URLRequest] = []
    static var seen: [URLRequest] { lock.withLock { _seen } }
    static func reset() { lock.withLock { _seen = [] } }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() { Self.lock.withLock { Self._seen.append(request) } }
    override func stopLoading() {}

    static func session() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [HangingRPCProtocol.self]
        return URLSession(configuration: configuration)
    }
}

@Suite("Web3ClientService endpoint preference (N3)", .serialized)
struct Web3ClientServicePreferenceTests {
    /// A chain of this suite's own, so the process-wide registry never meets another suite's.
    static func network(_ id: UInt) -> Network {
        .Custom(CustomNetwork(id: BigUInt(id), name: "pref-\(id)", coinName: "P", symbol: "P", rpcOverride: nil, rpcURLs: [], decimals: 18))
    }
    static func endpoint(_ tag: String) -> String { "https://\(tag)-\(UUID().uuidString.lowercased()).example/v2/k" }

    @Test("the preference is the last success while it is registered, readable and writable through the service, and ignored once it leaves the list")
    func preference() async {
        let network = Self.network(880_001)
        let a = Self.endpoint("a"), b = Self.endpoint("b")
        let service = Web3ClientService.shared
        await service.registerEndpoints([a, b], for: network)
        #expect(await service.preferredEndpoint(for: network) == a)
        await service.setPreferredEndpoint(b, for: network)
        #expect(await service.preferredEndpoint(for: network) == b)
        await service.setPreferredEndpoint(Self.endpoint("gone"), for: network)
        #expect(await service.preferredEndpoint(for: network) == a, "a preference outside the list is ignored")
        await service.registerEndpoints([b, a], for: network)
        #expect(await service.preferredEndpoint(for: network) == b, "the first registered when nothing preferred is in the list")
    }

}

@Suite("TransactionPolling's floor (N4)")
struct TransactionPollingFloorTests {
    @Test("the floor is a block's cadence: a poll asking for one second runs at one second")
    func oneSecondFloor() async {
        #expect(TransactionPolling.minimumInterval == 1)
        // A port that refuses connections: every read errors, so the loop's waits between its three error
        // retries are the whole cost — two sleeps at the floor, about two seconds; four under the old floor.
        let provider = Web3HttpProvider(url: URL(string: "http://127.0.0.1:9")!, network: .Ethereum, session: URLSession(configuration: .ephemeral))
        let started = Date()
        do {
            _ = try await TransactionPolling.waitForTransaction(
                txHash: "0x" + String(repeating: "ab", count: 32), web3: Web3(provider: provider),
                pollingInterval: 1, timeout: 30, maxRetries: 20, maxErrorRetries: 3
            )
            Issue.record("a refused port cannot yield a receipt")
        } catch {
            let elapsed = Date().timeIntervalSince(started)
            #expect(elapsed >= 1.9 && elapsed < 3.5, "two one-second waits, measured \(elapsed)s")
        }
    }
}
