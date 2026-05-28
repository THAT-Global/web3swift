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

public enum WSMessage: Sendable {
    case minedTxHash(_ hash: String, removed: Bool)
    case minedTx(subId: String, tx: MinedTx)
    case subscribed(kind: String, rpcID: Int, subId: String)
    case raw(Data)
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
    private var subLookup: [Int: String] = [:]
    public private(set) var currentSubscriptionId: String?
    private var lastCanonicalKey: String?
    private var lastFilterDict: [String: Any]?

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
        if let filter = lastFilterDict {
            _ = internalSubscribe(kind: "alchemy_minedTransactions", filter: filter)
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
        currentSubscriptionId = nil

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

    private func handle(_ data: Data) {
        if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let id = obj["id"] as? Int,
           let subId = obj["result"] as? String,
           let kind = subLookup.removeValue(forKey: id) {
            currentSubscriptionId = subId
            delegate?.minedTxWS(self, didReceive: .subscribed(kind: kind, rpcID: id, subId: subId))
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

        if canonKey == lastCanonicalKey { return nil }

        var filter: [String: Any] = [
            "addresses": capped.map { $0.dict },
            "hashesOnly": hashesOnly
        ]
        if includeRemoved { filter["includeRemoved"] = true }

        lastCanonicalKey = canonKey
        lastFilterDict = filter

        guard isOpen else { return nil }
        return internalSubscribe(kind: "alchemy_minedTransactions", filter: filter)
    }

    // MARK: Internals

    @discardableResult
    private func internalSubscribe(kind: String, filter: [String: Any]) -> Int? {
        if let currentSubscriptionId {
            sendUnsubscribe(subId: currentSubscriptionId)
            self.currentSubscriptionId = nil
        }

        let id = nextID()
        subLookup[id] = kind

        let body: [String: Any] = [
            "jsonrpc": "2.0",
            "id": id,
            "method": "eth_subscribe",
            "params": [kind, filter]
        ]

        guard let data = try? JSONSerialization.data(withJSONObject: body) else { return nil }
        ws?.send(.data(data)) { _ in }
        return id
    }

    public func unsubscribeCurrent() {
        guard let subId = currentSubscriptionId else { return }
        sendUnsubscribe(subId: subId)
        currentSubscriptionId = nil
        lastCanonicalKey = nil
        lastFilterDict = nil
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
