# Windows Switcher Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace macOS Cmd+Tab application-switching with Windows/Linux-style window switching across all windows on the current Space, via a minimal native Swift/AppKit background app.

**Architecture:** Swift Package with a `WindowsSwitcherCore` library (testable logic: window listing, cycling state machine, key classification, AX raiser, event tap) and a `WindowsSwitcher` executable (AppDelegate + menubar status item). A `CGEventTap` intercepts Cmd+Tab, a frozen MRU snapshot drives an instant in-place cycling state machine, and `AXUIElementPerformAction(kAXRaiseAction)` raises the chosen cross-app window.

**Tech Stack:** Swift 5.9 (tools-version), macOS 12+, AppKit, CoreGraphics, ApplicationServices (Accessibility). No third-party dependencies. Built with `swift build`; bundled into `WindowsSwitcher.app` with `make-app.sh`. Tests use **Swift Testing** (`import Testing`, `@Test`, `#expect`) instead of XCTest, because this environment has only CommandLineTools (no Xcode). The `test.sh` wrapper at the repo root supplies the framework/macro/rpath flags `swift test` needs to find the `Testing.framework` that ships with CommandLineTools. Run tests with `./test.sh` (supports extra args, e.g. `./test.sh --filter WindowsSwitcherTests`).

---

## File Structure

```
WindowsSwitcher/
├── Package.swift                          # SwiftPM manifest (core lib + executable + test target)
├── test.sh                                # swift test wrapper that wires up the Testing framework paths
├── make-app.sh                            # Assembles WindowsSwitcher.app from the release binary
├── Info.plist                             # Bundle metadata, LSUIElement=true (background app)
├── docs/superpowers/specs/                # Design spec (already written)
├── docs/superpowers/plans/                # This plan
├── Sources/
│   ├── WindowsSwitcherCore/
│   │   ├── WindowLister.swift             # WindowInfo model + filter() + currentSpaceWindows()
│   │   ├── Switcher.swift                 # WindowRaising protocol + Switcher state machine
│   │   ├── KeyClassifier.swift            # Pure classify(keyCode,flags,isKeyDown) -> KeyAction
│   │   ├── WindowRaiser.swift             # AX raise impl + pure framesMatch() helper
│   │   └── EventTap.swift                 # CGEventTapCreate wrapper, dispatches KeyAction
│   └── WindowsSwitcher/
│       └── main.swift                     # NSApplication entry, AppDelegate, NSStatusItem
└── Tests/
    └── WindowsSwitcherTests/
        ├── WindowListerTests.swift         # Filter fixtures
        ├── SwitcherTests.swift             # Cycling state machine with MockRaiser
        └── KeyClassifierTests.swift        # classify() pure tests
```

**Responsibilities & boundaries:**
- `WindowLister` owns the *set* of switchable windows (current Space now; cross-Space later is isolated here).
- `Switcher` owns the *cycling state* (snapshot, cursor, session lifecycle) and delegates raising to a `WindowRaising` protocol — so it is pure and unit-testable with a mock.
- `KeyClassifier` is a pure function translating a raw key event into a `KeyAction` — testable without a real event tap.
- `WindowRaiser` is the AX integration (not unit-testable; verified by running the app) but extracts one pure helper `framesMatch()` that is tested.
- `EventTap` wires `CGEventTapCreate` to `KeyClassifier` and a handler closure — integration only.
- `main.swift` is the composition root:AppDelegate owns the tap, switcher, raiser, and status item.

---

### Task 1: Project scaffold

**Files:**
- Create: `Package.swift`
- Create: `test.sh` (Swift Testing wrapper for CommandLineTools-only environments)
- Create: `Sources/WindowsSwitcherCore/WindowLister.swift` (placeholder)
- Create: `Sources/WindowsSwitcher/main.swift` (placeholder)
- Create: `Tests/WindowsSwitcherTests/ScaffoldTests.swift`

- [ ] **Step 1: Create `Package.swift`**

