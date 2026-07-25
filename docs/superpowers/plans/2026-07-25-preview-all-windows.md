# Preview All Windows (Row Overlay) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the single centered thumbnail with a horizontal row showing all window thumbnails at once, with a selection ring that moves on Tab and a single raise on Cmd-up.

**Architecture:** The `WindowPreviewing` protocol and `Switcher` core are untouched — the protocol already passes the full `pairs` array and cursor index. The only code change is a rewrite of `ThumbnailOverlay.swift` (app target): single `NSPanel` + custom container with N `NSImageView` subviews laid out manually side-by-side, a uniform cell size computed to shrink-to-fit the screen, and a `CALayer` border ring toggled on the selected cell. `main.swift` is unchanged (class name stays `ThumbnailOverlay`).

**Tech Stack:** Swift 5.9, AppKit (`NSPanel`, `NSImageView`, `CALayer` border), CoreGraphics, Swift Testing (regression gate via existing 42 tests).

**Spec:** `docs/superpowers/specs/2026-07-25-preview-all-windows-design.md`

---

## File Structure

**Rewrite:**
- `Sources/WindowsSwitcher/ThumbnailOverlay.swift` — row layout replaces single-image layout. Class name stays `ThumbnailOverlay` so `main.swift` is unchanged.

**Modify:**
- `README.md` — "How it works" step 4, "Usage" paragraph, and intro bullet describe the row instead of a single thumbnail.

**No change:**
- `Sources/WindowsSwitcherCore/Switcher.swift` (protocol + state machine unchanged)
- `Sources/WindowsSwitcher/main.swift` (wiring unchanged)
- `Tests/WindowsSwitcherTests/PreviewingMocks.swift` (mocks unchanged)
- `Tests/WindowsSwitcherTests/SwitcherTests.swift` (14 tests unchanged — protocol contract intact)

---

## Task 1: Rewrite `ThumbnailOverlay` to render a horizontal row with a selection ring

**Files:**
- Rewrite: `Sources/WindowsSwitcher/ThumbnailOverlay.swift`

**Note on testing:** The `WindowPreviewing` protocol contract is unchanged, so the 14 existing `SwitcherTests` (using `MockPreviewer`) and the 42-test total serve as the regression gate. App-target rendering (`ThumbnailOverlay`) is verified manually per project convention (same as `ThumbnailCapturer`, `WindowRaiser`, `EventTap` — see README "Tests" section). There are no new unit tests to write for this task.

- [ ] **Step 1: Replace the entire contents of `Sources/WindowsSwitcher/ThumbnailOverlay.swift` with the row implementation**

