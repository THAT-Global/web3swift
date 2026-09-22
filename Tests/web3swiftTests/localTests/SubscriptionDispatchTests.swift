//
//  SubscriptionDispatchTests.swift
//  localTests
//
//  PAYMENT-CONNECTIONS-PLAN.md N4, the fork half (T8's fork cells): one socket per chain carries two
//  subscription kinds — the mined transactions it always had and the node's logs — each with its own filter
//  and id, dispatched by the id a notification names and re-applied on a reconnect; the center's log watch
//  answers the first matching log and skips one that does not match; a suspension keeps the watches and a
//  stop drops them. The frames are fed to the client's parser directly: no socket is opened for the parsing
//  cells, and the cells that start a center point it at a refused port and stop it before they end.
//

import Foundation
import Testing
@testable import Web3Swift

@MainActor
final class RecordingWSDelegate: MinedTxWSClientDelegate {
    var messages: [WSMessage] = []
    func minedTxWS(_ client: MinedTxWSClient, didReceive message: WSMessage) { messages.append(message) }
    func minedTxWS(_ client: MinedTxWSClient, didChange isConnected: Bool) {}
}

@MainActor
@Suite("MinedTxWSClient dispatch (N4): two kinds on one socket, by subscription id")
struct MinedTxWSClientDispatchTests {
    static let wss = URL(string: "wss://127.0.0.1:9/ws")!
    static func frame(_ json: String) -> Data { Data(json.utf8) }
    static let topics: [Set<String>?] = [["0xsig"], nil, ["0xsender"]]

