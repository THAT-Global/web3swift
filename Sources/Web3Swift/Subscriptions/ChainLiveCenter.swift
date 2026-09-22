//
//  ChainLiveCenter.swift
//  web3swift
//
//  Per-chain WS manager: maintains a normalized address watch set
//  and (re)applies subscriptions on connect/reconnect.
//

import Foundation

#if !os(Android)

@MainActor
public final class ChainLiveCenter: NSObject, MinedTxWSClientDelegate {

    // MARK: Public outputs

    public let minedTxHashHooks = HookCenter<String>()
    /// Every log the center's log watch delivers (N4); `waitForLog` listens here.
    public let logHooks = HookCenter<SubscribedLog>()
    public var onAffectedWallets: ((Set<String>) -> Void)?
    public var onMinedTx: ((MinedTx) -> Void)?
    public var onLog: ((SubscribedLog) -> Void)?

    // MARK: Configuration

    public let chainId: Int
    public let wssURL: URL

    public var hashesOnly: Bool {
        didSet { applySubscriptionIfNeeded() }
    }

    public var includeRemoved: Bool {
        didSet { applySubscriptionIfNeeded() }
    }

    // MARK: Private

    private let client: MinedTxWSClient
    private var started = false
    private var isConnected = false

    private var watchSet: Set<AddressFilter> = []
    private var watchedFrom: Set<String> = []
    private var watchedTo: Set<String> = []
    /// The log watch (N4): one filter per chain, kept across a suspension, gone on `stop`.
    public private(set) var logWatch: LogWatch?

    /// What the log subscription asks the node for: the logs at one address whose topics match — a position's
    /// nil is any value, a set any of its values (the app watches an EntryPoint's `UserOperationEvent` for a
    /// set of senders at topic 2).
    public struct LogWatch: Sendable, Equatable {
        public var address: String
        public var topics: [Set<String>?]

        public init(address: String, topics: [Set<String>?]) {
            self.address = address.lowercased()
            self.topics = topics.map { $0.map { Set($0.map { $0.lowercased() }) } }
        }
    }

    // MARK: Init

    public init(chainId: Int, wssURL: URL, hashesOnly: Bool = true, includeRemoved: Bool = false) {
        self.chainId = chainId
        self.wssURL = wssURL
        self.hashesOnly = hashesOnly
        self.includeRemoved = includeRemoved
        self.client = MinedTxWSClient(chainId: chainId, wssURL: wssURL)
        super.init()
        self.client.delegate = self
    }

    // MARK: Lifecycle

    public func start() {
        guard !started else { return }
        started = true
        client.connect()
        if !watchSet.isEmpty { applySubscriptionIfNeeded() }
    }

    public func stop() {
        guard started else { return }
        started = false
        watchSet.removeAll()
        watchedFrom.removeAll()
        watchedTo.removeAll()
        logWatch = nil
        client.unsubscribe(.minedTransactions)
        client.unsubscribe(.logs)
        client.disconnect()
    }

    /// The socket closed while the app is in the background (N4): the watches stay, and `resume` puts them
    /// back on a new socket. A receipt awaited across a suspension is the backstop poll's until then.
    public func suspend() {
        guard started else { return }
        started = false
        client.disconnect()
    }

    /// Back to the foreground: reconnect, and every watch the center holds goes back on the socket.
    public func resume() {
        guard !started, !watchSet.isEmpty || logWatch != nil else { return }
        start()
        applySubscriptionIfNeeded()
        applyLogSubscriptionIfNeeded()
    }

    /// Whether the mined-transactions watch names `address` as a sender.
    public func isWatching(from address: String) -> Bool {
        guard let normalized = AddressFilter.from(address).normalized, case .from(let a) = normalized else { return false }
        return watchedFrom.contains(a)
    }

    // MARK: Watch management

    public func setAddressWatch(from: [String], to: [String], pairs: [(from: String, to: String)] = []) {
        var next: Set<AddressFilter> = []
        for f in from { if let nf = AddressFilter.from(f).normalized { next.insert(nf) } }
        for t in to { if let nt = AddressFilter.to(t).normalized { next.insert(nt) } }
        for p in pairs { if let np = AddressFilter.both(from: p.from, to: p.to).normalized { next.insert(np) } }

        watchSet = next
        rebuildDerivedSets()
        start()
        applySubscriptionIfNeeded()
    }

    public func addAddressWatch(from: String? = nil, to: String? = nil) {
        var entry: AddressFilter?
        if let from, let to, let pair = AddressFilter.both(from: from, to: to).normalized { entry = pair }
        else if let from, let fromFilter = AddressFilter.from(from).normalized { entry = fromFilter }
        else if let to, let toFilter = AddressFilter.to(to).normalized { entry = toFilter }

        guard let e = entry, !watchSet.contains(e) else { return }
        watchSet.insert(e)
        rebuildDerivedSets()
        start()
        applySubscriptionIfNeeded()
    }

