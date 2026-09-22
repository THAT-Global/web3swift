//
//  MinedTxWSClient.swift
//  web3swift
//
//  WebSocket client for mined-transaction subscriptions.
//

import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

#if !os(Android)
// MARK: - Value Types

public struct MinedTx: Sendable, Equatable {
    public let hash: String
    public let from: String
    public let to: String?
    public let value: String?
    public let blockNumber: UInt64?
    public let removed: Bool

    public init(hash: String, from: String, to: String?, value: String?, blockNumber: UInt64?, removed: Bool) {
        self.hash = hash
        self.from = from
        self.to = to
        self.value = value
        self.blockNumber = blockNumber
        self.removed = removed
    }
}

/// A log a `logs` subscription delivered, as the node sent it: the address, the topics, the data, the
/// transaction it sits in. Raw on purpose — the fork knows no contract's event; the app that watches an
/// EntryPoint decodes it (PAYMENT-CONNECTIONS-PLAN.md N4).
public struct SubscribedLog: Sendable, Equatable {
    public let address: String
    public let topics: [String]
    public let data: String
    public let transactionHash: String?
    public let blockNumber: UInt64?
    public let removed: Bool

    public init(address: String, topics: [String], data: String, transactionHash: String?, blockNumber: UInt64?, removed: Bool) {
        self.address = address
        self.topics = topics
        self.data = data
        self.transactionHash = transactionHash
        self.blockNumber = blockNumber
        self.removed = removed
    }
}

public enum WSMessage: Sendable {
    case minedTxHash(_ hash: String, removed: Bool)
    case minedTx(subId: String, tx: MinedTx)
    /// A `logs` subscription's log (N4).
    case log(subId: String, log: SubscribedLog)
    case subscribed(kind: String, rpcID: Int, subId: String)
    case raw(Data)
}

/// What one socket subscribes to: one live subscription per kind, each with its own filter and id, all
/// re-applied on reconnect (N4 — the EntryPoint's logs ride the same socket as the mined transactions).
public enum SubscriptionKind: String, Sendable, Hashable, CaseIterable {
    case minedTransactions = "alchemy_minedTransactions"
    case logs = "logs"
}

public enum AddressFilter: Sendable, Equatable, Hashable {
    case from(String)
    case to(String)
    case both(from: String, to: String)

    public var normalized: AddressFilter? {
        func norm(_ s: String?) -> String? {
            guard let s, !s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
            return s.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        }
        switch self {
        case .from(let a):
            guard let a = norm(a) else { return nil }
            return .from(a)
        case .to(let a):
            guard let a = norm(a) else { return nil }
            return .to(a)
        case .both(let f, let t):
            guard let f = norm(f), let t = norm(t) else { return nil }
            return .both(from: f, to: t)
        }
    }

    public var dict: [String: String] {
        switch self {
        case .from(let address):        return ["from": address]
        case .to(let address):          return ["to": address]
        case .both(let from, let to):   return ["from": from, "to": to]
        }
    }

    public var canon: String {
        switch self {
        case .from(let a):          return "f:\(a)"
        case .to(let a):            return "t:\(a)"
        case .both(let f, let t):   return "f:\(f)|t:\(t)"
        }
    }
}

// MARK: - Delegate

@MainActor
public protocol MinedTxWSClientDelegate: AnyObject {
    func minedTxWS(_ client: MinedTxWSClient, didReceive message: WSMessage)
    func minedTxWS(_ client: MinedTxWSClient, didChange isConnected: Bool)
}

// MARK: - WeakBox

public final class WeakBox<T: AnyObject>: @unchecked Sendable {
    public weak var value: T?
    public init(_ value: T?) { self.value = value }
}

// MARK: - URLSession WebSocket delegate proxy

public final class MinedTxWSDelegateProxy: NSObject, URLSessionWebSocketDelegate, @unchecked Sendable {
    weak var owner: MinedTxWSClient?
    public init(owner: MinedTxWSClient) { self.owner = owner }

