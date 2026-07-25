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

    // Helper: a Switcher wired with mocks and a capturer that returns a test
    // image for every window (the common case).
    private func makeSwitcher(capturer: MockCapturer = MockCapturer()) -> (Switcher, MockRaiser, MockPreviewer, MockCapturer) {
        let raiser = MockRaiser()
        let previewer = MockPreviewer()
        capturer.defaultReturn = makeTestImage()
        let s = Switcher(raiser: raiser, previewer: previewer, capturer: capturer)
        return (s, raiser, previewer, capturer)
    }

    @Test("beginSession captures per window, shows at index 0, no raise")
    func beginSession() {
        let (s, raiser, previewer, capturer) = makeSwitcher()
        s.beginSession(windows: [win(1), win(2), win(3)])
        #expect(s.snapshot.count == 3)
        #expect(s.cursor == 0)
        #expect(s.isCmdDown)
        #expect(capturer.captureOrder == [1, 2, 3])
        #expect(previewer.showCalls.count == 1)
        #expect(previewer.showCalls[0].startingAt == 0)
        #expect(previewer.showCalls[0].thumbnails.count == 3)
        #expect(raiser.raised.isEmpty)
    }

    @Test("tap forward advances cursor, updates previewer, does NOT raise")
    func tapForward() {
        let (s, raiser, previewer, _) = makeSwitcher()
        s.beginSession(windows: [win(1), win(2), win(3)])
        let advanced = s.tap(forward: true)
        #expect(advanced)
        #expect(s.cursor == 1)
        #expect(previewer.updateCalls == [1])
        #expect(raiser.raised.isEmpty)
    }

    @Test("tap backward wraps to end")
    func tapBackwardWraps() {
        let (s, raiser, previewer, _) = makeSwitcher()
        s.beginSession(windows: [win(1), win(2), win(3)])
        let advanced = s.tap(forward: false)
        #expect(advanced)
        #expect(s.cursor == 2)
        #expect(previewer.updateCalls == [2])
        #expect(raiser.raised.isEmpty)
    }

    @Test("tap forward wraps around")
    func tapForwardWraps() {
        let (s, raiser, previewer, _) = makeSwitcher()
        s.beginSession(windows: [win(1), win(2), win(3)])
        _ = s.tap(forward: true)
        _ = s.tap(forward: true)
        let advanced = s.tap(forward: true)
        #expect(advanced)
        #expect(s.cursor == 0)
        #expect(previewer.updateCalls == [1, 2, 0])
        #expect(raiser.raised.isEmpty)
    }

    @Test("repeated taps cycle through previewer updates, never raise")
    func repeatedTaps() {
        let (s, raiser, previewer, _) = makeSwitcher()
        s.beginSession(windows: [win(1), win(2), win(3)])
        for _ in 0..<6 { _ = s.tap(forward: true) }
        #expect(previewer.updateCalls == [1, 2, 0, 1, 2, 0])
        #expect(raiser.raised.isEmpty)
    }

    @Test("empty snapshot tap is no-op")
    func emptySnapshot() {
        let (s, raiser, previewer, _) = makeSwitcher()
        s.beginSession(windows: [])
        let advanced = s.tap(forward: true)
        #expect(!advanced)
        #expect(previewer.updateCalls.isEmpty)
        #expect(raiser.raised.isEmpty)
    }

    @Test("single window tap is no-op")
    func singleWindow() {
        let (s, raiser, previewer, _) = makeSwitcher()
        s.beginSession(windows: [win(1)])
        let advanced = s.tap(forward: true)
        #expect(!advanced)
        #expect(previewer.updateCalls.isEmpty)
        #expect(raiser.raised.isEmpty)
    }

    @Test("tap before begin is no-op")
    func tapBeforeBegin() {
        let (s, raiser, previewer, _) = makeSwitcher()
        let advanced = s.tap(forward: true)
        #expect(!advanced)
        #expect(previewer.updateCalls.isEmpty)
        #expect(raiser.raised.isEmpty)
    }

    @Test("endSession hides previewer and raises selected window once")
    func endSessionRaises() {
        let (s, raiser, previewer, _) = makeSwitcher()
        s.beginSession(windows: [win(1), win(2), win(3)])
        _ = s.tap(forward: true)
        s.endSession()
        #expect(!s.isCmdDown)
        #expect(previewer.hideCallCount == 1)
        #expect(raiser.raised.count == 1)
        #expect(raiser.raised[0].windowID == 2)
    }

    @Test("endSession without begin is no-op")
    func strayEndSession() {
        let (s, raiser, previewer, _) = makeSwitcher()
        s.endSession()
        #expect(previewer.hideCallCount == 0)
        #expect(raiser.raised.isEmpty)
    }

    @Test("endSession disables further taps")
    func endSessionDisablesTaps() {
        let (s, raiser, previewer, _) = makeSwitcher()
        s.beginSession(windows: [win(1), win(2)])
        s.endSession()
        let advanced = s.tap(forward: true)
        #expect(!advanced)
        #expect(previewer.updateCalls.isEmpty)
        #expect(raiser.raised.count == 1)  // only the endSession raise
    }

    @Test("new beginSession re-snapshots and re-captures")
    func reSnapshot() {
        let (s, raiser, previewer, capturer) = makeSwitcher()
        s.beginSession(windows: [win(1), win(2)])
        _ = s.tap(forward: true)
        s.endSession()
        s.beginSession(windows: [win(5), win(6), win(7)])
        #expect(s.snapshot.count == 3)
        #expect(s.cursor == 0)
        #expect(capturer.captureOrder == [1, 2, 5, 6, 7])
        #expect(previewer.showCalls.count == 2)
        #expect(previewer.showCalls[1].startingAt == 0)
        _ = s.tap(forward: true)
        s.endSession()
        #expect(raiser.raised.last?.windowID == 6)
    }

    @Test("all-nil capture: no show, no raise on end")
    func allNilCapture() {
        let capturer = MockCapturer()
        capturer.defaultReturn = nil
        let raiser = MockRaiser()
        let previewer = MockPreviewer()
        let s = Switcher(raiser: raiser, previewer: previewer, capturer: capturer)
        s.beginSession(windows: [win(1), win(2), win(3)])
        #expect(s.snapshot.isEmpty)
        #expect(previewer.showCalls.isEmpty)
        s.endSession()
        #expect(raiser.raised.isEmpty)
        #expect(previewer.hideCallCount == 1)  // endSession still hides
    }

    @Test("partial capture: failed windows excluded from snapshot")
    func partialCapture() {
        let capturer = MockCapturer()
        let img = makeTestImage()
        capturer.results = [1: img, 3: img]   // window 2 fails
        capturer.defaultReturn = nil
        let raiser = MockRaiser()
        let previewer = MockPreviewer()
        let s = Switcher(raiser: raiser, previewer: previewer, capturer: capturer)
        s.beginSession(windows: [win(1), win(2), win(3)])
        #expect(s.snapshot.count == 2)
        #expect(s.snapshot.map { $0.windowID } == [1, 3])
        #expect(previewer.showCalls.count == 1)
        #expect(previewer.showCalls[0].thumbnails.count == 2)
        // cycling stays within the filtered snapshot
        _ = s.tap(forward: true)
        #expect(s.cursor == 1)
        #expect(previewer.updateCalls == [1])
        s.endSession()
        #expect(raiser.raised.count == 1)
        #expect(raiser.raised[0].windowID == 3)
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
