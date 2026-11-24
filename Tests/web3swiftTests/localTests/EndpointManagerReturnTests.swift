//
//  EndpointManagerReturnTests.swift
//  localTests
//
//  that-ios decision 14g (25 Nov 2026): a fall-back preference — an endpoint that is NOT the registered first — lapses
//  after `returnToFirstAfter`, counted from the fall-back, and the first registered endpoint goes first again; checked
//  when the preference is asked for (no timer). The window's edges are 15·60 − 1 s (still the fall-back) and 15·60 s
//  (the first endpoint). Without a window, a preference holds until another endpoint answers, as before.
//

import Foundation
import Web3Core
import XCTest
@testable import Web3Swift

final class EndpointManagerReturnTests: XCTestCase {
    /// A clock the cells move.
    final class Clock: @unchecked Sendable {
        private let lock = NSLock()
        private var value = Date(timeIntervalSince1970: 1_800_000_000)
        var now: Date { lock.withLock { value } }
        func advance(_ seconds: TimeInterval) { lock.withLock { value = value.addingTimeInterval(seconds) } }
    }

    static let first = "https://first.example/rpc"
    static let backup = "https://backup.example/rpc"
    static let window: TimeInterval = 15 * 60

    func manager(window: TimeInterval?, clock: Clock) async -> EndpointManager {
        let manager = EndpointManager(returnToFirstAfter: window, now: { clock.now })
        await manager.register(for: .Polygon, endpoints: [Self.first, Self.backup])
        return manager
    }

    func testAFallBackHoldsUntilItsWindowThenTheFirstGoesFirstAgain() async {
        let clock = Clock()
        let manager = await manager(window: Self.window, clock: clock)
        await manager.setPreferred(for: .Polygon, endpoint: Self.backup)   // the first failed; the backup answered
        clock.advance(Self.window - 1)
        var preferred = await manager.preferred(for: .Polygon)
        var ordered = await manager.orderedEndpoints(for: .Polygon)
        XCTAssertEqual(preferred, Self.backup, "15·60 − 1 s after the fall-back: still the backup")
        XCTAssertEqual(ordered, [Self.backup, Self.first])
        clock.advance(1)
        preferred = await manager.preferred(for: .Polygon)
        ordered = await manager.orderedEndpoints(for: .Polygon)
        XCTAssertEqual(preferred, Self.first, "15·60 s after the fall-back: the first endpoint")
        XCTAssertEqual(ordered, [Self.first, Self.backup])
    }

    func testLaterAnswersOnTheBackupDoNotExtendTheWindow() async {
        let clock = Clock()
        let manager = await manager(window: Self.window, clock: clock)
        await manager.setPreferred(for: .Polygon, endpoint: Self.backup)
        clock.advance(10 * 60)
        await manager.setPreferred(for: .Polygon, endpoint: Self.backup)   // another answer on the backup
        clock.advance(5 * 60)
        let preferred = await manager.preferred(for: .Polygon)
        XCTAssertEqual(preferred, Self.first, "the window counts from the fall-back, not the latest answer")
    }

    func testAFallBackAfterTheReturnStartsAWindowOfItsOwn() async {
        let clock = Clock()
        let manager = await manager(window: Self.window, clock: clock)
        await manager.setPreferred(for: .Polygon, endpoint: Self.backup)
        clock.advance(Self.window)
        var preferred = await manager.preferred(for: .Polygon)
        XCTAssertEqual(preferred, Self.first)
        // The first fails again; the backup answers: a new fall-back, a new window from now.
        await manager.setPreferred(for: .Polygon, endpoint: Self.backup)
        clock.advance(Self.window - 1)
        preferred = await manager.preferred(for: .Polygon)
        XCTAssertEqual(preferred, Self.backup)
        clock.advance(1)
        preferred = await manager.preferred(for: .Polygon)
        XCTAssertEqual(preferred, Self.first)
    }

    func testTheFirstEndpointPreferredNeverLapses() async {
        let clock = Clock()
        let manager = await manager(window: Self.window, clock: clock)
        await manager.setPreferred(for: .Polygon, endpoint: Self.first)
        clock.advance(10 * Self.window)
        let ordered = await manager.orderedEndpoints(for: .Polygon)
        XCTAssertEqual(ordered, [Self.first, Self.backup])
    }

    func testWithNoWindowAPreferenceHoldsUntilAnotherEndpointAnswers() async {
        let clock = Clock()
        let manager = await manager(window: nil, clock: clock)
        await manager.setPreferred(for: .Polygon, endpoint: Self.backup)
        clock.advance(24 * 60 * 60)
        let preferred = await manager.preferred(for: .Polygon)
        XCTAssertEqual(preferred, Self.backup, "the rule before 14g, kept by default")
    }

    func testAPreferenceTheListNoLongerHoldsIsIgnored() async {
        let clock = Clock()
        let manager = await manager(window: Self.window, clock: clock)
        await manager.setPreferred(for: .Polygon, endpoint: "https://rotated.example/rpc")
        let preferred = await manager.preferred(for: .Polygon)
        XCTAssertEqual(preferred, Self.first)
    }

    func testTheServiceCarriesItsWindow() async {
        let service = Web3ClientService.shared
        let before = await service.endpointReturnWindow
        XCTAssertNil(before, "no window until a host sets one")
        await service.configureEndpointReturn(after: Self.window)
        let window = await service.endpointReturnWindow
        XCTAssertEqual(window, Self.window)
        await service.configureEndpointReturn(after: before)
    }
}
