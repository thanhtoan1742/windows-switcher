import Testing
import CoreGraphics
@testable import WindowsSwitcherCore

@Suite("RaiseMatcher.matchIndex")
struct RaiseMatcherTests {
    private func target(_ id: UInt32, _ frame: CGRect) -> WindowInfo {
        WindowInfo(windowID: id, ownerPID: 1, ownerName: "app",
                   bounds: frame, layer: 0, alpha: 1.0)
    }

    @Test func windowIDMatchWinsOverFrameMatch() {
        // candidate 0 has matching frame; candidate 1 has matching windowID.
        // Pass 1 (windowID) must pick candidate 1, not the frame match.
        let target = self.target(99, CGRect(x: 0, y: 0, width: 800, height: 600))
        let candidates: [(windowID: CGWindowID?, frame: CGRect?)] = [
            (1, CGRect(x: 0, y: 0, width: 800, height: 600)),  // frame match
            (99, CGRect(x: 50, y: 50, width: 400, height: 300)),  // windowID match
        ]
        #expect(RaiseMatcher.matchIndex(candidates: candidates, target: target) == 1)
    }

    @Test func frameFallbackWhenNoWindowIDMatch() {
        let target = self.target(99, CGRect(x: 10, y: 20, width: 800, height: 600))
        let candidates: [(windowID: CGWindowID?, frame: CGRect?)] = [
            (1, CGRect(x: 10, y: 20, width: 800, height: 600)),  // frame matches
            (2, CGRect(x: 0, y: 0, width: 100, height: 100)),
        ]
        #expect(RaiseMatcher.matchIndex(candidates: candidates, target: target) == 0)
    }

    @Test func frameFallbackUsesEpsilon() {
        let target = self.target(99, CGRect(x: 0, y: 0, width: 800, height: 600))
        let candidates: [(windowID: CGWindowID?, frame: CGRect?)] = [
            (1, CGRect(x: 0.99, y: 0, width: 800, height: 600)),  // within 1pt epsilon
        ]
        #expect(RaiseMatcher.matchIndex(candidates: candidates, target: target) == 0)
    }

    @Test func returnsNilWhenNoMatch() {
        let target = self.target(99, CGRect(x: 0, y: 0, width: 800, height: 600))
        let candidates: [(windowID: CGWindowID?, frame: CGRect?)] = [
            (1, CGRect(x: 100, y: 100, width: 100, height: 100)),
            (2, CGRect(x: 500, y: 500, width: 100, height: 100)),
        ]
        #expect(RaiseMatcher.matchIndex(candidates: candidates, target: target) == nil)
    }

    @Test func nilWindowIDAndFrameCandidatesAreSkipped() {
        let target = self.target(99, CGRect(x: 0, y: 0, width: 800, height: 600))
        let candidates: [(windowID: CGWindowID?, frame: CGRect?)] = [
            (nil, nil),  // skipped by both passes
            (99, nil),   // windowID match despite missing frame
        ]
        #expect(RaiseMatcher.matchIndex(candidates: candidates, target: target) == 1)
    }

    @Test func emptyCandidatesReturnsNil() {
        let target = self.target(99, CGRect(x: 0, y: 0, width: 800, height: 600))
        #expect(RaiseMatcher.matchIndex(candidates: [], target: target) == nil)
    }
}
