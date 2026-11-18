//
//  WSReconnectCapTests.swift
//  localTests
//
//  The 4.8.0 performance pass, finding 16 (the fork half): a mined-transactions socket reconnects with a bounded
//  back-off. After `maxConsecutiveFailures` attempts in a row that ended before the node answered on them — a refused
//  handshake (a rotated key's 401, a plan cap's 429 completes the task and nothing else), or an upgrade accepted and
//  then closed — the client stops and stays closed until an explicit `connect()`, which begins afresh. The node's first
//  frame on an attempt puts the count back to zero, so a socket that served and dropped reconnects as it always did;
//  an open alone does not. The watches survive giving up and go on the next socket that opens.
//
//  No socket and no real time: the client's opener records each attempt and answers nil, the cells drive the attempt's
//  events (`socketDidOpen` / `socketDidReceive` / `socketDidEnd`, what the delegate proxy and the receive loop call),
//  and the back-off waits on a virtual clock that either passes at once or holds until the cell advances it.
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

    /// The attempt in flight ends — refused before it opened, or closed — and, on a clock that passes at once, the
    /// back-off's wait runs to its end (the next attempt, or none once the client gave up).
    func end() async {
        guard let attempt = client.currentAttempt else {
            Issue.record("no attempt in flight to end")
            return
        }
        client.socketDidEnd(attempt: attempt)
        await client.reconnectTask?.value
    }

    /// The attempt in flight is refused before it opens: its task completes, nothing else.
    func refuse() async { await end() }

    /// The attempt in flight opens.
    func open() {
        guard let attempt = client.currentAttempt else {
            Issue.record("no attempt in flight to open")
            return
        }
        client.socketDidOpen(attempt: attempt)
    }

    /// A reply that shows the node serving us.
    nonisolated static let resultFrame = #"{"jsonrpc":"2.0","id":0,"result":"0xS"}"#
    /// A gateway's error reply, the kind it sends before it closes.
    nonisolated static let errorFrame = #"{"jsonrpc":"2.0","id":1,"error":{"code":-32000,"message":"capacity exceeded"}}"#

    /// A text frame from the node on `attempt` (the one in flight when nil): what the receive loop delivers.
    func frame(_ text: String = ReconnectHarness.resultFrame, on attempt: UInt64? = nil) {
        deliver(.string(text), on: attempt)
    }

    func deliver(_ message: URLSessionWebSocketTask.Message, on attempt: UInt64? = nil) {
        guard let attempt = attempt ?? client.currentAttempt else {
            Issue.record("no attempt for the frame")
            return
        }
        client.socketDidReceive(.success(message), attempt: attempt)
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

    @Test("an endpoint that accepts the upgrade and then closes gets exactly `cap` attempts — waits 1, 2, 4, 8 s at the default — then none: an open is not an answer", arguments: [1, 3, 5])
    func acceptThenCloseStopsAtTheCap(cap: Int) async {
        let h = ReconnectHarness(cap: cap)
        h.client.connect()
        for _ in 0..<cap {
            h.open()
            await h.end()
        }
        #expect(h.attempts == cap, "attempts: \(h.opener.attempts)")
        #expect(h.clock.waits == Array([1.0, 2, 4, 8, 16].prefix(cap - 1)), "waits: \(h.clock.waits)")
        #expect(h.client.hasGivenUp && h.client.reconnectTask == nil && h.client.currentAttempt == nil)
        _ = await h.settle { false }
        #expect(h.attempts == cap)
        h.client.disconnect()
    }

    @Test("the node's first frame on an attempt puts the count back to zero, the open alone does not: a served socket's drop reconnects at 1 s, and its refusals get the full cap, waits 1, 2, 4, 8, 16 s")
    func aFrameResetsTheCount() async {
        let h = ReconnectHarness()
        h.client.connect()
        for _ in 0..<3 { await h.refuse() }
        #expect(h.attempts == 4 && h.client.consecutiveFailures == 3 && !h.client.hasGivenUp)
        h.open()
        #expect(h.client.consecutiveFailures == 3, "open, unanswered: the count stands")
        h.frame()
        #expect(h.client.consecutiveFailures == 0 && h.client.currentAttemptAnswered)
        // The socket served and dropped: a drop is not a failure, and the back-off starts again from 1 s.
        await h.end()
        #expect(h.attempts == 5 && h.client.consecutiveFailures == 0)
        for _ in 0..<5 { await h.refuse() }
        #expect(h.attempts == 9, "the drop's reconnects: five more attempts — \(h.opener.attempts)")
        #expect(h.clock.waits == [1, 2, 4, 1, 2, 4, 8, 16], "waits: \(h.clock.waits)")
        #expect(h.client.hasGivenUp)
        h.client.disconnect()
    }

    @Test("a socket that opens, is answered and drops, again and again, never gives up, and each reconnect waits 1 s")
    func servedSocketsNeverGiveUp() async {
        let h = ReconnectHarness()
        h.client.connect()
        for _ in 0..<12 {
            h.open()
            h.frame()
            await h.end()
        }
        #expect(h.attempts == 13, "attempts: \(h.opener.attempts)")
        #expect(h.clock.waits == Array(repeating: 1.0, count: 12), "waits: \(h.clock.waits)")
        #expect(!h.client.hasGivenUp && h.client.consecutiveFailures == 0)
        h.client.disconnect()
    }

    @Test("a socket open with nothing to subscribe — no request, so no frame — stays open and is not counted; only its end, unanswered, counts")
    func openWithoutAFrameIsNotCounted() async {
        let h = ReconnectHarness()
        h.client.connect()
        for _ in 0..<2 { await h.refuse() }
        h.open()
        #expect(h.client.pendingSubscribe.isEmpty, "nothing to subscribe: nothing asked, nothing to answer")
        _ = await h.settle { false }
        #expect(h.client.currentAttempt == 3 && h.client.reconnectTask == nil, "not torn down")
        #expect(h.client.consecutiveFailures == 2 && !h.client.currentAttemptAnswered, "neither counted nor reset")
        await h.end()
        #expect(h.client.consecutiveFailures == 3 && h.clock.waits == [1, 2, 4], "its unanswered end counted: \(h.clock.waits)")
        h.client.disconnect()
    }

    @Test("a frame on an attempt that has ended is stale: it does not reset the count")
    func aStaleFrameDoesNotResetTheCount() async {
        let h = ReconnectHarness()
        h.client.connect()
        h.open()
        await h.end()
        await h.refuse()
        #expect(h.attempts == 3 && h.client.consecutiveFailures == 2)
        h.frame(on: 1)
        h.frame(on: 2)
        #expect(h.client.consecutiveFailures == 2 && !h.client.currentAttemptAnswered)
        h.open()
        h.frame(on: 2)
        #expect(h.client.consecutiveFailures == 2 && !h.client.currentAttemptAnswered, "the open attempt is 3")
        await h.end()
        #expect(h.client.consecutiveFailures == 3 && h.clock.waits == [1, 2, 4], "waits: \(h.clock.waits)")
        h.client.disconnect()
    }

    @Test("an endpoint that replies with an error and then closes gets exactly `cap` attempts — waits 1, 2, 4, 8 s at the default — then none: an error is not an answer", arguments: [1, 3, 5])
    func errorThenCloseStopsAtTheCap(cap: Int) async {
        let h = ReconnectHarness(cap: cap)
        h.client.connect()
        for _ in 0..<cap {
            h.open()
            h.frame(ReconnectHarness.errorFrame)
            await h.end()
        }
        #expect(h.attempts == cap, "attempts: \(h.opener.attempts)")
        #expect(h.clock.waits == Array([1.0, 2, 4, 8, 16].prefix(cap - 1)), "waits: \(h.clock.waits)")
        #expect(h.client.hasGivenUp && h.client.reconnectTask == nil && h.client.currentAttempt == nil)
        _ = await h.settle { false }
        #expect(h.attempts == cap)
        h.client.disconnect()
    }

    @Test("an error reply leaves the attempt unanswered and its socket open; one kind's subscribe erring and the other's succeeding answers it — the drop reconnects at 1 s, count 0 — and each frame is dispatched as before")
    func errorThenResultOnTheSameAttemptAnswers() async throws {
        let h = ReconnectHarness()
        let delegate = RecordingWSDelegate()
        h.client.delegate = delegate
        _ = h.client.subscribeMinedTransactions(filters: [.from("0xAbC")])
        _ = h.client.subscribeLogs(address: "0xEntry", topics: [["0xsig"], nil, ["0xsender"]])
        h.client.connect()
        for _ in 0..<2 { await h.refuse() }
        h.open()
        #expect(h.client.currentAttempt == 3)
        let logsId = try #require(h.client.pendingSubscribe.first { $0.value == .logs }?.key)
        let minedId = try #require(h.client.pendingSubscribe.first { $0.value == .minedTransactions }?.key)

        h.frame(#"{"jsonrpc":"2.0","id":\#(logsId),"error":{"code":-32000,"message":"capacity exceeded"}}"#)
        #expect(!h.client.currentAttemptAnswered && h.client.consecutiveFailures == 2, "an error is no answer")
        #expect(h.client.currentAttempt == 3 && h.client.reconnectTask == nil, "and the socket is left open")
        h.frame(#"{"jsonrpc":"2.0","id":\#(minedId),"result":"0xM"}"#)
        #expect(h.client.currentAttemptAnswered && h.client.consecutiveFailures == 0, "the other kind's result answers")
        #expect(h.client.currentSubscriptionId == "0xM" && h.client.subscriptionId(for: .logs) == nil)

        #expect(delegate.messages.count == 2)
        if delegate.messages.count == 2 {
            guard case .raw = delegate.messages[0] else { Issue.record("the error reply: \(delegate.messages[0])"); return }
            guard case .subscribed(let kind, let rpcID, let subId) = delegate.messages[1] else { Issue.record("\(delegate.messages[1])"); return }
            #expect(kind == "alchemy_minedTransactions" && rpcID == minedId && subId == "0xM")
        }

        await h.end()
        #expect(h.attempts == 4 && h.client.consecutiveFailures == 0, "a drop, not a failure")
        #expect(h.clock.waits == [1, 2, 1], "the answer reset the back-off: \(h.clock.waits)")
        h.client.disconnect()
    }

    @Test("a frame that is not a JSON object — text, bytes, an array — answers nothing and is dispatched as before; a null `error` beside a result is no error")
    func aFrameThatIsNotJSONDoesNotAnswer() async {
        let h = ReconnectHarness()
        let delegate = RecordingWSDelegate()
        h.client.delegate = delegate
        h.client.connect()
        await h.refuse()
        h.open()
        h.frame("not json")
        h.deliver(.data(Data([0xff, 0x00, 0x13])))
        h.frame("[1,2]")
        #expect(!h.client.currentAttemptAnswered && h.client.consecutiveFailures == 1)
        let raw = delegate.messages.filter { if case .raw = $0 { return true }; return false }
        #expect(delegate.messages.count == 3 && raw.count == 3, "each to .raw, as before: \(delegate.messages)")
        await h.end()
        #expect(h.client.consecutiveFailures == 2 && h.clock.waits == [1, 2], "waits: \(h.clock.waits)")

        h.open()
        h.frame(#"{"jsonrpc":"1.0","id":7,"result":"0x1","error":null}"#)
        #expect(h.client.currentAttemptAnswered && h.client.consecutiveFailures == 0)
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

    @Test("an attempt ends once: a closed socket's later events (its close's completion, the failed receive) and an old socket's open are stale")
    func anAttemptEndsOnce() async {
        let h = ReconnectHarness()
        h.client.connect()
        h.open()
        await h.end()   // the close, unanswered: one failure
        #expect(h.attempts == 2 && h.client.currentAttempt == 2)
        // The same socket's completion and its failed receive arrive after its close, as URLSession sends them.
        h.client.socketDidEnd(attempt: 1)
        h.client.socketDidReceive(.failure(URLError(.networkConnectionLost)), attempt: 1)
        #expect(h.client.reconnectTask == nil && h.client.currentAttempt == 2 && h.client.consecutiveFailures == 1)
        #expect(h.clock.waits == [1], "one reconnect for one close: \(h.clock.waits)")
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

    @Test("a wait's start — for a log, for a mined hash — begins again on a socket that gave up")
    func waitRevivesAGivenUpSocket() async {
        let h = ReconnectHarness(cap: 1)
        let center = ChainLiveCenter(client: h.client)
        defer { center.stop() }
        center.start()
        await h.refuse()
        #expect(center.socketHasGivenUp && h.attempts == 1)
        _ = await center.waitForLog(timeout: 0.05) { _ in true }
        #expect(h.attempts == 2 && !center.socketHasGivenUp)
        await h.refuse()
        #expect(center.socketHasGivenUp)
        _ = await center.waitForMinedHash("0x" + String(repeating: "ab", count: 32), from: "0xAbC", timeout: 0.05)
        #expect(h.attempts == 3 && !center.socketHasGivenUp)
    }

    @Test("a center with no watches: its open socket asks nothing and is not counted; five unanswered closes in a row give up, and a watch added begins again")
    func idleCenterGivesUpAndAWatchRevivesIt() async throws {
        let h = ReconnectHarness()
        let center = ChainLiveCenter(client: h.client)
        defer { center.stop() }
        center.start()
        h.open()
        #expect(h.client.pendingSubscribe.isEmpty, "no watch: no request, no frame to come")
        _ = await h.settle { false }
        #expect(h.client.currentAttempt == 1 && h.client.consecutiveFailures == 0 && !center.socketHasGivenUp, "open and idle: left as it is")
        await h.end()
        for _ in 0..<4 {
            h.open()
            await h.end()
        }
        #expect(center.socketHasGivenUp && h.attempts == 5 && h.clock.waits == [1, 2, 4, 8], "waits: \(h.clock.waits)")

        center.addAddressWatch(from: "0xAbC")
        #expect(h.attempts == 6 && !center.socketHasGivenUp, "the watch added began again")
        h.open()
        let (id, kind) = try #require(h.client.pendingSubscribe.first)
        #expect(kind == .minedTransactions && h.client.pendingSubscribe.count == 1)
        h.client.socketDidReceive(.success(.string(#"{"jsonrpc":"2.0","id":\#(id),"result":"0xM"}"#)), attempt: 6)
        #expect(h.client.currentAttemptAnswered && h.client.consecutiveFailures == 0 && h.client.currentSubscriptionId == "0xM")
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