    public func urlSession(_ session: URLSession,
                           webSocketTask: URLSessionWebSocketTask,
                           didOpenWithProtocol proto: String?) {
        Task { @MainActor [weak owner] in owner?.handleDidOpen() }
    }

    public func urlSession(_ session: URLSession,
                           webSocketTask: URLSessionWebSocketTask,
                           didCloseWith closeCode: URLSessionWebSocketTask.CloseCode,
                           reason: Data?) {
        Task { @MainActor [weak owner] in owner?.handleDidClose() }
    }
}

// MARK: - Client (MainActor)

@MainActor
public final class MinedTxWSClient: NSObject {
    public let chainId: Int
    public let wssURL: URL
    public weak var delegate: MinedTxWSClientDelegate?

    private var session: URLSession?
    private var ws: URLSessionWebSocketTask?
    private var delegateProxy: MinedTxWSDelegateProxy?
    private var isOpen = false
    private var isClosing = false
    private var hasActiveReceive = false
    private var backoff: TimeInterval = 1.0
    private var heartbeatTask: Task<Void, Never>?

    private var nextRequestID = 1
    /// A subscribe request in flight, by its JSON-RPC id, to the kind it is for.
    private var pendingSubscribe: [Int: SubscriptionKind] = [:]
    /// One subscription per kind: its filter (re-applied on reconnect), the key that dedupes a repeat, and
    /// the node's id once it answered.
    private struct Subscription {
        var filter: [String: Any]
        var canonicalKey: String
        var subId: String?
    }
    private var subscriptions: [SubscriptionKind: Subscription] = [:]

    /// The mined-transactions subscription's id — the one the client had before N4 gave it a second kind.
    public var currentSubscriptionId: String? { subscriptions[.minedTransactions]?.subId }
    /// A kind's live subscription id, nil until the node answered (or after a reconnect, until it does again).
    public func subscriptionId(for kind: SubscriptionKind) -> String? { subscriptions[kind]?.subId }

    public var subIdMeta: [String: Any] = [:]

    public init(chainId: Int, wssURL: URL) {
        self.chainId = chainId
        self.wssURL = wssURL
        super.init()
    }

    // MARK: Lifecycle

    public func connect() {
        guard ws == nil else { return }
        isClosing = false

        let cfg = URLSessionConfiguration.default
        cfg.waitsForConnectivity = true

        let proxy = MinedTxWSDelegateProxy(owner: self)
        delegateProxy = proxy

        let session = URLSession(configuration: cfg, delegate: proxy, delegateQueue: nil)
        self.session = session

        let task = session.webSocketTask(with: wssURL)
        ws = task
        task.resume()
    }

    public func disconnect() {
        isClosing = true
        stopHeartbeat()
        ws?.cancel(with: .goingAway, reason: nil)
        ws = nil
        session?.invalidateAndCancel()
        session = nil
        hasActiveReceive = false
        delegate?.minedTxWS(self, didChange: false)
    }

    public func handleDidOpen() {
        isOpen = true
        backoff = 1.0
        listen()
        startHeartbeat()
        delegate?.minedTxWS(self, didChange: true)
        // Every kind's filter goes back on the new socket; the ids are the node's to answer again.
        for kind in SubscriptionKind.allCases where subscriptions[kind] != nil {
            subscriptions[kind]?.subId = nil
            _ = internalSubscribe(kind)
        }
    }

    public func handleDidClose() {
        isOpen = false
        scheduleReconnect()
    }

