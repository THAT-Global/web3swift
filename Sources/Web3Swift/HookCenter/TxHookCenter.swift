//
//  TxHookCenter.swift
//  THAT
//
//  Created by Bailey Nahi on 11/08/2025.
//

import Foundation

/// Typical usage:
/// ```swift
/// // Create a shared instance (e.g. in a service or app-wide context)
/// let txHooks = TxHookCenter()
/// let result = try await TransactionExecutor.sendRawTransaction(signedTx, using: web3)
///
/// // Notify all listeners
/// await txHooks.fire(result) // notify listeners or: `await txHooks.fireAsync(result)`
///
/// // Adding a listener (e.g., in a UI controller or view model)
/// let hookID = await txHooks.add { result in print("TX sent:", result.hash) }
///
/// // Removing a specific listener
/// await txHooks.remove(hookID)
///
/// // Or wiping all listeners
/// await txHooks.removeAll()
/// ```
public typealias TxHookCenter = HookCenter<TransactionSendingResult>

public enum HookBuses {
    public static let txn = TxHookCenter()
}
