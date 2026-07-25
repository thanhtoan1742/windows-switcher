# Preview Overlay Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a decoupled preview overlay to Cmd+Tab cycling — thumbnails captured at Cmd-down, cycling swaps the on-screen thumbnail without raising, the selected window is raised once on Cmd-up.

**Architecture:** Extend the existing `WindowRaising` dependency-injection pattern in `WindowsSwitcherCore` with two sibling protocols (`ThumbnailCapturing`, `WindowPreviewing`). `Switcher` gains two new dependencies and changes from "raise on each tap" to "preview on each tap, raise on end". The app target supplies AppKit/CoreGraphics-backed implementations (`ThumbnailCapturer`, `ThumbnailOverlay`) and Screen Recording permission wiring.

**Tech Stack:** Swift 5.9, Swift Testing, CoreGraphics (`CGWindowListCreateImage`), ApplicationServices (`CGPreflightScreenCaptureAccess`, `CGRequestScreenCaptureAccess`), AppKit (`NSPanel`, `NSImageView`).

**Spec:** `docs/superpowers/specs/2026-07-25-preview-overlay-design.md`

---

## File Structure

**Create:**
- `Sources/WindowsSwitcher/ThumbnailCapturer.swift` — `ThumbnailCapturing` conformance; wraps `CGWindowListCreateImage`.
- `Sources/WindowsSwitcher/ThumbnailOverlay.swift` — `WindowPreviewing` conformance; borderless `NSPanel` + `NSImageView`.
- `Tests/WindowsSwitcherTests/PreviewingMocks.swift` — `MockPreviewer` and `MockCapturer` for `Switcher` tests.

**Modify:**
- `Sources/WindowsSwitcherCore/Switcher.swift` — add `ThumbnailCapturing` + `WindowPreviewing` protocols; rewrite `Switcher` to take three dependencies, capture at begin, preview on tap, raise on end.
- `Sources/WindowsSwitcher/main.swift` — wire new dependencies into `AppDelegate`; add Screen Recording preflight/prompt; add amber menubar-dot state.
- `Tests/WindowsSwitcherTests/SwitcherTests.swift` — rewrite for new call shape; add new cases.
- `README.md` — update "How it works", "Usage", "Limitations / Future work", and add Screen Recording to Requirements.

---

## Task 1: Add `ThumbnailCapturing` and `WindowPreviewing` protocols to Core

**Files:**
- Modify: `Sources/WindowsSwitcherCore/Switcher.swift` (add protocols above the existing `Switcher` class)

- [ ] **Step 1: Add the two new protocols to `Switcher.swift`**

Insert these protocols above the existing `public final class Switcher` line, immediately after the existing `WindowRaising` protocol definition:

```swift
public protocol ThumbnailCapturing: AnyObject {
    func capture(_ window: WindowInfo) -> CGImage?
}

public protocol WindowPreviewing: AnyObject {
    func show(thumbnails: [(WindowInfo, CGImage)], startingAt index: Int)
    func update(index: Int)
    func hide()
}
```

`Switcher.swift` already imports `CoreGraphics` (line 1), so `CGImage` is available. No new imports needed.

- [ ] **Step 2: Verify the core target still compiles**

Run: `swift build --target WindowsSwitcherCore`
Expected: BUILD SUCCEEDED (the protocols are unused so far, but compile fine).

- [ ] **Step 3: Commit**

```bash
git add Sources/WindowsSwitcherCore/Switcher.swift
git commit -m "feat(core): add ThumbnailCapturing and WindowPreviewing protocols"
```

---

## Task 2: Add mocks for `MockPreviewer` and `MockCapturer`

**Files:**
- Create: `Tests/WindowsSwitcherTests/PreviewingMocks.swift`

- [ ] **Step 1: Create the mocks file**