```swift
// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "WindowsSwitcher",
    platforms: [.macOS(.v12)],
    targets: [
        .target(
            name: "WindowsSwitcherCore",
            path: "Sources/WindowsSwitcherCore"
        ),
        .executableTarget(
            name: "WindowsSwitcher",
            dependencies: ["WindowsSwitcherCore"],
            path: "Sources/WindowsSwitcher"
        ),
        .testTarget(
            name: "WindowsSwitcherTests",
            dependencies: ["WindowsSwitcherCore"],
            path: "Tests/WindowsSwitcherTests"
        )
    ]
)
```

- [ ] **Step 2: Create `test.sh`**

```bash
#!/bin/bash
# Swift Testing wrapper for environments with only CommandLineTools (no Xcode).
# The Testing framework and its macro plugin ship with CommandLineTools but live
# off the default search paths, so we point swift test at them explicitly.
set -euo pipefail
exec swift test \
  -Xswiftc -F -Xswiftc /Library/Developer/CommandLineTools/Library/Developer/Frameworks/ \
  -Xswiftc -load-plugin-library -Xswiftc /Library/Developer/CommandLineTools/usr/lib/swift/host/plugins/testing/libTestingMacros.dylib \
  -Xlinker -rpath -Xlinker /Library/Developer/CommandLineTools/Library/Developer/Frameworks/ \
  -Xlinker -rpath -Xlinker /Library/Developer/CommandLineTools/Library/Developer/usr/lib/ \
  "$@"
```

Then `chmod +x test.sh`.

- [ ] **Step 3: Create placeholder `Sources/WindowsSwitcherCore/WindowLister.swift`**

```swift
import CoreGraphics

// Placeholder — real content added in Task 2.
```

- [ ] **Step 4: Create placeholder `Sources/WindowsSwitcher/main.swift`**

```swift
import Cocoa

// Placeholder — real content added in Task 7.
```

- [ ] **Step 5: Create `Tests/WindowsSwitcherTests/ScaffoldTests.swift`**

```swift
import Testing
@testable import WindowsSwitcherCore

@Suite("Scaffold")
struct ScaffoldTests {
    @Test("scaffold compiles")
    func scaffoldCompiles() {
        #expect(true)
    }
}
```

- [ ] **Step 6: Initialize git and verify the build + tests pass**

Run:
```bash
git init
git add -A
git commit -m "chore: scaffold Swift Package"
./test.sh
```
Expected: `./test.sh` compiles all targets and `Scaffold/scaffold compiles` passes.

---

### Task 2: WindowLister — filter + currentSpaceWindows

**Files:**
- Modify: `Sources/WindowsSwitcherCore/WindowLister.swift`
- Create: `Tests/WindowsSwitcherTests/WindowListerTests.swift`

- [ ] **Step 1: Write the failing tests**

```swift
import Testing
import CoreGraphics
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
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `./test.sh --filter WindowListerTests`
Expected: FAIL — `WindowLister` / `WindowInfo` do not exist.

- [ ] **Step 3: Implement `WindowLister.swift`**

```swift
import CoreGraphics

struct WindowInfo: Equatable {
    let windowID: CGWindowID
    let ownerPID: pid_t
    let ownerName: String
    let bounds: CGRect
    let layer: Int
    let alpha: Double
}

