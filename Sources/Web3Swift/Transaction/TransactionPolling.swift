//
//  TransactionPolling.swift
//  Created by Bailey Nahi on 11/08/2025.
//

import Foundation
import Web3Core

/// Stateless helpers for polling on-chain transaction state.
public enum TransactionPolling {
    /// Waits for a transaction receipt, polling at a specified interval (min 2 seconds).
    ///
    /// - Parameters:
    ///   - txHash: The transaction hash to check.
    ///   - web3: The `Web3` instance to use.
    ///   - pollingInterval: Base polling interval (default: 3 seconds, min: 2 seconds).
    ///   - timeout: Maximum time to wait before timing out (default: 60 seconds).
    ///   - maxRetries: Number of retries before cancelling (default: 20).
    ///   - maxErrorRetries: Number of retries (error count) before cancelling (default: 10).
    /// - Returns: The `TransactionReceipt` if found, or `throw` if it times out.
    /// - Throws: `CancellationError` as soon as the calling task is cancelled — checked at the
    ///   top of every attempt and inside every wait, so a consumer that has stopped listening
    ///   (a status stream torn down, a screen dismissed) does not keep the chain busy for the
    ///   remaining retries. Before 13 September 2026 the waits used `try? await Task.sleep`, which
    ///   turned cancellation into a burst of immediate retries and then a timeout error.
    public static func waitForTransaction(
        txHash: String,
        web3: Web3,
        pollingInterval: TimeInterval = 3,
        timeout: TimeInterval = 60,
        maxRetries: Int = 20,
        maxErrorRetries: Int = 10
    ) async throws -> TransactionReceipt {
        let interval = max(pollingInterval, 2) // min 2-second delay
        let startTime = Date()
        var retryCount = 0
        var errorCount = 0 // Occurs when transaction is not yet indexed
        var lastStatus: TransactionReceipt.TXStatus? = nil
        
        while Date().timeIntervalSince(startTime) < timeout && retryCount < maxRetries {
            try Task.checkCancellation()
            do {
                let receipt = try await web3.eth.transactionReceipt(txHash)
                if receipt.status != .notYetProcessed {
                    return receipt // Transaction confirmed or failed
                }
                
                // Prevent unnecessary polling if status remains unchanged
                if receipt.status == lastStatus {
                    try await sleep(interval)
                    retryCount += 1
                    continue
                }
                
                lastStatus = receipt.status
            } catch {
                errorCount += 1
                print("Polling retry (count\(errorCount)): \(error.localizedDescription)")
                if errorCount >= maxErrorRetries {
                    break // E.g. not indexed
                }
            }
            
            // Delay between retries
            try await sleep(interval)
            retryCount += 1
        }
        
        throw Web3Error.timeoutError(desc: "Timed out waiting for transaction receipt")
    }
    
    // MARK: - Helpers
    
    /// Propagates cancellation: `Task.sleep` throws `CancellationError` at once when the task is
    /// cancelled, and that is the answer the caller wants.
    private static func sleep(_ seconds: TimeInterval) async throws {
        try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
    }
}
