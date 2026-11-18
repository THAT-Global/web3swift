//
//  WSReconnectCapTests.swift
//  localTests
//
//  The 4.8.0 performance pass, finding 16 (the fork half): a mined-transactions socket reconnects with a bounded
//  back-off. After `maxConsecutiveFailures` attempts in a row that never opened (a refused handshake — a rotated key's
//  401, a plan cap's 429 — completes the task and nothing else) the client stops and stays closed until an explicit
//  `connect()`, which begins afresh; an open puts the count back to zero, so a socket that worked and dropped
//  reconnects as it always did. The watches survive giving up and go on the next socket that opens.
//
//  No socket and no real time: the client's opener records each attempt and answers nil, the cells drive the attempt's
//  events (`socketDidOpen` / `socketDidEnd`, what the delegate proxy calls), and the back-off waits on a virtual clock
//  that either passes at once or holds until the cell advances it.
//

import Foundation
import Testing
@testable import Web3Swift

/// The back-off's clock. `holds == false`: every wait passes at once, its length recorded. `holds == true`: a wait
/// parks until `advance()` — whether or not its task was cancelled, so a cancelled wait's stand-down is the client's.
@MainActor
final class VirtualClock {
    var holds: Bool
    private(set) var waits: [TimeInterval] = []
    private var sleepers: [CheckedContinuation<Void, Never>] = []
    var parked: Int { sleepers.count }

    init(holds: Bool = false) { self.holds = holds }

    func sleep(_ seconds: TimeInterval) async {
        waits.append(seconds)
        guard holds else { return }
        await withCheckedContinuation { sleepers.append($0) }
    }

    /// Every parked wait passes.
    func advance() {
        let woken = sleepers
        sleepers = []
        woken.forEach { $0.resume() }
    }
}

/// The socket opener: records each attempt (and its delegate proxy) and opens nothing.
@MainActor
final class RecordingOpener {
    private(set) var attempts: [UInt64] = []
    private(set) var proxies: [MinedTxWSDelegateProxy] = []

    func open(_ url: URL, _ proxy: MinedTxWSDelegateProxy) -> (URLSession, URLSessionWebSocketTask)? {
        attempts.append(proxy.attempt ?? 0)
        proxies.append(proxy)
        return nil
    }
}

@MainActor
struct ReconnectHarness {
    static let wss = URL(string: "wss://127.0.0.1:9/ws")!

    let client: MinedTxWSClient
    let clock: VirtualClock
    let opener: RecordingOpener

    init(cap: Int = MinedTxWSClient.defaultMaxConsecutiveFailures, holds: Bool = false) {
        let clock = VirtualClock(holds: holds)
        let opener = RecordingOpener()
        self.clock = clock
        self.opener = opener
        self.client = MinedTxWSClient(
            chainId: 137, wssURL: Self.wss, maxConsecutiveFailures: cap,
            openSocket: { opener.open($0, $1) },
            sleep: { await clock.sleep($0) }
        )
    }

    var attempts: Int { opener.attempts.count }

    /// The attempt in flight is refused before it opens — its task completes, nothing else — and, on a clock that
    /// passes at once, the back-off's wait runs to its end (the next attempt, or none once the client gave up).
    func refuse() async {
        guard let attempt = client.currentAttempt else {
            Issue.record("no attempt in flight to refuse")
            return
        }
        client.socketDidEnd(attempt: attempt)
        await client.reconnectTask?.value
    }

    /// The attempt in flight opens.
    func open() {
        guard let attempt = client.currentAttempt else {
            Issue.record("no attempt in flight to open")
            return
        }
        client.socketDidOpen(attempt: attempt)
    }

    /// Lets the main actor run what is queued until `done`, a bounded number of turns: never a hang.
    func settle(_ done: () -> Bool) async -> Bool {
        for _ in 0..<1_000 {
            if done() { return true }
            await Task.yield()
        }
        return done()
    }
}

@MainActor
@Suite("MinedTxWSClient bounded reconnect (4.8.0 perf finding 16)")
struct MinedTxWSReconnectCapTests {

