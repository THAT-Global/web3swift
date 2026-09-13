//
//  TransactionPollingCancellationTests.swift
//  localTests
//
//  `TransactionPolling.waitForTransaction` must stop when its task is
//  cancelled — throwing `CancellationError` at once — rather than spend
//  the remaining retries against a node nobody is listening to. Before
//  13 September 2026 the waits swallowed cancellation (`try? await
//  Task.sleep`), so a cancelled poll degenerated into a burst of
//  immediate retries that ended in a timeout error.
//

import Foundation
import Web3Core
import XCTest
@testable import Web3Swift

final class TransactionPollingCancellationTests: XCTestCase {
    func testCancellationStopsThePollAtOnce() async throws {
        // A port that refuses connections: every attempt errors, so without
        // the cancellation checks the loop would burn its error budget as
        // fast as the waits let it and then throw a timeout instead.
        let provider = Web3HttpProvider(url: URL(string: "http://127.0.0.1:9")!, network: .Ethereum)
        let web3 = Web3(provider: provider)
        let started = Date()
        let poll = Task {
            try await TransactionPolling.waitForTransaction(
                txHash: "0x" + String(repeating: "ab", count: 32),
                web3: web3,
                pollingInterval: 2,
                timeout: 60,
                maxRetries: 20,
                maxErrorRetries: 10
            )
        }
        try await Task.sleep(nanoseconds: 300_000_000)
        poll.cancel()
        do {
            _ = try await poll.value
            XCTFail("a cancelled poll must throw")
        } catch is CancellationError {
            // The one answer that proves the loop observed cancellation.
        }
        XCTAssertLessThan(
            Date().timeIntervalSince(started), 3,
            "cancellation must not wait out the polling interval or the retry budget"
        )
    }
}