```swift
import Cocoa
import CoreGraphics
import WindowsSwitcherCore

/// Centered, borderless, non-activating panel showing all window thumbnails
/// in a horizontal row. A selection ring indicates the currently-selected
/// window. Conforms to `WindowPreviewing` so the `Switcher` can stay pure
/// and unit-testable.
final class ThumbnailOverlay: WindowPreviewing {
    private let panel: NSPanel
    private var pairs: [(WindowInfo, CGImage)] = []
    private var imageViews: [NSImageView] = []
    private var selectedIndex: Int = 0

    private static let margin: CGFloat = 40
    private static let spacing: CGFloat = 8
    private static let maxCell = CGSize(width: 240, height: 180)
    private static let minCell = CGSize(width: 80, height: 60)
    private static let aspect = maxCell.height / maxCell.width   // 0.75 (4:3)
    private static let borderWidth: CGFloat = 3
    private static let cornerRadius: CGFloat = 6

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
    }

    func show(thumbnails: [(WindowInfo, CGImage)], startingAt index: Int) {
        guard !thumbnails.isEmpty else { return }
        tearDownCells()
        pairs = thumbnails
        let cellSize = computeCellSize(count: pairs.count)
        buildCells(cellSize: cellSize)
        layoutRow(cellSize: cellSize)
        sizeAndCenterPanel(cellSize: cellSize)
        applyImages()
        panel.orderFront(nil)
        guard pairs.indices.contains(index) else { return }
        selectedIndex = index
        applyRing(to: index)
    }

    func update(index: Int) {
        guard pairs.indices.contains(index) else { return }
        if selectedIndex != index {
            imageViews[selectedIndex].layer?.borderWidth = 0
        }
        selectedIndex = index
        imageViews[index].layer?.borderWidth = ThumbnailOverlay.borderWidth
        imageViews[index].layer?.borderColor = NSColor.controlAccentColor.cgColor
    }

    func hide() {
        panel.orderOut(nil)
        tearDownCells()
        pairs = []
        selectedIndex = 0
    }

    // MARK: - Cell sizing

    private func computeCellSize(count: Int) -> CGSize {
        guard let screen = NSScreen.main else {
            return ThumbnailOverlay.maxCell
        }
        let availWidth = screen.visibleFrame.width - 2 * ThumbnailOverlay.margin
        let naturalWidth = (availWidth - CGFloat(count - 1) * ThumbnailOverlay.spacing) / CGFloat(count)
        let cellWidth = min(ThumbnailOverlay.maxCell.width,
                            max(ThumbnailOverlay.minCell.width, naturalWidth))
        let cellHeight = cellWidth * ThumbnailOverlay.aspect
        return CGSize(width: cellWidth, height: cellHeight)
    }

    // MARK: - Cell building

    private func buildCells(cellSize: CGSize) {
        for _ in 0..<pairs.count {
            let cell = NSImageView()
            cell.imageScaling = .scaleProportionallyDown
            cell.imageAlignment = .alignCenter
            cell.wantsLayer = true
            cell.layer?.cornerRadius = ThumbnailOverlay.cornerRadius
            cell.layer?.masksToBounds = true
            cell.frame = CGRect(origin: .zero, size: cellSize)
            panel.contentView?.addSubview(cell)
            imageViews.append(cell)
        }
    }

    private func layoutRow(cellSize: CGSize) {
        let stride = cellSize.width + ThumbnailOverlay.spacing
        for (i, cell) in imageViews.enumerated() {
            let origin = CGPoint(x: CGFloat(i) * stride, y: 0)
            cell.frame = CGRect(origin: origin, size: cellSize)
        }
    }

    private func sizeAndCenterPanel(cellSize: CGSize) {
        let n = imageViews.count
        let rowWidth = CGFloat(n) * cellSize.width + CGFloat(n - 1) * ThumbnailOverlay.spacing
        let rowHeight = cellSize.height
        panel.setContentSize(CGSize(width: rowWidth, height: rowHeight))
        guard let screen = NSScreen.main else { return }
        let frame = screen.visibleFrame
        let x = frame.midX - rowWidth / 2
        let y = frame.midY - rowHeight / 2
        panel.setFrameOrigin(CGPoint(x: x, y: y))
    }

    private func applyImages() {
        for (i, pair) in pairs.enumerated() {
            let cg = pair.1
            imageViews[i].image = NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
        }
    }

    private func applyRing(to index: Int) {
        imageViews[index].layer?.borderWidth = ThumbnailOverlay.borderWidth
        imageViews[index].layer?.borderColor = NSColor.controlAccentColor.cgColor
    }

    private func tearDownCells() {
        for cell in imageViews {
            cell.image = nil
            cell.layer?.borderWidth = 0
            cell.removeFromSuperview()
        }
        imageViews.removeAll()
        selectedIndex = 0
    }
}
```

Key points the implementer should preserve:
- The `guard !thumbnails.isEmpty` at the top of `show` is defensive — the `Switcher` core won't call `show` with zero pairs, but the cell-size math divides by `count` and must not divide by zero.
- `tearDownCells()` is called at the start of `show` and in `hide()`, so a fresh session rebuilds cells from scratch and `hide()` is idempotent.
- `selectedIndex` is reset to 0 in `tearDownCells()` and re-set in `show()` after cells are built.
- The ring uses `NSColor.controlAccentColor` (system accent) and a 3pt `CALayer` border; toggling `borderWidth` between 0 and 3 does not reflow the row.

