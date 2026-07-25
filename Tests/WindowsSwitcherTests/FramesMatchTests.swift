import Testing
import CoreGraphics
@testable import WindowsSwitcherCore

@Suite("WindowRaiser.framesMatch")
struct FramesMatchTests {
    @Test func identicalFramesMatch() {
        let a = CGRect(x: 10, y: 20, width: 800, height: 600)
        let b = CGRect(x: 10, y: 20, width: 800, height: 600)
        #expect(WindowRaiser.framesMatch(a, b))
    }

    @Test func subPixelDifferenceTolerated() {
        let a = CGRect(x: 10, y: 20, width: 800, height: 600)
        let b = CGRect(x: 10.4, y: 19.7, width: 800.3, height: 599.6)
        #expect(WindowRaiser.framesMatch(a, b))
    }

    @Test func largeDifferenceDoesNotMatch() {
        let a = CGRect(x: 0, y: 0, width: 800, height: 600)
        let b = CGRect(x: 100, y: 100, width: 800, height: 600)
        #expect(!WindowRaiser.framesMatch(a, b))
    }

    @Test func sizeDifferenceDoesNotMatch() {
        let a = CGRect(x: 0, y: 0, width: 800, height: 600)
        let b = CGRect(x: 0, y: 0, width: 400, height: 300)
        #expect(!WindowRaiser.framesMatch(a, b))
    }

    @Test func epsilonBoundaryExactly1ptDoesNotMatch() {
        let a = CGRect(x: 0, y: 0, width: 800, height: 600)
        let b = CGRect(x: 1, y: 0, width: 800, height: 600)
        #expect(!WindowRaiser.framesMatch(a, b))
    }

    @Test func epsilonBoundaryJustUnder1ptMatches() {
        let a = CGRect(x: 0, y: 0, width: 800, height: 600)
        let b = CGRect(x: 0.99, y: 0, width: 800, height: 600)
        #expect(WindowRaiser.framesMatch(a, b))
    }
}