    public func removeAddressWatch(from: String? = nil, to: String? = nil) {
        var removedAny = false
        if let f = from?.lowercased().trimmingCharacters(in: .whitespacesAndNewlines), !f.isEmpty {
            removedAny = (watchSet.remove(.from(f)) != nil)
        }
        if let t = to?.lowercased().trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty {
            removedAny = (watchSet.remove(.to(t)) != nil) || removedAny
        }
        if let f = from?.lowercased().trimmingCharacters(in: .whitespacesAndNewlines),
           let t = to?.lowercased().trimmingCharacters(in: .whitespacesAndNewlines),
           !f.isEmpty, !t.isEmpty {
            removedAny = (watchSet.remove(.both(from: f, to: t)) != nil) || removedAny
        }
        guard removedAny else { return }
        rebuildDerivedSets()
        applySubscriptionIfNeeded()
    }

    // MARK: Log watch (N4)

    /// Sets the chain's log watch — replacing any earlier one — and puts it on the socket, starting the socket
    /// if it is not up. The same watch again is a no-op at the node.
    public func setLogWatch(_ watch: LogWatch?) {
        logWatch = watch
        if watch != nil { start() }
        applyLogSubscriptionIfNeeded()
    }

    /// The first delivered log `matches`, or nil when `timeout` passes first. A log that does not match is
    /// skipped, never an answer — another operation's event from the same sender, say.
    public func waitForLog(timeout: TimeInterval, matching matches: @escaping @Sendable (SubscribedLog) -> Bool) async -> SubscribedLog? {
        start()
        let stream = AsyncStream<SubscribedLog> { continuation in
            Task { [weak self] in
                guard let self else { return }
                let id = await self.logHooks.add { log in continuation.yield(log) }
                continuation.onTermination = { _ in
                    Task { await self.logHooks.remove(id) }
                }
            }
        }
        return await withTaskGroup(of: SubscribedLog?.self, returning: SubscribedLog?.self) { group in
            group.addTask {
                for await log in stream where matches(log) { return log }
                return nil
            }
            group.addTask {
                try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                return nil
            }
            let result = await group.next() ?? nil
            group.cancelAll()
            return result
        }
    }

    public func waitForMinedHash(
        _ hash: String,
        from: String? = nil,
        to: String? = nil,
        timeout: TimeInterval = 120
    ) async -> Bool {
        let target = hash.lowercased()
        start()

        var tempAdded: AddressFilter?
        if let f = from, let nf = AddressFilter.from(f).normalized, !watchSet.contains(nf) {
            watchSet.insert(nf); tempAdded = nf
        }
        if tempAdded == nil, let t = to, let nt = AddressFilter.to(t).normalized, !watchSet.contains(nt) {
            watchSet.insert(nt); tempAdded = nt
        }
        if tempAdded != nil { rebuildDerivedSets(); applySubscriptionIfNeeded() }

        let stream = AsyncStream<String> { continuation in
            Task { [weak self] in
                guard let self else { return }
                let id = await self.minedTxHashHooks.add { h in
                    continuation.yield(h.lowercased())
                }
                continuation.onTermination = { _ in
                    Task { await self.minedTxHashHooks.remove(id) }
                }
            }
        }

        let seen = await withTaskGroup(of: Bool.self, returning: Bool.self) { group in
            group.addTask {
                for await h in stream { if h == target { return true } }
                return false
            }
            group.addTask {
                try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                return false
            }
            let result = await group.next() ?? false
            group.cancelAll()
            return result
        }

        if let tempAdded {
            watchSet.remove(tempAdded)
            rebuildDerivedSets()
            applySubscriptionIfNeeded()
        }
        return seen
    }

    // MARK: Delegate

    public func minedTxWS(_ client: MinedTxWSClient, didReceive message: WSMessage) {
        switch message {
        case .subscribed(let kind, _, let subId):
            guard kind == "alchemy_minedTransactions" else { return }
            client.subIdMeta[subId] = Array(watchSet)

        case .minedTxHash(let h, _):
            Task { await minedTxHashHooks.fire(h) }

        case .minedTx(_, let tx):
            var affected: Set<String> = []
            if watchedFrom.contains(tx.from.lowercased()) { affected.insert(tx.from.lowercased()) }
            if let to = tx.to?.lowercased(), watchedTo.contains(to) { affected.insert(to) }
            if !affected.isEmpty { onAffectedWallets?(affected) }
            onMinedTx?(tx)
            Task { await minedTxHashHooks.fire(tx.hash) }

        case .log(_, let log):
            onLog?(log)
            Task { await logHooks.fire(log) }

        case .raw:
            break
        }
    }

    public func minedTxWS(_ client: MinedTxWSClient, didChange isConnected: Bool) {
        self.isConnected = isConnected
    }

    // MARK: Internals

    private func applyLogSubscriptionIfNeeded() {
        guard let logWatch else {
            client.unsubscribe(.logs)
            return
        }
        _ = client.subscribeLogs(address: logWatch.address, topics: logWatch.topics)
    }

    private func applySubscriptionIfNeeded() {
        if watchSet.isEmpty {
            client.unsubscribeCurrent()
            return
        }
        let filters = Array(watchSet)
        _ = client.subscribeMinedTransactions(
            filters: filters,
            includeRemoved: includeRemoved,
            hashesOnly: hashesOnly
        )
    }

    private func rebuildDerivedSets() {
        var froms: Set<String> = []
        var tos: Set<String> = []
        for f in watchSet {
            switch f {
            case .from(let a): froms.insert(a)
            case .to(let a): tos.insert(a)
            case .both(let f, let t):
                froms.insert(f); tos.insert(t)
            }
        }
        watchedFrom = froms
        watchedTo = tos
    }
}
#endif // !os(Android)
