//
//  EventLoop.swift
//  THAT
//
//  Created by Bailey Nahi on 10/08/2025.
//

import Foundation
import Web3Core

public actor EventLoop: Sendable {
    public typealias EventLoopCall = @Sendable (Web3Provider) async -> Void
    
    public struct MonitoredProperty: Sendable {
        public var name: String
        public var calledFunction: EventLoopCall
        public init(name: String, calledFunction: @escaping EventLoopCall) {
            self.name = name
            self.calledFunction = calledFunction
        }
    }
    
    public let provider: Web3Provider
    private var tickTask: Task<Void, Never>?
    
    public private(set) var monitoredProperties: [MonitoredProperty] = []
    public private(set) var monitoredUserFunctions: [EventLoopRunnableProtocol] = []
    
    public init(provider: Web3Provider) { self.provider = provider }
    
    deinit { tickTask?.cancel() }
    
    // MARK: - Control
    
    /// Starts the loop; cancels any existing task first.
    public func start(_ interval: TimeInterval) {
        stop()
        tickTask = Self.startRepeating(every: .seconds(interval)) { [weak self] in
            await self?.tick()
        }
    }
    
    /// Stops the loop and cancels the task.
    public func stop() {
        tickTask?.cancel()
        tickTask = nil
    }
    
    // MARK: - Mutators
    
    public func setMonitors(
        properties: [MonitoredProperty] = [],
        userFunctions: [EventLoopRunnableProtocol] = []
    ) {
        monitoredProperties = properties
        monitoredUserFunctions = userFunctions
    }
    
    public func addMonitor(_ property: MonitoredProperty) {
        monitoredProperties.append(property)
    }
    
    public func addUserFunction(_ runnable: EventLoopRunnableProtocol) {
        monitoredUserFunctions.append(runnable)
    }
    
    // MARK: - Tick
    
    private func tick() async {
        let provider = self.provider
        for prop in monitoredProperties {
            Task { await prop.calledFunction(provider) }
        }
        for fn in monitoredUserFunctions {
            Task { await fn.functionToRun() }
        }
    }
    
    // MARK: - Repeating task helper
    
    /// Creates a repeating async task. Caller should retain the returned Task to cancel later.
    @discardableResult
    static func startRepeating(
        every interval: Duration,
        tolerance: Duration = .milliseconds(100),
        operation: @escaping @Sendable () async -> Void
    ) -> Task<Void, Never> {
        Task {
            let clock = ContinuousClock()
            var next = clock.now + interval
            while !Task.isCancelled {
                await operation()
                try? await clock.sleep(until: next, tolerance: tolerance)
                next += interval
            }
        }
    }
}