    @Test("a refusing endpoint gets exactly `cap` attempts — the waits 1, 2, 4, 8 s at the default — then none, and the client has given up", arguments: [1, 3, 5])
    func refusalsStopAtTheCap(cap: Int) async {
        let h = ReconnectHarness(cap: cap)
        h.client.connect()
        #expect(h.attempts == 1, "the explicit start's attempt")
        for _ in 0..<cap { await h.refuse() }
        #expect(h.attempts == cap, "attempts: \(h.opener.attempts)")
        #expect(h.clock.waits == Array([1.0, 2, 4, 8, 16].prefix(cap - 1)), "waits: \(h.clock.waits)")
        #expect(h.client.hasGivenUp)
        #expect(h.client.reconnectTask == nil, "no wait pending once it gave up")
        #expect(h.client.currentAttempt == nil, "no socket in flight")
        // Nothing further, however long the main actor runs.
        _ = await h.settle { false }
        #expect(h.attempts == cap)
        h.client.disconnect()
    }

    @Test("an open before the cap puts the count back to zero: a drop reconnects at 1 s, and its refusals get the full cap, waits 1, 2, 4, 8, 16 s")
    func anOpenResetsTheCount() async {
        let h = ReconnectHarness()
        h.client.connect()
        for _ in 0..<3 { await h.refuse() }
        #expect(h.attempts == 4 && h.client.consecutiveFailures == 3 && !h.client.hasGivenUp)
        h.open()
        #expect(h.client.consecutiveFailures == 0)
        // The socket worked and dropped: a drop is not a failure, and the back-off starts again from 1 s.
        await h.refuse()
        #expect(h.attempts == 5 && h.client.consecutiveFailures == 0)
        for _ in 0..<5 { await h.refuse() }
        #expect(h.attempts == 9, "the drop's reconnects: five more attempts — \(h.opener.attempts)")
        #expect(h.clock.waits == [1, 2, 4, 1, 2, 4, 8, 16], "waits: \(h.clock.waits)")
        #expect(h.client.hasGivenUp)
        h.client.disconnect()
    }

    @Test("connect() after giving up attempts again at once, once, with the count and the back-off reset")
    func connectAfterGivingUpBeginsAgain() async {
        let h = ReconnectHarness()
        h.client.connect()
        for _ in 0..<5 { await h.refuse() }
        #expect(h.client.hasGivenUp && h.attempts == 5)

        h.client.connect()
        #expect(h.attempts == 6, "one attempt, now")
        #expect(!h.client.hasGivenUp && h.client.consecutiveFailures == 0 && h.client.reconnectTask == nil)
        h.client.connect()
        #expect(h.attempts == 6, "a second start while that attempt is in flight opens nothing")

        let waitsBefore = h.clock.waits.count
        for _ in 0..<5 { await h.refuse() }
        #expect(h.attempts == 10, "a fresh sequence of five: \(h.opener.attempts)")
        #expect(Array(h.clock.waits.dropFirst(waitsBefore)) == [1, 2, 4, 8], "the back-off began again at 1 s: \(h.clock.waits)")
        #expect(h.client.hasGivenUp)
        h.client.disconnect()
    }

    @Test("connect() while a back-off wait is parked makes one attempt, and the parked wait stands down when it wakes")
    func connectDuringBackOffDoesNotDoubleConnect() async {
        let h = ReconnectHarness(holds: true)
        h.client.connect()
        h.client.socketDidEnd(attempt: 1)
        let pending = h.client.reconnectTask
        #expect(pending != nil)
        #expect(await h.settle { h.clock.parked == 1 }, "the back-off's wait is parked")

        h.client.connect()
        #expect(h.attempts == 2 && h.client.currentAttempt == 2, "the start's attempt, at once")
        #expect(h.client.reconnectTask == nil)
        h.clock.advance()
        await pending?.value
        #expect(h.attempts == 2, "the woken wait opened nothing: \(h.opener.attempts)")
        #expect(h.client.currentAttempt == 2)

        // Its count and back-off were fresh: the next refusal waits 1 s again.
        h.client.socketDidEnd(attempt: 2)
        #expect(await h.settle { h.clock.parked == 1 })
        #expect(h.clock.waits == [1, 1], "waits: \(h.clock.waits)")
        h.client.disconnect()
        h.clock.advance()
    }