    @Test("each kind subscribes with its own request, learns its own id from the reply, and a notification is dispatched by the id it names")
    func twoKindsDispatchById() throws {
        let client = MinedTxWSClient(chainId: 137, wssURL: Self.wss)
        let delegate = RecordingWSDelegate()
        client.delegate = delegate
        client.handleDidOpen()   // open with no socket: sends go nowhere, the bookkeeping is real
        let mined = try #require(client.subscribeMinedTransactions(filters: [.from("0xAbC")], hashesOnly: false))
        let logs = try #require(client.subscribeLogs(address: "0xEntry", topics: Self.topics))
        #expect(mined != logs)
        client.handle(Self.frame(#"{"jsonrpc":"2.0","id":\#(mined),"result":"0xsubM"}"#))
        client.handle(Self.frame(#"{"jsonrpc":"2.0","id":\#(logs),"result":"0xsubL"}"#))
        #expect(client.currentSubscriptionId == "0xsubM")
        #expect(client.subscriptionId(for: .logs) == "0xsubL")

        client.handle(Self.frame(#"{"jsonrpc":"2.0","method":"eth_subscription","params":{"subscription":"0xsubL","result":{"address":"0xentry","topics":["0xsig","0xhash","0xsender"],"data":"0x01","transactionHash":"0xtx","blockNumber":"0x10","removed":false}}}"#))
        client.handle(Self.frame(#"{"jsonrpc":"2.0","method":"eth_subscription","params":{"subscription":"0xsubM","result":{"removed":false,"transaction":{"hash":"0xt1","from":"0xabc","to":"0xdef","value":"0x1","blockNumber":"0x11"}}}}"#))
        client.handle(Self.frame(#"{"jsonrpc":"2.0","method":"eth_subscription","params":{"subscription":"0xother","result":{"hash":"0xzz"}}}"#))

        #expect(delegate.messages.count == 5)
        guard delegate.messages.count == 5 else { return }
        guard case .subscribed(let kind0, let id0, let sub0) = delegate.messages[0] else { Issue.record("\(delegate.messages[0])"); return }
        #expect(kind0 == "alchemy_minedTransactions" && id0 == mined && sub0 == "0xsubM")
        guard case .subscribed(let kind1, let id1, let sub1) = delegate.messages[1] else { Issue.record("\(delegate.messages[1])"); return }
        #expect(kind1 == "logs" && id1 == logs && sub1 == "0xsubL")
        guard case .log(let subId, let log) = delegate.messages[2] else { Issue.record("\(delegate.messages[2])"); return }
        #expect(subId == "0xsubL")
        #expect(log == SubscribedLog(address: "0xentry", topics: ["0xsig", "0xhash", "0xsender"], data: "0x01", transactionHash: "0xtx", blockNumber: 16, removed: false))
        guard case .minedTx(let minedSub, let tx) = delegate.messages[3] else { Issue.record("\(delegate.messages[3])"); return }
        #expect(minedSub == "0xsubM" && tx.hash == "0xt1" && tx.blockNumber == 17)
        guard case .minedTxHash(let hash, let removed) = delegate.messages[4] else { Issue.record("\(delegate.messages[4])"); return }
        #expect(hash == "0xzz" && !removed, "a notification on no known id is parsed as it always was")
    }

    @Test("the same log filter again is a no-op, a different one replaces the subscription, and a reconnect re-applies every kind with fresh ids")
    func dedupeReplaceAndReapply() throws {
        let client = MinedTxWSClient(chainId: 137, wssURL: Self.wss)
        client.handleDidOpen()
        let first = try #require(client.subscribeLogs(address: "0xE", topics: Self.topics))
        #expect(client.subscribeLogs(address: "0xe", topics: Self.topics) == nil, "the same filter: no request")
        let wider: [Set<String>?] = [["0xsig"], nil, ["0xsender", "0xanother"]]
        let second = try #require(client.subscribeLogs(address: "0xE", topics: wider))
        #expect(second == first + 1)
        client.handle(Self.frame(#"{"jsonrpc":"2.0","id":\#(second),"result":"0xL1"}"#))
        let mined = try #require(client.subscribeMinedTransactions(filters: [.from("0xa")]))
        client.handle(Self.frame(#"{"jsonrpc":"2.0","id":\#(mined),"result":"0xM1"}"#))
        #expect(client.subscriptionId(for: .logs) == "0xL1" && client.currentSubscriptionId == "0xM1")

        // A new socket opened: the ids are the node's to answer again, both kinds asked in a known order.
        client.handleDidOpen()
        #expect(client.subscriptionId(for: .logs) == nil && client.currentSubscriptionId == nil)
        client.handle(Self.frame(#"{"jsonrpc":"2.0","id":\#(mined + 1),"result":"0xM2"}"#))
        client.handle(Self.frame(#"{"jsonrpc":"2.0","id":\#(mined + 2),"result":"0xL2"}"#))
        #expect(client.currentSubscriptionId == "0xM2" && client.subscriptionId(for: .logs) == "0xL2")

        client.unsubscribe(.logs)
        #expect(client.subscriptionId(for: .logs) == nil && client.currentSubscriptionId == "0xM2")
    }
}

@MainActor
@Suite("ChainLiveCenter's log watch and suspension (N4)")
struct ChainLiveCenterWatchTests {
    static let wss = URL(string: "wss://127.0.0.1:9/ws")!
    static let watch = ChainLiveCenter.LogWatch(address: "0xEntry", topics: [["0xSig"], nil, ["0xSender"]])

    @Test("waitForLog answers the first matching log and skips one that does not match — another operation's event from the same sender")
    func waitForLogSkipsWhatDoesNotMatch() async {
        let center = ChainLiveCenter(chainId: 137, wssURL: Self.wss)
        defer { center.stop() }
        center.setLogWatch(Self.watch)
        #expect(center.logWatch == ChainLiveCenter.LogWatch(address: "0xentry", topics: [["0xsig"], nil, ["0xsender"]]), "normalised to lowercase")
        let wanted = "0xhash2"
        let waiter = Task { await center.waitForLog(timeout: 5) { $0.topics.count > 1 && $0.topics[1] == wanted } }
        try? await Task.sleep(for: .milliseconds(200))   // the hook registers on the actor first
        let feeder = MinedTxWSClient(chainId: 137, wssURL: Self.wss)
        let other = SubscribedLog(address: "0xentry", topics: ["0xsig", "0xhash1", "0xsender"], data: "0x", transactionHash: "0xt1", blockNumber: 1, removed: false)
        let ours = SubscribedLog(address: "0xentry", topics: ["0xsig", wanted, "0xsender"], data: "0x", transactionHash: "0xt2", blockNumber: 2, removed: false)
        center.minedTxWS(feeder, didReceive: .log(subId: "0xL", log: other))
        center.minedTxWS(feeder, didReceive: .log(subId: "0xL", log: ours))
        let got = await waiter.value
        #expect(got?.transactionHash == "0xt2")
    }

    @Test("waitForLog answers nil at its timeout when nothing matched")
    func waitForLogTimesOut() async {
        let center = ChainLiveCenter(chainId: 137, wssURL: Self.wss)
        defer { center.stop() }
        let got = await center.waitForLog(timeout: 0.2) { _ in true }
        #expect(got == nil)
    }

    @Test("suspend keeps the watches for the next socket and resume puts them back; stop drops them")
    func suspendResumeStop() {
        let center = ChainLiveCenter(chainId: 137, wssURL: Self.wss)
        center.setAddressWatch(from: ["0xAbC"], to: [])
        center.setLogWatch(Self.watch)
        #expect(center.isWatching(from: "0xabc") && !center.isWatching(from: "0xdef"))
        center.suspend()
        #expect(center.isWatching(from: "0xABC") && center.logWatch != nil, "a suspension keeps the watches")
        center.resume()
        #expect(center.isWatching(from: "0xabc") && center.logWatch != nil)
        center.stop()
        #expect(!center.isWatching(from: "0xabc") && center.logWatch == nil, "a stop drops them")
    }

    @Test("the registry suspends and resumes every center it holds")
    func registrySuspendsAndResumes() {
        let chainId = 990_137
        let center = ChainSubscriptionRegistry.shared.ensureAndWatch(chainId: chainId, wssURL: Self.wss, from: ["0xAbC"], to: [])
        defer { ChainSubscriptionRegistry.shared.remove(chainId: chainId) }
        ChainSubscriptionRegistry.shared.suspendAll()
        #expect(center.isWatching(from: "0xabc"))
        ChainSubscriptionRegistry.shared.resumeAll()
        #expect(center.isWatching(from: "0xabc"))
    }
}