enum WindowLister {
    /// Filter raw CGWindowList entries down to actual switchable windows, preserving
    /// the front-to-back order returned by the Window Server (index 0 == frontmost).
    static func filter(_ raw: [[String: Any]]) -> [WindowInfo] {
        var out: [WindowInfo] = []
        for entry in raw {
            guard let layer = (entry[kCGWindowLayer as String] as? NSNumber)?.intValue,
                  layer == 0 else { continue }
            guard let alpha = (entry[kCGWindowAlpha as String] as? NSNumber)?.doubleValue,
                  alpha > 0 else { continue }
            guard let wid = (entry[kCGWindowNumber as String] as? NSNumber)?.uint32Value else { continue }
            guard let pid = (entry[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value else { continue }
            let ownerName = (entry[kCGWindowOwnerName as String] as? String) ?? ""
            guard let boundsDict = entry[kCGWindowBounds as String] as? [String: Any],
                  let bounds = CGRect(dictionaryRepresentation: boundsDict as CFDictionary),
                  bounds.width > 0, bounds.height > 0 else { continue }
            if isSystemOwner(ownerName) { continue }
            out.append(WindowInfo(
                windowID: wid, ownerPID: pid, ownerName: ownerName,
                bounds: bounds, layer: layer, alpha: alpha
            ))
        }
        return out
    }

    /// Live fetch from the Window Server. `.optionOnScreenOnly` is Space-aware so this
    /// returns only windows on the current Space. Cross-Space support would change only
    /// this method (see spec "Non-Goals").
    static func currentSpaceWindows() -> [WindowInfo] {
        guard let raw = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[String: Any]] else { return [] }
        return filter(raw)
    }

    private static let systemOwners: Set<String> = [
        "Dock", "SystemUIServer", "WindowServer",
        "Control Center", "Wallpaper", "WindowManager"
    ]
    private static func isSystemOwner(_ name: String) -> Bool {
        systemOwners.contains(name)
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `./test.sh --filter WindowListerTests`
Expected: PASS (7 tests).

- [ ] **Step 5: Commit**

```bash
git add Sources/WindowsSwitcherCore/WindowLister.swift Tests/WindowsSwitcherTests/WindowListerTests.swift
git commit -m "feat: window lister filters switchable windows on current Space"
```

---

### Task 3: Switcher cycling state machine

**Files:**
- Create: `Sources/WindowsSwitcherCore/Switcher.swift`
- Create: `Tests/WindowsSwitcherTests/SwitcherTests.swift`

- [ ] **Step 1: Write the failing tests**

```swift
import Testing
import CoreGraphics
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
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `./test.sh --filter SwitcherTests`
Expected: FAIL — `WindowRaising` / `Switcher` undefined.

- [ ] **Step 3: Implement `Switcher.swift`**

```swift
import CoreGraphics

protocol WindowRaising: AnyObject {
    @discardableResult
    func raise(_ window: WindowInfo) -> Bool
}

/// Cycling state machine for window switching. Pure: raises are delegated to a
/// `WindowRaising` instance so this class is fully unit-testable with a mock.
final class Switcher {
    private let raiser: WindowRaising
    private(set) var snapshot: [WindowInfo] = []
    private(set) var cursor: Int = 0
    private(set) var isCmdDown: Bool = false

    init(raiser: WindowRaising) {
        self.raiser = raiser
    }

    /// Called on Cmd-down. Freezes the MRU window list for the session. The frontmost
    /// window (index 0) is already in front so no raise is issued here.
    func beginSession(windows: [WindowInfo]) {
        snapshot = windows
        cursor = 0
        isCmdDown = true
    }

    /// Called on Tab keydown while Cmd is held. `forward = !shift`.
    /// Returns true if a window was raised; false if the session was inactive or
    /// there was nothing to cycle to.
    @discardableResult
    func tap(forward: Bool) -> Bool {
        guard isCmdDown, snapshot.count >= 2 else { return false }
        cursor = forward
            ? (cursor + 1) % snapshot.count
            : (cursor - 1 + snapshot.count) % snapshot.count
        return raiser.raise(snapshot[cursor])
    }

    /// Called on Cmd-up. Ends the session; subsequent taps are no-ops until the
    /// next `beginSession`.
    func endSession() {
        isCmdDown = false
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `./test.sh --filter SwitcherTests`
Expected: PASS (10 tests).

- [ ] **Step 5: Commit**

```bash
git add Sources/WindowsSwitcherCore/Switcher.swift Tests/WindowsSwitcherTests/SwitcherTests.swift
git commit -m "feat: pure cycling state machine with mockable raiser"
```

---

### Task 4: KeyClassifier (pure)

**Files:**
- Create: `Sources/WindowsSwitcherCore/KeyClassifier.swift`
- Create: `Tests/WindowsSwitcherTests/KeyClassifierTests.swift`

- [ ] **Step 1: Write the failing tests**

```swift
import Testing
import CoreGraphics
@testable import WindowsSwitcherCore

@Suite("KeyClassifier.classify")
struct KeyClassifierTests {
    private let cmdKeyCode: UInt16 = 0x37
    private let tabKeyCode: UInt16 = 0x30

    @Test func cmdDown() {
        #expect(KeyClassifier.classify(keyCode: cmdKeyCode, flags: .maskCommand, isKeyDown: false) == .cmdDown)
    }

    @Test func cmdUp() {
        #expect(KeyClassifier.classify(keyCode: cmdKeyCode, flags: [], isKeyDown: false) == .cmdUp)
    }

    @Test func tabForward() {
        #expect(KeyClassifier.classify(keyCode: tabKeyCode, flags: .maskCommand, isKeyDown: true) == .tabForward)
    }

    @Test func tabBackward() {
        #expect(KeyClassifier.classify(keyCode: tabKeyCode, flags: [.maskCommand, .maskShift], isKeyDown: true) == .tabBackward)
    }

    @Test func tabKeyUpIsIgnored() {
        #expect(KeyClassifier.classify(keyCode: tabKeyCode, flags: .maskCommand, isKeyDown: false) == .ignore)
    }

    @Test func tabWithoutCmdIsIgnored() {
        #expect(KeyClassifier.classify(keyCode: tabKeyCode, flags: [], isKeyDown: true) == .ignore)
    }

    @Test func otherKeyCodeIsIgnored() {
        #expect(KeyClassifier.classify(keyCode: 0x00, flags: .maskCommand, isKeyDown: true) == .ignore)
    }

    @Test func shiftAloneIsIgnored() {
        let shiftKeyCode: UInt16 = 0x38
        #expect(KeyClassifier.classify(keyCode: shiftKeyCode, flags: .maskShift, isKeyDown: false) == .ignore)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `./test.sh --filter KeyClassifierTests`
Expected: FAIL — `KeyClassifier` undefined.

- [ ] **Step 3: Implement `KeyClassifier.swift`**

```swift
import CoreGraphics

enum KeyAction {
    case cmdDown
    case cmdUp
    case tabForward
    case tabBackward
    case ignore
}

/// Pure translation of a raw key event into a `KeyAction`. Extracted so the event
/// tap callback stays a thin adapter and the classification is unit-testable.
enum KeyClassifier {
    static let cmdKeyCode: UInt16 = 0x37  // kVK_Command
    static let tabKeyCode: UInt16 = 0x30  // kVK_Tab

    static func classify(keyCode: UInt16, flags: CGEventFlags, isKeyDown: Bool) -> KeyAction {
        // FlagsChanged for the Cmd key: presence of .maskCommand == pressed, absence == released.
        if keyCode == cmdKeyCode {
            return flags.contains(.maskCommand) ? .cmdDown : .cmdUp
        }
        // Tab keydown with Cmd held — Shift selects direction.
        if keyCode == tabKeyCode, isKeyDown, flags.contains(.maskCommand) {
            return flags.contains(.maskShift) ? .tabBackward : .tabForward
        }
        return .ignore
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `./test.sh --filter KeyClassifierTests`
Expected: PASS (8 tests).

- [ ] **Step 5: Commit**

```bash
git add Sources/WindowsSwitcherCore/KeyClassifier.swift Tests/WindowsSwitcherTests/KeyClassifierTests.swift
git commit -m "feat: pure key classifier for cmd+tab events"
```

---

### Task 5: WindowRaiser (AX) + framesMatch helper

**Files:**
- Create: `Sources/WindowsSwitcherCore/WindowRaiser.swift`
- Create: `Tests/WindowsSwitcherTests/FramesMatchTests.swift`

Note: the AX plumbing (`AXUIElementCreateApplication`, `kAXRaiseAction`, etc.) cannot be unit-tested because `AXUIElement` values cannot be constructed outside a live Accessibility session. Only the pure `framesMatch()` helper is unit-tested; the integration is verified manually in Task 8 by running the app.

- [ ] **Step 1: Write the failing test for `framesMatch`**

```swift
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
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `./test.sh --filter FramesMatchTests`
Expected: FAIL — `WindowRaiser.framesMatch` undefined.

- [ ] **Step 3: Implement `WindowRaiser.swift`**

```swift
import ApplicationServices
import Cocoa
import CoreGraphics

/// Raises a cross-app window via the Accessibility API. Conforms to `WindowRaising`
/// so the `Switcher` can stay pure and unit-testable.
final class WindowRaiser: WindowRaising {
    @discardableResult
    func raise(_ window: WindowInfo) -> Bool {
        let app = AXUIElementCreateApplication(window.ownerPID)
        var windowsRef: CFArray?
        guard AXUIElementCopyAttributeValue(
            app, kAXWindowsAttribute as CFString, &windowsRef
        ) == .success,
        let axWindows = windowsRef as? [AXUIElement] else {
            return false
        }
        for ax in axWindows {
            guard let frame = axFrame(ax) else { continue }
            guard WindowRaiser.framesMatch(frame, window.bounds) else { continue }
            AXUIElementSetMessagingTimeout(ax, 0.2)
            AXUIElementPerformAction(ax, kAXRaiseAction as CFString)
            AXUIElementSetAttributeValue(ax, kAXMainAttribute as CFString, kCFBooleanTrue)
            if let running = NSRunningApplication(processIdentifier: window.ownerPID) {
                running.activate()
            }
            return true
        }
        return false
    }

    private func axFrame(_ ax: AXUIElement) -> CGRect? {
        var posRef: CFTypeRef?
        var sizeRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(ax, kAXPositionAttribute as CFString, &posRef) == .success,
              AXUIElementCopyAttributeValue(ax, kAXSizeAttribute as CFString, &sizeRef) == .success,
              let posVal = posRef, let sizeVal = sizeRef else {
            return nil
        }
        var origin = CGPoint.zero
        var size = CGSize.zero
        AXValueGetValue(posVal as! AXValue, .cgPoint, &origin)
        AXValueGetValue(sizeVal as! AXValue, .cgSize, &size)
        return CGRect(origin: origin, size: size)
    }

    /// Pure helper: AX does not expose the CGWindowID, so we match an AX window to a
    /// CGWindowList entry by frame. Tolerant of sub-pixel rounding (1pt epsilon).
    static func framesMatch(_ a: CGRect, _ b: CGRect, epsilon: CGFloat = 1) -> Bool {
        abs(a.origin.x - b.origin.x) < epsilon &&
        abs(a.origin.y - b.origin.y) < epsilon &&
        abs(a.width - b.width) < epsilon &&
        abs(a.height - b.height) < epsilon
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `./test.sh --filter FramesMatchTests`
Expected: PASS (4 tests).

- [ ] **Step 5: Run the full suite to confirm no regressions**

Run: `./test.sh`
Expected: PASS (all tests across all tasks).

- [ ] **Step 6: Commit**

```bash
git add Sources/WindowsSwitcherCore/WindowRaiser.swift Tests/WindowsSwitcherTests/FramesMatchTests.swift
git commit -m "feat: AX window raiser with frame-matching helper"
```

---

### Task 6: EventTap wrapper

**Files:**
- Create: `Sources/WindowsSwitcherCore/EventTap.swift`

Note: `CGEventTapCreate` requires Accessibility permission and cannot be unit-tested in-process. The classification logic it depends on is already covered by `KeyClassifierTests`. This task is integration-only; verified by running the app in Task 8.

- [ ] **Step 1: Implement `EventTap.swift`**

```swift
import CoreGraphics

enum EventTapError: Error {
    case creationFailed
}

/// Wraps a system-wide `CGEventTap` for `KeyDown` + `FlagsChanged`. Translates each
/// event to a `KeyAction` via `KeyClassifier` and dispatches it to `handler`. Tab
/// keydowns that we handle are consumed (return nil); Cmd flag events pass through
/// so the rest of the system still sees Cmd state.
final class EventTap {
    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private let handler: (KeyAction) -> Void

    init(handler: @escaping (KeyAction) -> Void) {
        self.handler = handler
    }

    func start() throws {
        let mask = CGEventMask(
            (1 << CGEventType.keyDown.rawValue) |
            (1 << CGEventType.flagsChanged.rawValue)
        )
        let userInfo = Unmanaged.passUnretained(self).toOpaque()
        guard let port = CGEventTapCreate(
            .cgSessionEventTap,
            .headInsertEventTap,
            .defaultTap,
            mask,
            EventTap.callback,
            userInfo
        ) else {
            throw EventTapError.creationFailed
        }
        self.tap = port
        let source = CFMachPortCreateRunLoopSource(nil, port, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
        self.runLoopSource = source
        CGEventTapEnable(port, true)
    }

    func stop() {
        if let tap { CGEventTapEnable(tap, false) }
        if let runLoopSource { CFRunLoopRemoveSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes) }
        tap = nil
        runLoopSource = nil
    }

    private static let callback: CGEventTapCallBack = { _, type, event, userInfo in
        guard let userInfo else { return Unmanaged.passRetained(event) }
        let self = Unmanaged<EventTap>.fromOpaque(userInfo).takeUnretainedValue()

        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap = self.tap { CGEventTapEnable(tap, true) }
            return Unmanaged.passRetained(event)
        }

        let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
        let action = KeyClassifier.classify(
            keyCode: keyCode, flags: event.flags, isKeyDown: type == .keyDown
        )
        switch action {
        case .tabForward, .tabBackward:
            self.handler(action)
            return nil  // consume
        case .cmdDown, .cmdUp:
            self.handler(action)
            return Unmanaged.passRetained(event)  // let Cmd state reach the system
        case .ignore:
            return Unmanaged.passRetained(event)
        }
    }
}
```

- [ ] **Step 2: Build to confirm it compiles**

Run: `swift build`
Expected: builds with no errors.

- [ ] **Step 3: Run full suite to confirm no regressions**

Run: `./test.sh`
Expected: PASS (EventTap is not exercised by tests, but the build must still succeed).

- [ ] **Step 4: Commit**

```bash
git add Sources/WindowsSwitcherCore/EventTap.swift
git commit -m "feat: CGEventTap wrapper dispatching KeyActions"
```

---

### Task 7: AppDelegate + menubar status item

**Files:**
- Modify: `Sources/WindowsSwitcher/main.swift`

Note: This is the composition root and is integration-only (verified by running the app in Task 8).

- [ ] **Step 1: Implement `main.swift`**

```swift
import Cocoa
import WindowsSwitcherCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var eventTap: EventTap!
    private var switcher: Switcher!
    private var raiser: WindowRaiser!
    private var tapStarted: Bool = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        raiser = WindowRaiser()
        switcher = Switcher(raiser: raiser)
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = statusIcon(trusted: AXIsProcessTrusted())
        buildMenu()

        eventTap = EventTap { [weak self] action in
            self?.handle(action)
        }
        tryStartTap()

        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(appActivated),
            name: NSWorkspace.didActivateApplicationNotification, object: nil
        )
        _ = AXIsProcessTrustedWithOptions(
            [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        )
    }

    private func tryStartTap() {
        guard AXIsProcessTrusted() else {
            tapStarted = false
            statusItem.button?.image = statusIcon(trusted: false)
            return
        }
        do {
            try eventTap.start()
            tapStarted = true
            statusItem.button?.image = statusIcon(trusted: true)
        } catch {
            tapStarted = false
            statusItem.button?.image = statusIcon(trusted: false)
        }
    }

    @objc private func appActivated() {
        if !tapStarted { tryStartTap() }
    }

    private func handle(_ action: KeyAction) {
        switch action {
        case .cmdDown:
            switcher.beginSession(windows: WindowLister.currentSpaceWindows())
        case .cmdUp:
            switcher.endSession()
        case .tabForward:
            switcher.tap(forward: true)
        case .tabBackward:
            switcher.tap(forward: false)
        case .ignore:
            break
        }
    }

    private func statusIcon(trusted: Bool) -> NSImage {
        let image = NSImage(size: NSSize(width: 14, height: 14), flipped: false) { rect in
            (trusted ? NSColor.systemGreen : NSColor.systemRed).setFill()
            NSBezierPath(ovalIn: rect.insetBy(dx: 2.5, dy: 2.5)).fill()
            return true
        }
        image.isTemplate = false
        return image
    }

    private func buildMenu() {
        let menu = NSMenu()
        let title = AXIsProcessTrusted()
            ? "Windows Switcher: Active"
            : "Windows Switcher: Needs Accessibility Permission"
        menu.addItem(withTitle: title, action: nil, keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        statusItem.menu = menu
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
```

- [ ] **Step 2: Build the release binary**

Run: `swift build -c release`
Expected: builds with no errors.

- [ ] **Step 3: Run full suite to confirm no regressions**

Run: `./test.sh`
Expected: PASS.

- [ ] **Step 4: Commit**

```bash
git add Sources/WindowsSwitcher/main.swift
git commit -m "feat: app delegate with menubar status item and tap wiring"
```

---

### Task 8: Bundle assembly (Info.plist + make-app.sh)

**Files:**
- Create: `Info.plist`
- Create: `make-app.sh`

- [ ] **Step 1: Create `Info.plist`**

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>WindowsSwitcher</string>
    <key>CFBundleIdentifier</key>
    <string>com.toan.windowsswitcher</string>
    <key>CFBundleName</key>
    <string>Windows Switcher</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>LSMinimumSystemVersion</key>
    <string>12.0</string>
    <key>LSUIElement</key>
    <true/>
</dict>
</plist>
```

- [ ] **Step 2: Create `make-app.sh`**

```bash
#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"

BIN=.build/release/WindowsSwitcher
APP=WindowsSwitcher.app

if [ ! -f "$BIN" ]; then
    echo "Release binary not found. Run: swift build -c release" >&2
    exit 1
fi

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp "$BIN" "$APP/Contents/MacOS/WindowsSwitcher"
cp Info.plist "$APP/Contents/Info.plist"
echo "Built $APP"
```

- [ ] **Step 3: Make the script executable and assemble the bundle**

Run:
```bash
chmod +x make-app.sh
swift build -c release && ./make-app.sh && ls -d WindowsSwitcher.app
```
Expected: prints `Built WindowsSwitcher.app` and `ls` shows `WindowsSwitcher.app`.

- [ ] **Step 4: Smoke-test the bundle launches (manual)**

Run: `open WindowsSwitcher.app`
Expected: a green (or red, if Accessibility not yet granted) dot appears in the menubar. If red, grant Accessibility permission in System Settings → Privacy & Security → Accessibility, then relaunch. With permission granted, pressing Cmd+Tab should cycle through windows on the current Space; Cmd+Shift+Tab cycles backward. Quit via the menubar item.

- [ ] **Step 5: Commit**

```bash
git add Info.plist make-app.sh
git commit -m "chore: bundle assembly into WindowsSwitcher.app"
```

---

## Manual verification checklist (after Task 8)

- [ ] App appears as a menubar dot only (no Dock icon) — `LSUIElement` working.
- [ ] Green dot when Accessibility is granted; red dot when not.
- [ ] Cmd+Tab cycles forward through windows of multiple apps (not just apps).
- [ ] Cmd+Shift+Tab cycles backward.
- [ ] Holding Cmd and tapping Tab multiple times steps through a stable MRU list.
- [ ] Releasing Cmd ends the session; a fresh Cmd+Tab re-snapshots the list.
- [ ] Windows on other Spaces are not included (current-Space scope).
- [ ] Minimized windows are not included.
- [ ] Other Cmd shortcuts (Cmd+Space, Cmd+Q, Cmd+C in a text field) still work — only Cmd+Tab is intercepted.

## Future work (explicit non-goals in the spec)

- Cross-Space window cycling: change only `WindowLister.currentSpaceWindows()`.
- Overlay / thumbnails.
- Autostart via Login Items / LaunchAgent.
- Minimized-window cycling.
- Robust window matching beyond frame epsilon (private `CGSAssociation` or `kCGWindowNumber` via AX private attribute).