```swift
import Testing
import CoreGraphics
import Foundation
@testable import WindowsSwitcherCore

final class MockPreviewer: WindowPreviewing {
    var showCalls: [(thumbnails: [(WindowInfo, CGImage)], startingAt: Int)] = []
    var updateCalls: [Int] = []
    var hideCallCount: Int = 0

    func show(thumbnails: [(WindowInfo, CGImage)], startingAt index: Int) {
        showCalls.append((thumbnails, index))
    }
    func update(index: Int) { updateCalls.append(index) }
    func hide() { hideCallCount += 1 }
}

final class MockCapturer: ThumbnailCapturing {
    var results: [UInt32: CGImage?] = [:]   // windowID -> image or nil
    var captureOrder: [UInt32] = []
    var defaultReturn: CGImage? = nil

    func capture(_ window: WindowInfo) -> CGImage? {
        captureOrder.append(window.windowID)
        if let r = results[window.windowID] {
            return r
        }
        return defaultReturn
    }
}

/// Makes a 1x1 CGImage suitable as a placeholder thumbnail in tests.
func makeTestImage() -> CGImage? {
    let context = CGContext(
        data: nil, width: 1, height: 1,
        bitsPerComponent: 8, bytesPerRow: 4,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )
    return context?.makeImage()
}
```

