# Menubar Icon Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the flat colored-circle menubar icon with the SF Symbol `arrow.right.arrow.left.square` tinted to the menubar foreground, plus a warning-only red/amber corner badge shown when a permission is missing; keep the icon correct across dark/light appearance and the menu-open blue highlight.

**Architecture:** `statusIcon()` in `Sources/WindowsSwitcher/main.swift` is replaced by `statusImages()` returning a small `StatusImages` struct (`primary`, `alternate`). The primary image is the symbol tinted `controlTextColor` with the badge; the alternate image (used while the menu is open) is the symbol tinted white with the same badge. The composed image is `isTemplate = false` so the badge color is preserved. A block-based KVO observer on `NSApp.effectiveAppearance` re-runs the existing refresh path on dark/light toggle. No core-logic change; no new tests (pure presentation, verified manually per project convention).

**Tech Stack:** Swift 5.9, AppKit (`NSStatusItem`, `NSImage`, `NSImage(systemSymbolName:accessibilityDescription:)`, KVO on `effectiveAppearance`), CoreGraphics.

**Spec:** `docs/superpowers/specs/2026-07-25-menubar-icon-design.md`

---

## File Structure

**Modify:**
- `Sources/WindowsSwitcher/main.swift` — replace `statusIcon()` with `statusImages()`; add `StatusImages` struct; add appearance KVO observer token + `refreshStatusIcon()` helper; update all existing call sites (`applicationDidFinishLaunching`, `tryStartTap`, `appActivated`) to call `refreshStatusIcon()` instead of assigning `statusIcon()` directly.

**Modify:**
- `README.md` — replace the "red dot / amber dot / green dot" wording in the launch-steps list (lines 36-40) with the new symbol + warning-badge wording.

**No change:**
- `Sources/WindowsSwitcherCore/*` — no core logic touched.
- `Tests/WindowsSwitcherTests/*` — no new pure logic; AppKit rendering is verified manually (same convention as `ThumbnailOverlay`, `ThumbnailCapturer`, `EventTap`).

---

## Task 1: Replace `statusIcon()` with `statusImages()` + `StatusImages` struct and update all call sites

**Files:**
- Modify: `Sources/WindowsSwitcher/main.swift` (whole `AppDelegate` body)

**Note on testing:** Pure AppKit presentation; no unit-testable pure logic is introduced. The regression gate is the existing test suite (`./test.sh`), which must still pass. Visual correctness is verified manually in Task 4.

- [ ] **Step 1: Replace the `statusIcon()` method and add the `StatusImages` struct + `refreshStatusIcon()` helper**

In `Sources/WindowsSwitcher/main.swift`, delete the existing `private func statusIcon() -> NSImage { ... }` method (lines 83-97 in the current file) and replace it with the block below. Also add a `private var appearanceObserver: NSKeyValueObservation?` property near the other `private var` declarations at the top of the `AppDelegate` class.

```swift
    private struct StatusImages {
        let primary: NSImage
        let alternate: NSImage
    }

    private func statusImages() -> StatusImages {
        let trusted = AXIsProcessTrusted()
        let screenRecordingOk = CGPreflightScreenCaptureAccess()
        let badgeColor: NSColor?
        if !trusted { badgeColor = .systemRed }
        else if !screenRecordingOk { badgeColor = .systemOrange }
        else { badgeColor = nil }

        let symbol = NSImage(
            systemSymbolName: "arrow.right.arrow.left.square",
            accessibilityDescription: "Windows Switcher"
        )!
        let canvasSize = NSSize(width: 18, height: 18)
        let symbolSize = NSSize(width: 14, height: 14)
        let badgeRadius: CGFloat = 3.0
        let badgeInset: CGFloat = 1.5

        func compose(symbolTint: NSColor) -> NSImage {
            let image = NSImage(size: canvasSize, flipped: false) { rect in
                let symbolRect = NSRect(
                    x: (canvasSize.width - symbolSize.width) / 2,
                    y: (canvasSize.height - symbolSize.height) / 2,
                    width: symbolSize.width,
                    height: symbolSize.height
                )
                let tinted = symbol.tinted(symbolTint)
                tinted.draw(in: symbolRect,
                            from: .zero,
                            operation: .sourceOver,
                            fraction: 1.0)
                if let badgeColor {
                    let badgeRect = NSRect(
                        x: rect.maxX - badgeInset - badgeRadius * 2,
                        y: rect.maxY - badgeInset - badgeRadius * 2,
                        width: badgeRadius * 2,
                        height: badgeRadius * 2
                    )
                    badgeColor.setFill()
                    NSBezierPath(ovalIn: badgeRect).fill()
                }
                return true
            }
            image.isTemplate = false
            return image
        }

        return StatusImages(
            primary: compose(symbolTint: .controlTextColor),
            alternate: compose(symbolTint: .white)
        )
    }

    private func refreshStatusIcon() {
        let images = statusImages()
        statusItem.button?.image = images.primary
        statusItem.button?.alternateImage = images.alternate
    }
```