    private func scheduleReconnect() {
        guard !isClosing else { return }
        stopHeartbeat()
        ws?.cancel(with: .goingAway, reason: nil)
        ws = nil
        session?.invalidateAndCancel()
        session = nil
        hasActiveReceive = false
        for kind in SubscriptionKind.allCases { subscriptions[kind]?.subId = nil }
        pendingSubscribe = [:]

        let delay = min(backoff, 30.0)
        backoff = min(backoff * 2, 30.0)

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard !self.isClosing else { return }
            self.connect()
        }
    }

    // MARK: Heartbeat

    private func startHeartbeat() {
        stopHeartbeat()
        heartbeatTask = Task { @MainActor [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                self.ws?.sendPing { _ in }
                try? await Task.sleep(nanoseconds: 20_000_000_000)
            }
        }
    }

    private func stopHeartbeat() {
        heartbeatTask?.cancel()
        heartbeatTask = nil
    }

    // MARK: Receive loop

    private func listen() {
        guard let ws, !hasActiveReceive else { return }
        hasActiveReceive = true

        let box = WeakBox(self)
        ws.receive { result in
            Task { @MainActor in
                guard let owner = box.value else { return }
                owner.hasActiveReceive = false
                owner.handleReceive(result)
            }
        }
    }

    private func handleReceive(_ result: Result<URLSessionWebSocketTask.Message, Error>) {
        switch result {
        case .failure:
            scheduleReconnect()

        case .success(let msg):
            switch msg {
            case .data(let data):  handle(data)
            case .string(let str): handle(Data(str.utf8))
            @unknown default: break
            }
            listen()
        }
    }

    // MARK: Parse / Dispatch

    /// One frame from the node: a subscribe reply (the kind's id, by the request's id) or a notification,
    /// dispatched by the subscription id it names — a log to `.log`, a mined transaction to `.minedTx` /
    /// `.minedTxHash`, anything else to `.raw`. Internal, so the dispatch cells can feed it frames.
    func handle(_ data: Data) {
        if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let id = obj["id"] as? Int,
           let subId = obj["result"] as? String,
           let kind = pendingSubscribe.removeValue(forKey: id) {
            subscriptions[kind]?.subId = subId
            delegate?.minedTxWS(self, didReceive: .subscribed(kind: kind.rawValue, rpcID: id, subId: subId))
            return
        }

        guard
            let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let method = obj["method"] as? String, method == "eth_subscription",
            let params = obj["params"] as? [String: Any],
            let subId = params["subscription"] as? String,
            let result = params["result"] as? [String: Any]
        else {
            delegate?.minedTxWS(self, didReceive: .raw(data))
            return
        }

        let removed = (result["removed"] as? Bool) ?? false

        if subId == subscriptions[.logs]?.subId {
            guard let address = result["address"] as? String,
                  let topics = result["topics"] as? [String],
                  let logData = result["data"] as? String
            else {
                delegate?.minedTxWS(self, didReceive: .raw(data))
                return
            }
            let blockNumber = (result["blockNumber"] as? String).flatMap { UInt64($0.stripHexPrefix(), radix: 16) }
            let log = SubscribedLog(
                address: address, topics: topics, data: logData,
                transactionHash: result["transactionHash"] as? String, blockNumber: blockNumber, removed: removed
            )
            delegate?.minedTxWS(self, didReceive: .log(subId: subId, log: log))
            return
        }

        if let tx = result["transaction"] as? [String: Any],
           let hash = tx["hash"] as? String,
           let from = tx["from"] as? String {
            let to = tx["to"] as? String
            let value = tx["value"] as? String
            let blockHex = tx["blockNumber"] as? String
            let blockNumber = blockHex.flatMap { UInt64($0.stripHexPrefix(), radix: 16) }

            let mined = MinedTx(
                hash: hash, from: from, to: to, value: value,
                blockNumber: blockNumber, removed: removed
            )
            delegate?.minedTxWS(self, didReceive: .minedTx(subId: subId, tx: mined))
            return
        }

        if let hashDirect = result["hash"] as? String {
            delegate?.minedTxWS(self, didReceive: .minedTxHash(hashDirect, removed: removed))
            return
        }

        if let txObj = result["transaction"] as? [String: Any],
           let onlyHash = txObj["hash"] as? String {
            delegate?.minedTxWS(self, didReceive: .minedTxHash(onlyHash, removed: removed))
            return
        }

        delegate?.minedTxWS(self, didReceive: .raw(data))
    }

    // MARK: - Subscriptions

    public func subscribeMinedTransactions(
        filters: [AddressFilter],
        includeRemoved: Bool = false,
        hashesOnly: Bool = true
    ) -> Int? {
        let normalized = filters.compactMap { $0.normalized }
        let uniq = Array(Set(normalized))
        guard !uniq.isEmpty else { return nil }

        let capped = Array(uniq.prefix(1000))
        let canonKey = [
            "hashesOnly:\(hashesOnly)",
            "includeRemoved:\(includeRemoved)",
            "addresses:[\(capped.map { $0.canon }.sorted().joined(separator: ","))]"
        ].joined(separator: "|")

        var filter: [String: Any] = [
            "addresses": capped.map { $0.dict },
            "hashesOnly": hashesOnly
        ]
        if includeRemoved { filter["includeRemoved"] = true }

        return subscribe(.minedTransactions, filter: filter, canonicalKey: canonKey)
    }

    /// `eth_subscribe("logs", filter)` (N4): the node's logs at `address` whose topics match — a position's
    /// nil is any value, a set is any of its values. One logs subscription per socket; a different filter
    /// replaces it, the same one is a no-op.
    public func subscribeLogs(address: String, topics: [Set<String>?]) -> Int? {
        let address = address.lowercased()
        let normalized: [Set<String>?] = topics.map { $0.map { Set($0.map { $0.lowercased() }) } }
        let canonKey = "logs|address:\(address)|topics:" + normalized.map { set in
            set.map { $0.sorted().joined(separator: ",") } ?? "*"
        }.joined(separator: ";")
        let topicsJSON: [Any] = normalized.map { set -> Any in
            guard let set else { return NSNull() }
            return set.count == 1 ? set.first! : Array(set).sorted()
        }
        let filter: [String: Any] = ["address": address, "topics": topicsJSON]
        return subscribe(.logs, filter: filter, canonicalKey: canonKey)
    }

    /// Records the kind's filter — it goes on every socket from now on — and sends it when the socket is
    /// open. A repeat of the same filter is a no-op; a different one replaces the kind's subscription.
    @discardableResult
    private func subscribe(_ kind: SubscriptionKind, filter: [String: Any], canonicalKey: String) -> Int? {
        if subscriptions[kind]?.canonicalKey == canonicalKey { return nil }
        let previousId = subscriptions[kind]?.subId
        subscriptions[kind] = Subscription(filter: filter, canonicalKey: canonicalKey, subId: nil)
        guard isOpen else { return nil }
        if let previousId { sendUnsubscribe(subId: previousId) }
        return internalSubscribe(kind)
    }

    /// Ends a kind's subscription: unsubscribed on the socket when it has an id, and gone from the filters
    /// a reconnect would re-apply.
    public func unsubscribe(_ kind: SubscriptionKind) {
        guard let subscription = subscriptions.removeValue(forKey: kind) else { return }
        if let subId = subscription.subId { sendUnsubscribe(subId: subId) }
    }

    // MARK: Internals

    @discardableResult
    private func internalSubscribe(_ kind: SubscriptionKind) -> Int? {
        guard let subscription = subscriptions[kind] else { return nil }
        let id = nextID()
        pendingSubscribe[id] = kind

        let body: [String: Any] = [
            "jsonrpc": "2.0",
            "id": id,
            "method": "eth_subscribe",
            "params": [kind.rawValue, subscription.filter]
        ]

        guard let data = try? JSONSerialization.data(withJSONObject: body) else { return nil }
        ws?.send(.data(data)) { _ in }
        return id
    }

    public func unsubscribeCurrent() {
        unsubscribe(.minedTransactions)
    }

    private func sendUnsubscribe(subId: String) {
        let body: [String: Any] = [
            "jsonrpc": "2.0",
            "id": nextID(),
            "method": "eth_unsubscribe",
            "params": [subId]
        ]
        if let data = try? JSONSerialization.data(withJSONObject: body) {
            ws?.send(.data(data)) { _ in }
        }
    }

    private func nextID() -> Int { defer { nextRequestID &+= 1 }; return nextRequestID }
}
#endif // !os(Android)
