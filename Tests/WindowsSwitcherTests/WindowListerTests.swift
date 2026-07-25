import Testing
import CoreGraphics
import Foundation
@testable import WindowsSwitcherCore

@Suite("WindowLister.filter")
struct WindowListerTests {
    private func entry(id: UInt32, pid: Int32, owner: String, layer: Int = 0,
                       alpha: Double = 1.0, bounds: [String: Any]? = ["X": 0, "Y": 0, "Width": 100, "Height": 100]) -> [String: Any] {
        var d: [String: Any] = [
            kCGWindowNumber as String: NSNumber(value: id),
            kCGWindowOwnerPID as String: NSNumber(value: pid),
            kCGWindowOwnerName as String: owner,
            kCGWindowLayer as String: NSNumber(value: layer),
            kCGWindowAlpha as String: NSNumber(value: alpha),
        ]
        if let bounds { d[kCGWindowBounds as String] = bounds }
        return d
    }

    @Test("keeps a normal window")
    func keepsNormalWindow() {
        let out = WindowLister.filter([entry(id: 1, pid: 100, owner: "Safari")])
        #expect(out.count == 1)
        #expect(out[0].windowID == 1)
        #expect(out[0].ownerPID == 100)
        #expect(out[0].ownerName == "Safari")
    }

    @Test("filters non-zero layer")
    func filtersNonZeroLayer() {
        let out = WindowLister.filter([entry(id: 1, pid: 100, owner: "X", layer: 3)])
        #expect(out.isEmpty)
    }

    @Test("filters zero alpha")
    func filtersZeroAlpha() {
        let out = WindowLister.filter([entry(id: 1, pid: 100, owner: "X", alpha: 0.0)])
        #expect(out.isEmpty)
    }

    @Test("filters zero bounds")
    func filtersZeroBounds() {
        let out = WindowLister.filter([entry(id: 1, pid: 100, owner: "X", bounds: ["X": 0, "Y": 0, "Width": 0, "Height": 0])])
        #expect(out.isEmpty)
    }

    @Test("filters missing bounds")
    func filtersMissingBounds() {
        let out = WindowLister.filter([entry(id: 1, pid: 100, owner: "X", bounds: nil)])
        #expect(out.isEmpty)
    }

    @Test("filters system owners")
    func filtersSystemOwners() {
        let out = WindowLister.filter([
            entry(id: 1, pid: 100, owner: "Dock"),
            entry(id: 2, pid: 101, owner: "SystemUIServer"),
            entry(id: 3, pid: 102, owner: "WindowServer"),
            entry(id: 4, pid: 103, owner: "Control Center"),
            entry(id: 5, pid: 104, owner: "Safari"),
        ])
        #expect(out.count == 1)
        #expect(out[0].ownerName == "Safari")
    }

    @Test("preserves front-to-back order")
    func preservesOrder() {
        let out = WindowLister.filter([
            entry(id: 10, pid: 1, owner: "A"),
            entry(id: 20, pid: 2, owner: "B"),
            entry(id: 30, pid: 3, owner: "C"),
        ])
        #expect(out.map { $0.windowID } == [10, 20, 30])
    }
}