    @Test("disconnect() during a back-off wait schedules nothing further, and gives the client no 'gave up' state")
    func disconnectDuringBackOffSchedulesNothing() async {
        let h = ReconnectHarness(holds: true)
        h.client.connect()
        h.client.socketDidEnd(attempt: 1)
        let pending = h.client.reconnectTask
        #expect(await h.settle { h.clock.parked == 1 })

        h.client.disconnect()
        #expect(h.client.reconnectTask == nil)
        h.clock.advance()
        await pending?.value
        #expect(h.attempts == 1, "the woken wait opened nothing: \(h.opener.attempts)")
        #expect(!h.client.hasGivenUp && h.client.currentAttempt == nil)
        // The ended attempt's late events reach nothing.
        h.client.socketDidEnd(attempt: 1)
        h.client.socketDidOpen(attempt: 1)
        #expect(h.client.reconnectTask == nil && h.attempts == 1)
        #expect(h.client.subscribeLogs(address: "0xE", topics: [nil]) == nil, "not open: the filter is recorded, nothing sent")
    }

    @Test("an attempt ends once: a dropped socket's later events (its close's completion, the failed receive) and an old socket's open are stale")
    func anAttemptEndsOnce() async {
        let h = ReconnectHarness()
        h.client.connect()
        h.open()
        await h.refuse()   // the drop: the close
        #expect(h.attempts == 2 && h.client.currentAttempt == 2)
        // The same socket's completion arrives after its close, as URLSession sends it.
        h.client.socketDidEnd(attempt: 1)
        #expect(h.client.reconnectTask == nil && h.client.currentAttempt == 2 && h.client.consecutiveFailures == 0)
        #expect(h.clock.waits == [1], "one reconnect for one drop: \(h.clock.waits)")
        h.client.socketDidOpen(attempt: 1)
        #expect(h.client.subscribeLogs(address: "0xE", topics: [nil]) == nil, "an old socket's open does not open the client")
        h.client.disconnect()
    }

    @Test("a refused handshake reaches the client through the task's completion, the one event URLSession sends for it")
    func refusedHandshakeArrivesAsCompletion() async throws {
        let h = ReconnectHarness()
        h.client.connect()
        let proxy = try #require(h.opener.proxies.first)
        // Never resumed: a task object to name, no request made.
        let task = URLSession.shared.dataTask(with: URL(string: "https://127.0.0.1:9/")!)
        proxy.urlSession(URLSession.shared, task: task, didCompleteWithError: URLError(.badServerResponse))
        #expect(await h.settle { h.attempts == 2 }, "the refusal counted and the back-off's attempt followed: \(h.opener.attempts)")
        #expect(h.client.consecutiveFailures == 1)

        // A proxy made outside the client answers nothing to a completion, as before.
        let unchecked = MinedTxWSDelegateProxy(owner: h.client)
        unchecked.urlSession(URLSession.shared, task: task, didCompleteWithError: URLError(.badServerResponse))
        _ = await h.settle { false }
        #expect(h.attempts == 2 && h.client.consecutiveFailures == 1)
        h.client.disconnect()
    }

