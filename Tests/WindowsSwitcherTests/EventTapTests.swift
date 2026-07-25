import Testing
import CoreGraphics
@testable import WindowsSwitcherCore

@Suite("EventTap.decide")
struct EventTapTests {
    @Test func reenablesOnTapDisabledByTimeout() {
        let d = EventTap.decide(type: .tapDisabledByTimeout, action: .ignore)
        #expect(d == .reenable)
    }
    @Test func reenablesOnTapDisabledByUserInput() {
        let d = EventTap.decide(type: .tapDisabledByUserInput, action: .ignore)
        #expect(d == .reenable)
    }
    @Test func consumesTabForward() {
        let d = EventTap.decide(type: .keyDown, action: .tabForward)
        #expect(d == .consume)
    }
    @Test func consumesTabBackward() {
        let d = EventTap.decide(type: .keyDown, action: .tabBackward)
        #expect(d == .consume)
    }
    @Test func passthroughOnCmdDown() {
        let d = EventTap.decide(type: .flagsChanged, action: .cmdDown)
        #expect(d == .passthrough)
    }
    @Test func passthroughOnCmdUp() {
        let d = EventTap.decide(type: .flagsChanged, action: .cmdUp)
        #expect(d == .passthrough)
    }
    @Test func passesOnIgnore() {
        let d = EventTap.decide(type: .keyDown, action: .ignore)
        #expect(d == .pass)
    }
}
