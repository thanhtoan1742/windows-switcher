import Testing
import CoreGraphics
import Foundation
@testable import WindowsSwitcherCore

@Suite("Switcher")
struct SwitcherTests {
    private func win(_ id: UInt32, _ pid: Int32 = 1) -> WindowInfo {
        WindowInfo(windowID: id, ownerPID: pid, ownerName: "app\(id)",
                    bounds: CGRect(x: 0, y: 0, width: 100, height: 100), layer: 0, alpha: 1.0)
    }

    @Test("beginSession stores snapshot and resets cursor, no raise on begin")
    func beginSession() {
        let mock = MockRaiser()
        let s = Switcher(raiser: mock)
        s.beginSession(windows: [win(1), win(2), win(3)])
        #expect(s.snapshot.count == 3)
        #expect(s.cursor == 0)
        #expect(s.isCmdDown)
        #expect(mock.raised.isEmpty)
    }

    @Test("tap forward advances cursor and raises")
    func tapForward() {
        let mock = MockRaiser()
        let s = Switcher(raiser: mock)
        s.beginSession(windows: [win(1), win(2), win(3)])
        let raised = s.tap(forward: true)
        #expect(raised)
        #expect(s.cursor == 1)
        #expect(mock.raised.map { $0.windowID } == [2])
    }

    @Test("tap backward wraps to end")
    func tapBackwardWraps() {
        let mock = MockRaiser()
        let s = Switcher(raiser: mock)
        s.beginSession(windows: [win(1), win(2), win(3)])
        let raised = s.tap(forward: false)
        #expect(raised)
        #expect(s.cursor == 2)
        #expect(mock.raised.map { $0.windowID } == [3])
    }

    @Test("tap forward wraps around")
    func tapForwardWraps() {
        let mock = MockRaiser()
        let s = Switcher(raiser: mock)
        s.beginSession(windows: [win(1), win(2), win(3)])
        _ = s.tap(forward: true)
        _ = s.tap(forward: true)
        let raised = s.tap(forward: true)
        #expect(raised)
        #expect(s.cursor == 0)
        #expect(mock.raised.map { $0.windowID } == [2, 3, 1])
    }

    @Test("repeated taps cycle through")
    func repeatedTaps() {
        let mock = MockRaiser()
        let s = Switcher(raiser: mock)
        s.beginSession(windows: [win(1), win(2), win(3)])
        for _ in 0..<6 { _ = s.tap(forward: true) }
        #expect(mock.raised.map { $0.windowID } == [2, 3, 1, 2, 3, 1])
    }

    @Test("empty snapshot tap is no-op")
    func emptySnapshot() {
        let mock = MockRaiser()
        let s = Switcher(raiser: mock)
        s.beginSession(windows: [])
        let raised = s.tap(forward: true)
        #expect(!raised)
        #expect(mock.raised.isEmpty)
    }

    @Test("single window tap is no-op")
    func singleWindow() {
        let mock = MockRaiser()
        let s = Switcher(raiser: mock)
        s.beginSession(windows: [win(1)])
        let raised = s.tap(forward: true)
        #expect(!raised)
        #expect(mock.raised.isEmpty)
    }

    @Test("tap before begin is no-op")
    func tapBeforeBegin() {
        let mock = MockRaiser()
        let s = Switcher(raiser: mock)
        let raised = s.tap(forward: true)
        #expect(!raised)
        #expect(mock.raised.isEmpty)
    }

    @Test("endSession disables taps")
    func endSession() {
        let mock = MockRaiser()
        let s = Switcher(raiser: mock)
        s.beginSession(windows: [win(1), win(2)])
        s.endSession()
        #expect(!s.isCmdDown)
        let raised = s.tap(forward: true)
        #expect(!raised)
        #expect(mock.raised.isEmpty)
    }

    @Test("new beginSession re-snapshots")
    func reSnapshot() {
        let mock = MockRaiser()
        let s = Switcher(raiser: mock)
        s.beginSession(windows: [win(1), win(2)])
        _ = s.tap(forward: true)
        s.endSession()
        s.beginSession(windows: [win(5), win(6), win(7)])
        #expect(s.snapshot.count == 3)
        #expect(s.cursor == 0)
        let raised = s.tap(forward: true)
        #expect(raised)
        #expect(mock.raised.last?.windowID == 6)
    }
}

final class MockRaiser: WindowRaising {
    var raised: [WindowInfo] = []
    var returnSuccess: Bool = true
    @discardableResult
    func raise(_ window: WindowInfo) -> Bool {
        raised.append(window)
        return returnSuccess
    }
}