- [ ] **Step 2: Verify mocks compile (tests won't pass yet — Switcher still has old shape)**

Run: `swift build --target WindowsSwitcherTests 2>&1 | head -20 || true`
Expected: Possible compile errors in `SwitcherTests.swift` (it still uses `Switcher(raiser:)`) — that's expected; the mocks file itself should not error. We rewrite `SwitcherTests` in Task 4. The build of the test target may fail; just confirm `PreviewingMocks.swift` has no syntax errors of its own by checking the output mentions only `SwitcherTests.swift`.

- [ ] **Step 3: Commit**

```bash
git add Tests/WindowsSwitcherTests/PreviewingMocks.swift
git commit -m "test: add MockPreviewer and MockCapturer for Switcher tests"
```

---

## Task 3: Rewrite `Switcher` for decoupled preview behavior

**Files:**
- Modify: `Sources/WindowsSwitcherCore/Switcher.swift` (rewrite the `Switcher` class)

- [ ] **Step 1: Rewrite the `Switcher` class body**

Replace the entire `public final class Switcher { ... }` block (everything from `public final class Switcher {` through the closing `}` at end of file) with:

```swift
public final class Switcher {
    private let raiser: WindowRaising
    private let previewer: WindowPreviewing
    private let capturer: ThumbnailCapturing
    private(set) var snapshot: [WindowInfo] = []
    private(set) var thumbnails: [CGImage] = []
    private(set) var cursor: Int = 0
    private(set) var isCmdDown: Bool = false

    public init(raiser: WindowRaising, previewer: WindowPreviewing, capturer: ThumbnailCapturing) {
        self.raiser = raiser
        self.previewer = previewer
        self.capturer = capturer
    }

    /// Called on Cmd-down. Captures a thumbnail per window, filters the snapshot
    /// to only successfully captured windows, and tells the previewer to show.
    /// If every capture failed, the session is a silent no-op (strict mode).
    public func beginSession(windows: [WindowInfo]) {
        let pairs: [(WindowInfo, CGImage)] = windows.compactMap {
            guard let img = capturer.capture($0) else { return nil }
            return ($0, img)
        }
        snapshot = pairs.map { $0.0 }
        thumbnails = pairs.map { $0.1 }
        cursor = 0
        isCmdDown = true
        guard !pairs.isEmpty else { return }
        previewer.show(thumbnails: pairs, startingAt: 0)
    }

    /// Called on Tab keydown while Cmd is held. `forward = !shift`. Advances the
    /// cursor and notifies the previewer. Does NOT raise. Returns true if the
    /// cursor advanced; false if the session was inactive or had <2 windows.
    @discardableResult
    public func tap(forward: Bool) -> Bool {
        guard isCmdDown, snapshot.count >= 2 else { return false }
        cursor = forward
            ? (cursor + 1) % snapshot.count
            : (cursor - 1 + snapshot.count) % snapshot.count
        previewer.update(index: cursor)
        return true
    }

    /// Called on Cmd-up. Hides the overlay and raises the selected window once.
    /// Guards `isCmdDown` so a stray Cmd-up with no prior Cmd-down is a no-op.
    public func endSession() {
        guard isCmdDown else { return }
        isCmdDown = false
        previewer.hide()
        guard snapshot.indices.contains(cursor) else { return }
        raiser.raise(snapshot[cursor])
    }
}
```

- [ ] **Step 2: Verify core compiles**

Run: `swift build --target WindowsSwitcherCore`
Expected: BUILD SUCCEEDED. (The test target and app target will still fail because they use `Switcher(raiser:)` — those are fixed in Tasks 4 and 5.)

- [ ] **Step 3: Commit**

```bash
git add Sources/WindowsSwitcherCore/Switcher.swift
git commit -m "feat(core): decouple raise from tap; preview on tap, raise on end"
```

---

## Task 4: Rewrite `SwitcherTests` for the new call shape

**Files:**
- Modify: `Tests/WindowsSwitcherTests/SwitcherTests.swift` (full rewrite)

- [ ] **Step 1: Rewrite the test file**

Replace the entire contents of `Tests/WindowsSwitcherTests/SwitcherTests.swift` with:

```swift
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
```

Note: `MockRaiser` stays in `SwitcherTests.swift` (its original location) to minimize churn. The new `MockPreviewer` and `MockCapturer` live in `PreviewingMocks.swift` (created in Task 2).

- [ ] **Step 2: Run tests to verify they pass**

Run: `./test.sh`
Expected: All tests pass, including the rewritten `Switcher` suite and the new all-nil and partial-capture cases.

- [ ] **Step 3: Commit**

```bash
git add Tests/WindowsSwitcherTests/SwitcherTests.swift
git commit -m "test: rewrite Switcher tests for decoupled preview behavior"
```

---

## Task 5: Implement `ThumbnailCapturer` in the app target

**Files:**
- Create: `Sources/WindowsSwitcher/ThumbnailCapturer.swift`

- [ ] **Step 1: Create the capturer**

```swift
import CoreGraphics
import WindowsSwitcherCore

/// Captures a single window's content as a `CGImage` via
/// `CGWindowListCreateImage`. Conforms to `ThumbnailCapturing` so the `Switcher`
/// can stay pure and unit-testable with a mock.
final class ThumbnailCapturer: ThumbnailCapturing {
    init() {}

    func capture(_ window: WindowInfo) -> CGImage? {
        CGWindowListCreateImage(
            window.bounds,
            .optionIncludingWindow,
            window.windowID,
            [.nominalResolution, .boundsIgnoreFraming]
        )
    }
}
```

- [ ] **Step 2: Verify the app target compiles**

Run: `swift build --target WindowsSwitcher`
Expected: BUILD SUCCEEDED. (The app target will still fail to link/run because `main.swift` still constructs `Switcher(raiser:)` — that's fixed in Task 7. `swift build --target WindowsSwitcher` builds the target's sources; if it fails on `main.swift`, proceed to Task 7 and re-check after.)

If `swift build --target WindowsSwitcher` fails due to `main.swift`'s `Switcher(raiser:)` call, that's expected — go to Task 7 to fix `main.swift`, then come back to confirm the whole app target builds.

- [ ] **Step 3: Commit**

```bash
git add Sources/WindowsSwitcher/ThumbnailCapturer.swift
git commit -m "feat: add ThumbnailCapturer wrapping CGWindowListCreateImage"
```

---

## Task 6: Implement `ThumbnailOverlay` in the app target

**Files:**
- Create: `Sources/WindowsSwitcher/ThumbnailOverlay.swift`

- [ ] **Step 1: Create the overlay**

```swift
import Cocoa
import CoreGraphics
import WindowsSwitcherCore

/// Centered, borderless, non-activating panel showing a single window thumbnail.
/// Conforms to `WindowPreviewing` so the `Switcher` can stay pure and unit-testable.
final class ThumbnailOverlay: WindowPreviewing {
    private let panel: NSPanel
    private let imageView: NSImageView
    private var pairs: [(WindowInfo, CGImage)] = []

    private static let maxSize = CGSize(width: 320, height: 240)

    init() {
        self.panel = NSPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .statusBar
        panel.hidesOnDeactivate = false
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        self.imageView = NSImageView()
        imageView.imageAlignment = .alignCenter
        imageView.imageScaling = .scaleProportionallyDown
        panel.contentView = imageView
    }

    func show(thumbnails: [(WindowInfo, CGImage)], startingAt index: Int) {
        pairs = thumbnails
        guard pairs.indices.contains(index) else { return }
        let cg = pairs[index].1
        imageView.image = NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
        panel.setContentSize(cappedSize(cg))
        centerOnMainScreen()
        panel.orderFront(nil)
        if index != 0 { update(index: index) }
    }

    func update(index: Int) {
        guard pairs.indices.contains(index) else { return }
        let cg = pairs[index].1
        imageView.image = NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
    }

    func hide() {
        panel.orderOut(nil)
        pairs = []
        imageView.image = nil
    }

    private func cappedSize(_ cg: CGImage) -> NSSize {
        let natural = NSSize(width: cg.width, height: cg.height)
        let max = ThumbnailOverlay.maxSize
        let scaleW = max.width / natural.width
        let scaleH = max.height / natural.height
        let scale = min(1.0, min(scaleW, scaleH))
        return NSSize(width: natural.width * scale, height: natural.height * scale)
    }

    private func centerOnMainScreen() {
        guard let screen = NSScreen.main else { return }
        let frame = screen.visibleFrame
        let pf = panel.frame
        let x = frame.midX - pf.width / 2
        let y = frame.midY - pf.height / 2
        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }
}
```

- [ ] **Step 2: Verify the file compiles in context**

Run: `swift build --target WindowsSwitcher 2>&1 | grep -i error || echo "no errors in ThumbnailOverlay"`
Expected: "no errors in ThumbnailOverlay" (errors from `main.swift`'s `Switcher(raiser:)` call are expected and handled in Task 7).

- [ ] **Step 3: Commit**

```bash
git add Sources/WindowsSwitcher/ThumbnailOverlay.swift
git commit -m "feat: add ThumbnailOverlay panel for preview display"
```

---

## Task 7: Wire new dependencies into `AppDelegate` and add Screen Recording permission

**Files:**
- Modify: `Sources/WindowsSwitcher/main.swift`

- [ ] **Step 1: Update `AppDelegate` to construct the new `Switcher` and wire previewer/capturer**

In `Sources/WindowsSwitcher/main.swift`, replace the `AppDelegate` class (lines 5 through 90) with:

```swift
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var eventTap: EventTap!
    private var switcher: Switcher!
    private var raiser: WindowRaiser!
    private var capturer: ThumbnailCapturer!
    private var previewer: ThumbnailOverlay!
    private var tapStarted: Bool = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        raiser = WindowRaiser()
        capturer = ThumbnailCapturer()
        previewer = ThumbnailOverlay()
        switcher = Switcher(raiser: raiser, previewer: previewer, capturer: capturer)
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = statusIcon()
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
        _ = CGPreflightScreenCaptureAccess() || CGRequestScreenCaptureAccess()
    }

    private func tryStartTap() {
        guard AXIsProcessTrusted() else {
            tapStarted = false
            statusItem.button?.image = statusIcon()
            buildMenu()
            return
        }
        do {
            try eventTap.start()
            tapStarted = true
        } catch {
            tapStarted = false
        }
        statusItem.button?.image = statusIcon()
        buildMenu()
    }

    @objc private func appActivated() {
        if !tapStarted { tryStartTap() }
        statusItem.button?.image = statusIcon()
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

    private func statusIcon() -> NSImage {
        let trusted = AXIsProcessTrusted()
        let screenRecordingOk = CGPreflightScreenCaptureAccess()
        let color: NSColor
        if !trusted { color = .systemRed }
        else if !screenRecordingOk { color = .systemOrange }
        else { color = .systemGreen }
        let image = NSImage(size: NSSize(width: 14, height: 14), flipped: false) { rect in
            color.setFill()
            NSBezierPath(ovalIn: rect.insetBy(dx: 2.5, dy: 2.5)).fill()
            return true
        }
        image.isTemplate = false
        return image
    }

    private func buildMenu() {
        let menu = NSMenu()
        let trusted = AXIsProcessTrusted()
        let screenRecordingOk = CGPreflightScreenCaptureAccess()
        let title: String
        if !trusted {
            title = "Windows Switcher: Needs Accessibility Permission"
        } else if !screenRecordingOk {
            title = "Windows Switcher: Needs Screen Recording Permission"
        } else {
            title = "Windows Switcher: Active"
        }
        menu.addItem(withTitle: title, action: nil, keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        statusItem.menu = menu
    }
}
```

Keep the bottom of `main.swift` unchanged (the `let app = NSApplication.shared ...` block).

- [ ] **Step 2: Build the whole package**

Run: `swift build`
Expected: BUILD SUCCEEDED.

- [ ] **Step 3: Build the .app bundle and run tests**

Run: `./test.sh && swift build -c release && ./make-app.sh`
Expected: Tests pass; release build succeeds; `WindowsSwitcher.app` is produced.

- [ ] **Step 4: Commit**

```bash
git add Sources/WindowsSwitcher/main.swift
git commit -m "feat: wire preview overlay and Screen Recording permission into app"
```

---

## Task 8: Update README

**Files:**
- Modify: `README.md`

- [ ] **Step 1: Update the Requirements section**

In `README.md`, find the Requirements section:

```
## Requirements

- macOS 12+
- Swift 5.9+ (builds with just Command Line Tools — no Xcode needed)
- **Accessibility permission** (the app prompts on first launch)
```

Replace with:

```
## Requirements

- macOS 12+
- Swift 5.9+ (builds with just Command Line Tools — no Xcode needed)
- **Accessibility permission** (the app prompts on first launch)
- **Screen Recording permission** (the app prompts on first launch; needed for window thumbnails)
```

- [ ] **Step 2: Update the Run section's first-launch steps**

Find:

```
On first launch:
1. A **red dot** appears in the menubar — the app needs Accessibility permission.
2. Open **System Settings → Privacy & Security → Accessibility** and enable *Windows Switcher*.
3. The dot turns **green** and Cmd+Tab now cycles windows.
```

Replace with:

```
On first launch:
1. A **red dot** appears in the menubar — the app needs Accessibility permission.
2. Open **System Settings → Privacy & Security → Accessibility** and enable *Windows Switcher*.
3. The dot turns **amber** — the app now needs Screen Recording permission (for window thumbnails).
4. Open **System Settings → Privacy & Security → Screen Recording** and enable *Windows Switcher*.
5. The dot turns **green** and Cmd+Tab now cycles windows with a preview overlay.
```

- [ ] **Step 3: Update the Usage section to describe the new behavior**

Find:

```
## Usage

| Shortcut | Action |
|----------|--------|
| Hold `Cmd` + tap `Tab` | Cycle forward through windows (most-recently-used) |
| Hold `Cmd` + tap `Shift`+`Tab` | Cycle backward |

The window list is snapshotted when you press Cmd, so cycling stays stable while you tap. Release Cmd to end the session; a fresh list is taken on the next Cmd+Tab.
```

Replace with:

```
## Usage

| Shortcut | Action |
|----------|--------|
| Hold `Cmd` + tap `Tab` | Cycle forward through windows (most-recently-used) |
| Hold `Cmd` + tap `Shift`+`Tab` | Cycle backward |

The window list and thumbnails are snapshotted when you press Cmd, so cycling stays stable while you tap. A centered preview shows the thumbnail of the currently selected window; nothing is raised until you release Cmd, which raises the selected window. A fresh snapshot is taken on the next Cmd+Tab.
```

- [ ] **Step 4: Update the "How it works" section**

Find:

```
## How it works

1. A system-wide `CGEventTap` intercepts `KeyDown` + `FlagsChanged` events.
2. A pure `KeyClassifier` translates each event into a `KeyAction` (`cmdDown`, `cmdUp`, `tabForward`, `tabBackward`, `ignore`).
3. On Cmd-down, `WindowLister` snapshots on-screen windows on the current Space via `CGWindowListCopyWindowInfo`.
4. Each Tab tap advances a cursor in a frozen MRU list and calls `WindowRaiser`.
5. `WindowRaiser` resolves the window's AX element by matching its frame and raises it via `AXUIElementPerformAction(kAXRaiseAction)`.

Only Tab keydowns with Cmd held are consumed; all other keystrokes pass through untouched.
```

Replace with:

```
## How it works

1. A system-wide `CGEventTap` intercepts `KeyDown` + `FlagsChanged` events.
2. A pure `KeyClassifier` translates each event into a `KeyAction` (`cmdDown`, `cmdUp`, `tabForward`, `tabBackward`, `ignore`).
3. On Cmd-down, `WindowLister` snapshots on-screen windows on the current Space via `CGWindowListCopyWindowInfo`, and `ThumbnailCapturer` captures each window's content via `CGWindowListCreateImage`.
4. Each Tab tap advances a cursor in the frozen list and updates a centered `ThumbnailOverlay` — no window is raised during cycling.
5. On Cmd-up, `WindowRaiser` resolves the selected window's AX element by matching its frame and raises it via `AXUIElementPerformAction(kAXRaiseAction)`.

Only Tab keydowns with Cmd held are consumed; all other keystrokes pass through untouched.
```

- [ ] **Step 5: Update the Project layout block and Limitations**

Find:

```
Sources/
  WindowsSwitcherCore/   # Testable core: WindowLister, Switcher, KeyClassifier, WindowRaiser, EventTap
  WindowsSwitcher/       # App entry point: AppDelegate + menubar status item
```

Replace with:

```
Sources/
  WindowsSwitcherCore/   # Testable core: WindowLister, Switcher, KeyClassifier, WindowRaiser, EventTap
  WindowsSwitcher/       # App entry point: AppDelegate, ThumbnailCapturer, ThumbnailOverlay
```

Find the Limitations section and replace its first bullet:

```
- **Current Space only** — windows on other Spaces are not included. Cross-Space support is isolated in `WindowLister.currentSpaceWindows()`.
```

with (add a bullet about Screen Recording at the end of the list — do not remove the existing private AX API bullet):

Find the existing last bullet of Limitations:

```
- **No autostart** — add it as a Login Item or LaunchAgent yourself.
```

Insert before it:

```
- **Screen Recording permission required** — without it, window thumbnails are blank and the session is a silent no-op (the menubar dot shows amber).
```

- [ ] **Step 6: Commit**

```bash
git add README.md
git commit -m "docs: update README for preview overlay and Screen Recording permission"
```

---

## Task 9: Final verification

- [ ] **Step 1: Run the full test suite**

Run: `./test.sh`
Expected: All tests pass (Swift Testing reports all suites green).

- [ ] **Step 2: Build the release .app**

Run: `swift build -c release && ./make-app.sh`
Expected: `WindowsSwitcher.app` produced with no errors.

- [ ] **Step 3: Smoke-test the .app (manual)**

Run: `open WindowsSwitcher.app`
Expected (manual check):
- Menubar dot appears. If Accessibility is already granted and Screen Recording is not, dot is amber; after granting both, dot is green.
- Hold Cmd + tap Tab: a centered thumbnail of the next window appears; windows do not shuffle while cycling.
- Release Cmd: the thumbnail disappears and the selected window comes to front.
- Cmd+Shift+Tab cycles backward.

Quit the app when done.

- [ ] **Step 4: Commit (if any final tweaks were needed)**

If the smoke test surfaced any fixes, commit them. Otherwise no commit needed.
