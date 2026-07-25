import Testing
import CoreGraphics
@testable import WindowsSwitcherCore

@Suite("KeyClassifier.classify")
struct KeyClassifierTests {
    private let leftCmd: UInt16 = 0x37
    private let rightCmd: UInt16 = 0x36
    private let tab: UInt16 = 0x30
    private let shift: UInt16 = 0x38

    @Test func leftCmdDown() {
        #expect(KeyClassifier.classify(keyCode: leftCmd, flags: .maskCommand, isKeyDown: false) == .cmdDown)
    }

    @Test func leftCmdUp() {
        #expect(KeyClassifier.classify(keyCode: leftCmd, flags: [], isKeyDown: false) == .cmdUp)
    }

    @Test func rightCmdDown() {
        #expect(KeyClassifier.classify(keyCode: rightCmd, flags: .maskCommand, isKeyDown: false) == .cmdDown)
    }

    @Test func rightCmdUp() {
        #expect(KeyClassifier.classify(keyCode: rightCmd, flags: [], isKeyDown: false) == .cmdUp)
    }

    @Test func tabForward() {
        #expect(KeyClassifier.classify(keyCode: tab, flags: .maskCommand, isKeyDown: true) == .tabForward)
    }

    @Test func tabBackward() {
        #expect(KeyClassifier.classify(keyCode: tab, flags: [.maskCommand, .maskShift], isKeyDown: true) == .tabBackward)
    }

    @Test func tabForwardWithOption() {
        #expect(KeyClassifier.classify(keyCode: tab, flags: [.maskCommand, .maskAlternate], isKeyDown: true) == .tabForward)
    }

    @Test func tabBackwardWithControl() {
        #expect(KeyClassifier.classify(keyCode: tab, flags: [.maskCommand, .maskShift, .maskControl], isKeyDown: true) == .tabBackward)
    }

    @Test func tabKeyUpIsIgnored() {
        #expect(KeyClassifier.classify(keyCode: tab, flags: .maskCommand, isKeyDown: false) == .ignore)
    }

    @Test func tabWithoutCmdIsIgnored() {
        #expect(KeyClassifier.classify(keyCode: tab, flags: [], isKeyDown: true) == .ignore)
    }

    @Test func otherKeyCodeIsIgnored() {
        #expect(KeyClassifier.classify(keyCode: 0x00, flags: .maskCommand, isKeyDown: true) == .ignore)
    }

    @Test func shiftAloneIsIgnored() {
        #expect(KeyClassifier.classify(keyCode: shift, flags: .maskShift, isKeyDown: false) == .ignore)
    }

    @Test func cmdDownWithShiftHeld() {
        #expect(KeyClassifier.classify(keyCode: leftCmd, flags: [.maskCommand, .maskShift], isKeyDown: false) == .cmdDown)
    }

    @Test func cmdUpWithShiftResidual() {
        #expect(KeyClassifier.classify(keyCode: leftCmd, flags: .maskShift, isKeyDown: false) == .cmdUp)
    }
}