    @Test("the subscriptions survive giving up and go on the next socket that opens")
    func subscriptionsSurviveGivingUp() async throws {
        let h = ReconnectHarness()
        #expect(h.client.subscribeMinedTransactions(filters: [.from("0xAbC")]) == nil, "not open: recorded")
        #expect(h.client.subscribeLogs(address: "0xEntry", topics: [["0xsig"], nil, ["0xsender"]]) == nil)
        h.client.connect()
        for _ in 0..<5 { await h.refuse() }
        #expect(h.client.hasGivenUp)

        h.client.connect()
        h.open()
        #expect(Set(h.client.pendingSubscribe.values) == [.minedTransactions, .logs], "both kinds asked again")
        for (id, kind) in h.client.pendingSubscribe {
            let subId = kind == .logs ? "0xL" : "0xM"
            h.client.handle(Data(#"{"jsonrpc":"2.0","id":\#(id),"result":"\#(subId)"}"#.utf8))
        }
        #expect(h.client.currentSubscriptionId == "0xM" && h.client.subscriptionId(for: .logs) == "0xL")
        h.client.disconnect()
    }
}

@MainActor
@Suite("ChainLiveCenter over a socket that gave up (4.8.0 perf finding 16)")
struct ChainLiveCenterReconnectCapTests {
    static let watch = ChainLiveCenter.LogWatch(address: "0xEntry", topics: [["0xSig"], nil, ["0xSender"]])

    /// What the arming does (`ReceiptWatcher.arm`): the sender's watch, the log watch, a start.
    static func arm(_ center: ChainLiveCenter) {
        center.addAddressWatch(from: "0xAbC")
        center.setLogWatch(watch)
        center.start()
    }

    @Test("a started center's start — an arming, a wait — begins again on a socket that gave up, with its watches; on one waiting out its back-off it does nothing")
    func startRevivesAGivenUpSocket() async {
        let h = ReconnectHarness()
        let center = ChainLiveCenter(client: h.client)
        defer { center.stop() }
        Self.arm(center)
        #expect(h.attempts == 1, "the arming's starts open one socket")

        h.client.socketDidEnd(attempt: 1)
        let pending = h.client.reconnectTask
        Self.arm(center)
        #expect(h.attempts == 1 && h.client.reconnectTask != nil, "a start during the back-off leaves it be")
        await pending?.value
        #expect(h.attempts == 2)
        for _ in 0..<4 { await h.refuse() }
        #expect(center.socketHasGivenUp && h.attempts == 5)
        #expect(center.isWatching(from: "0xabc") && center.logWatch != nil, "giving up keeps the watches")

        Self.arm(center)
        #expect(h.attempts == 6, "the arming began again, once: \(h.opener.attempts)")
        #expect(!center.socketHasGivenUp)
        h.open()
        #expect(Set(h.client.pendingSubscribe.values) == [.minedTransactions, .logs], "both watches on the new socket")
    }

    @Test("a wait's start begins again on a socket that gave up")
    func waitRevivesAGivenUpSocket() async {
        let h = ReconnectHarness(cap: 1)
        let center = ChainLiveCenter(client: h.client)
        defer { center.stop() }
        center.start()
        await h.refuse()
        #expect(center.socketHasGivenUp && h.attempts == 1)
        _ = await center.waitForLog(timeout: 0.05) { _ in true }
        #expect(h.attempts == 2 && !center.socketHasGivenUp)
    }

    @Test("resume on a center never suspended restarts only a socket that gave up; a suspension during the back-off schedules nothing, and resume begins afresh")
    func resumeAndSuspend() async {
        let h = ReconnectHarness()
        let center = ChainLiveCenter(client: h.client)
        defer { center.stop() }
        Self.arm(center)
        center.resume()
        #expect(h.attempts == 1, "an up (in-flight) socket is left as it is")
        for _ in 0..<5 { await h.refuse() }
        #expect(center.socketHasGivenUp)
        center.resume()
        #expect(h.attempts == 6 && !center.socketHasGivenUp, "inactive → active: the socket that gave up begins again")

        h.client.socketDidEnd(attempt: 6)
        let pending = h.client.reconnectTask
        center.suspend()
        await pending?.value
        #expect(h.attempts == 6 && h.client.reconnectTask == nil, "suspended during the back-off: nothing further")
        #expect(center.isWatching(from: "0xabc") && center.logWatch != nil)

        center.resume()
        #expect(h.attempts == 7 && h.client.consecutiveFailures == 0, "back to the foreground: a fresh start")
        await h.refuse()
        #expect(h.clock.waits.last == 1, "from a 1 s wait: \(h.clock.waits)")
    }
}