Note: `NSImage.tinted(_:)` is not a stock AppKit method. Step 2 adds it as a private extension in the same file.

- [ ] **Step 2: Add a private `NSImage.tinted(_:)` extension at the bottom of `Sources/WindowsSwitcher/main.swift`**

Append this after the `MainActor.assumeIsolated { ... }` block at the end of the file:

```swift
private extension NSImage {
    func tinted(_ color: NSColor) -> NSImage {
        let tinted = NSImage(size: size, flipped: false) { rect in
            self.draw(in: rect)
            color.set()
            rect.fill(using: .sourceAtop)
            return true
        }
        tinted.isTemplate = false
        return tinted
    }
}
```

- [ ] **Step 3: Replace every `statusItem.button?.image = statusIcon()` call site with `refreshStatusIcon()`**

There are exactly three call sites in the current file:

1. In `applicationDidFinishLaunching` (line 20): replace
   ```swift
           statusItem.button?.image = statusIcon()
   ```
   with
   ```swift
           refreshStatusIcon()
   ```

2. In `tryStartTap()`, the `guard` early-return branch (line 41): replace
   ```swift
           statusItem.button?.image = statusIcon()
   ```
   with
   ```swift
           refreshStatusIcon()
   ```

3. In `tryStartTap()`, after the `do/catch` (line 51): replace
   ```swift
           statusItem.button?.image = statusIcon()
   ```
   with
   ```swift
           refreshStatusIcon()
   ```

4. In `appActivated()` (line 57): replace
   ```swift
           statusItem.button?.image = statusIcon()
   ```
   with
   ```swift
           refreshStatusIcon()
   ```

- [ ] **Step 4: Build to verify it compiles**

Run: `swift build`
Expected: Build succeeds with no errors. If `NSImage(systemSymbolName:accessibilityDescription:)` is flagged, confirm `LSMinimumSystemVersion` is `12.0` in `Info.plist` (it is) and that the SDK is macOS 11+.

- [ ] **Step 5: Commit**

```bash
git add Sources/WindowsSwitcher/main.swift
git commit -m "feat(menubar): SF Symbol icon with warning-only corner badge"
```

---

## Task 2: Add an `NSApp.effectiveAppearance` KVO observer to re-render on dark/light toggle

**Files:**
- Modify: `Sources/WindowsSwitcher/main.swift`

- [ ] **Step 1: Add the `appearanceObserver` property**

Near the top of the `AppDelegate` class, beside `private var tapStarted: Bool = false`, add:

```swift
    private var appearanceObserver: NSKeyValueObservation?
```

- [ ] **Step 2: Register the observer in `applicationDidFinishLaunching`**

In `applicationDidFinishLaunching`, immediately after the line `refreshStatusIcon()` (added in Task 1 Step 3.1) and before `buildMenu()`, insert:

```swift
        appearanceObserver = NSApp.observe(\.effectiveAppearance, options: [.new]) { [weak self] _, _ in
            MainActor.assumeIsolated {
                self?.refreshStatusIcon()
            }
        }
```

Rationale: `AppDelegate` is `@MainActor`; the KVO closure fires on the main thread, and `MainActor.assumeIsolated` satisfies the actor isolation checker. The block-based `NSKeyValueObservation` self-invalidates when `appearanceObserver` is released (on dealloc), so no explicit `removeObserver` is needed.

- [ ] **Step 3: Build to verify it compiles**

Run: `swift build`
Expected: Build succeeds.

- [ ] **Step 4: Commit**

```bash
git add Sources/WindowsSwitcher/main.swift
git commit -m "feat(menubar): re-render icon on system appearance change"
```

---

## Task 3: Update README menubar wording