- [ ] **Step 2: Verify the app target compiles**

Run: `swift build --target WindowsSwitcher`
Expected: BUILD SUCCEEDED. (If `main.swift` errors appear, they are pre-existing — this task does not touch `main.swift`. The class name `ThumbnailOverlay` is unchanged, so the `Switcher(raiser:previewer:capturer:)` wiring in `main.swift` still resolves.)

- [ ] **Step 3: Run the full test suite as a regression gate**

Run: `./test.sh`
Expected: All 42 tests pass, including the 14 `Switcher` tests that assert the `WindowPreviewing` protocol contract via `MockPreviewer`. No test files were modified, so all suites should be green unchanged. If any test fails, the rewrite accidentally broke the protocol conformance — compare the `show`/`update`/`hide` method signatures against the original.

- [ ] **Step 4: Commit**

```bash
git add Sources/WindowsSwitcher/ThumbnailOverlay.swift
git commit -m "feat: show all window thumbnails in a row with a selection ring"
```

---

## Task 2: Update README to describe the row overlay

**Files:**
- Modify: `README.md`

- [ ] **Step 1: Update the intro bullet (line 7)**

Find:

```
- **Preview overlay** — a centered thumbnail of the selected window; nothing is raised until you release Cmd
```

Replace with:

```
- **Preview overlay** — all window thumbnails shown at once in a centered row; a selection ring moves as you cycle, and nothing is raised until you release Cmd
```

- [ ] **Step 2: Update the Usage paragraph (line 48)**

Find:

```
The window list and thumbnails are snapshotted when you press Cmd, so cycling stays stable while you tap. A centered preview shows the thumbnail of the currently selected window; nothing is raised until you release Cmd, which raises the selected window. A fresh snapshot is taken on the next Cmd+Tab.
```

Replace with:

```
The window list and thumbnails are snapshotted when you press Cmd, so cycling stays stable while you tap. A centered row shows all window thumbnails at once; a selection ring moves across the row as you tap Tab, and nothing is raised until you release Cmd, which raises the selected window. A fresh snapshot is taken on the next Cmd+Tab.
```

- [ ] **Step 3: Update the "How it works" step 4 (line 55)**

Find:

```
4. Each Tab tap advances a cursor in the frozen list and updates a centered `ThumbnailOverlay` — no window is raised during cycling.
```

Replace with:

```
4. Each Tab tap advances a cursor in the frozen list and moves a selection ring across a centered row of `ThumbnailOverlay` thumbnails — no window is raised during cycling.
```

- [ ] **Step 4: Commit**

```bash
git add README.md
git commit -m "docs: update README for all-windows row overlay"
```

---

## Task 3: Final verification

- [ ] **Step 1: Run the full test suite**

Run: `./test.sh`
Expected: All 42 tests pass (Swift Testing reports all suites green).

- [ ] **Step 2: Build the release .app**

Run: `swift build -c release && ./make-app.sh`
Expected: `WindowsSwitcher.app` produced with no errors.

- [ ] **Step 3: Smoke-test the .app (manual)**

Run: `open WindowsSwitcher.app`
Expected (manual check):
- Menubar dot appears (green if both permissions already granted; amber if Screen Recording still needed).
- Hold Cmd + tap Tab: a centered row of all window thumbnails appears; the selection ring starts on the leftmost and moves right on Tab.
- Shift+Tab moves the ring left; wraps at both ends.
- All thumbnails stay the same size; only the ring moves.
- Release Cmd: the row hides and the ringed window comes to front.
- With many windows open, thumbnails shrink to fit; at extreme counts the row overflows symmetrically.

Quit the app when done.

- [ ] **Step 4: Commit (if any final tweaks were needed)**

If the smoke test surfaced any fixes, commit them. Otherwise no commit needed.
