//
//  HookCenter.swift
//  THAT
//
//  Created by Bailey Nahi on 11/08/2025.
//

import Foundation

/// A lightweight, concurrency-safe hook bus.
/// Store closures, fire them later with a payload.
/// Callers can add/remove hooks at runtime.
public actor HookCenter<Payload: Sendable> {
    public typealias HookID = UUID
    public typealias Hook = @Sendable (Payload) async -> Void
    // public typealias Hook = @Sendable (Payload) -> Void
    
    private var hooks: [HookID: Hook] = [:]
    
    public init() {}
    
    /// Adds a hook and returns its id so you can remove it later.
    @discardableResult
    public func add(_ hook: @escaping Hook) -> HookID {
        let id = HookID()
        hooks[id] = hook
        return id
    }
    
    /// Remove a previously added hook.
    public func remove(_ id: HookID) {
        hooks.removeValue(forKey: id)
    }
    
    /// Remove everything.
    public func removeAll() {
        hooks.removeAll()
    }
    
    /// Serial execution on this actor; preserves registration order.
    public func fire(_ payload: Payload) async {
        let current = hooks.values // snapshot
        for h in current { await h(payload) }
    }
    
    /// Concurrent execution with structured concurrency; awaits all.
    public func fireConcurrently(_ payload: Payload) async {
        let current = hooks.values // snapshot
        await withTaskGroup(of: Void.self) { group in
            for h in current { group.addTask { await h(payload) } }
        }
    }
    
    /// Unstructured fire-and-forget; does not await completion.
    /// Use only when we truly don't care about completion/ordering.
    public func fireDetached(_ payload: Payload) {
        let current = hooks.values // snapshot
        for h in current { Task { await h(payload) } }
    }
}