**Files:**
- Modify: `README.md` (lines 36-40 in the current file)

- [ ] **Step 1: Replace the launch-steps list block**

In `README.md`, replace this exact block (currently lines 36-40):

```markdown
1. A **red dot** appears in the menubar — the app needs Accessibility permission.
2. Open **System Settings → Privacy & Security → Accessibility** and enable *Windows Switcher*.
3. The dot turns **amber** — the app now needs Screen Recording permission (for window thumbnails).
4. Open **System Settings → Privacy & Security → Screen Recording** and enable *Windows Switcher*.
5. The dot turns **green** and Cmd+Tab now cycles windows with a preview overlay.
```

with:

```markdown
1. The Windows Switcher icon appears in the menubar with a **red badge** — the app needs Accessibility permission.
2. Open **System Settings → Privacy & Security → Accessibility** and enable *Windows Switcher*.
3. The badge turns **amber** — the app now needs Screen Recording permission (for window thumbnails).
4. Open **System Settings → Privacy & Security → Screen Recording** and enable *Windows Switcher*.
5. The badge disappears and Cmd+Tab now cycles windows with a preview overlay.
```

- [ ] **Step 2: Commit**

```bash
git add README.md
git commit -m "docs: describe new menubar icon (symbol + warning badge) in README"
```

---

## Task 4: Build, run tests, manual verification

**Files:** none (verification only)

- [ ] **Step 1: Full build**

Run: `swift build -c release`
Expected: Build succeeds.

- [ ] **Step 2: Run the test suite**

Run: `./test.sh`
Expected: All existing tests pass (regression gate — no core logic changed).

- [ ] **Step 3: Rebuild the .app bundle**

Run: `./make-app.sh`
Expected: `WindowsSwitcher.app` is produced.

- [ ] **Step 4: Manual visual verification**

Open `WindowsSwitcher.app` and verify each item:

- [ ] Menubar shows the `arrow.right.arrow.left.square` symbol (not a plain circle).
- [ ] In **dark** menubar appearance: symbol is light, badge (if shown) is red or amber.
- [ ] In **light** menubar appearance: symbol is dark, badge (if shown) is red or amber.
- [ ] While the menu is **open**: symbol is readable against the blue highlight (white tint via `alternateImage`); badge keeps its red/amber color.
- [ ] Toggle system appearance while the app is idle: symbol re-renders to match on the next KVO fire.
- [ ] With both permissions granted: **no badge** on the symbol; menu title reads "Windows Switcher: Active".
- [ ] With Accessibility missing: **red badge**; menu title reads "Windows Switcher: Needs Accessibility Permission".
- [ ] With Screen Recording missing (Accessibility granted): **amber badge**; menu title reads "Windows Switcher: Needs Screen Recording Permission".

- [ ] **Step 5: Final commit if any tweaks were made during verification**

If the manual check required adjustments, stage and commit them:

```bash
git add -A
git commit -m "polish: menubar icon tweaks from manual verification"
```

---

## Self-Review

**Spec coverage:**
- Symbol `arrow.right.arrow.left.square` → Task 1 Step 1.
- `statusImages()` returning primary + alternate → Task 1 Step 1.
- Badge red/amber, warning-only → Task 1 Step 1 (`badgeColor` nil when active).
- `isTemplate = false` on composed image → Task 1 Step 1 (`compose`).
- `alternateImage` for menu-open highlight → Task 1 Step 1 + Step 3 (call sites set `alternateImage`).
- KVO on `NSApp.effectiveAppearance` → Task 2 Step 2.
- Block-based observer, self-invalidating → Task 2 Step 2 (rationale note).
- Existing refresh sites re-run → Task 1 Step 3 (all 4 sites converted).
- Menu text unchanged → no task (intentional).
- README update → Task 3.
- Manual verification checklist → Task 4 Step 4.
- No new unit tests → noted in Task 1.
All spec sections covered.

**Placeholder scan:** No TBD/TODO. All code blocks contain real code. Exact file paths and line numbers given.

**Type consistency:** `StatusImages` (struct), `statusImages()` (returns `StatusImages`), `refreshStatusIcon()` (assigns `primary`/`alternate`) — names match across tasks. `appearanceObserver: NSKeyValueObservation?` matches the `NSApp.observe(\.effectiveAppearance...)` assignment in Task 2.
