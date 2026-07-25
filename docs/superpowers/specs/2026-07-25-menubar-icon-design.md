# Menubar Icon Design

Date: 2026-07-25
Status: Approved
Supersedes: the "green/red dot" menubar description in `2026-07-25-windows-switcher-design.md` (line 98) and `2026-07-25-preview-overlay-design.md` (lines 78, 249).

## Goal

Make the Windows Switcher menubar icon look like a real macOS status item instead of a flat colored circle, while keeping permission state visible at a glance.

## Background

The current icon is a 14x14 colored circle drawn in `statusIcon()` in `Sources/WindowsSwitcher/main.swift:83-97`. Color encodes permission state:

- `systemRed` — Accessibility not granted
- `systemOrange` — Accessibility granted, Screen Recording not granted
- `systemGreen` — both granted (active)

The image uses `isTemplate = false`, so it does not adapt to dark/light menubar appearance or to the blue "menu open" highlight. The menu title (in `buildMenu()`) reports the same state in text.

## Requirements

- Real monochrome SF Symbol as the menubar glyph; adapts to dark/light menubar.
- Colored status badge shown **only when a permission is missing** (red = Accessibility, amber = Screen Recording). No badge when active.
- Badge color preserved (not auto-inverted by template rendering).
- Stays correct when the menu is open (blue highlight) and when the system appearance changes.
- No new pure logic; no new unit tests (AppKit rendering is verified manually).
- README and existing specs updated to match the new wording.

## Non-goals

- App icon (`CFBundleIconFile` / `AppIcon` assets). The app is `LSUIElement` and has no Dock icon; out of scope.
- Custom-drawn brand artwork. We use an SF Symbol.
- Animated badge (pulse on error). Static only.
- Settings UI. Permission state stays in the menubar + menu title.

## Design

### Symbol

`NSImage(systemSymbolName: "arrow.right.arrow.left.square", accessibilityDescription: "Windows Switcher")`. Reads as "switch back and forth, in a window." Available macOS 11+; project targets 12+.

### Image composition — `statusIcon()`

Replace the existing circle-drawing closure with a compose step:

1. Canvas 18x18 points (retina-friendly). Symbol ~14pt, badge ~6pt.
2. Lock focus, draw the SF Symbol tinted with `NSColor.controlTextColor` (resolves to the current appearance's menubar text color, including dark/light).
3. If a permission is missing, draw a filled circle in the bottom-right corner:
   - `systemRed` when `!AXIsProcessTrusted()`
   - `systemOrange` when `AXIsProcessTrusted()` but `!CGPreflightScreenCaptureAccess()`
4. Skip the badge when both are granted (the "active" state).
5. Set `image.isTemplate = false` so the badge color is honored. The symbol's tint is baked in at draw time instead of relying on template auto-invert.

### Menu-open highlight — `alternateImage`

When a menu is open, the status button gets a blue background; a non-template image won't auto-invert and the symbol would look wrong against the blue. Set `statusItem.button?.alternateImage` to a second composed image:

- Symbol tinted white (readable on the blue highlight).
- Badge keeps its red/amber color — still readable on blue.

`statusIcon()` is replaced by a `statusImages()` function returning a small `StatusImages` struct (`primary: NSImage`, `alternate: NSImage`). Every existing refresh site sets both `statusItem.button?.image = images.primary` and `statusItem.button?.alternateImage = images.alternate`.

### Appearance refresh

Register a block-based KVO observer on `NSApp.effectiveAppearance` in `applicationDidFinishLaunching`; store the observation token as a stored property (`appearanceObserver`). The block-based `NSKeyValueObservation` self-invalidates when the token is released (on `AppDelegate` deinit) — no explicit `removeObserver` or `dealloc` override is needed. On change, re-run the existing `statusItem.button?.image = statusImages().primary` refresh path (also setting `alternateImage`). No timers, no event-tap coupling.

### Refresh sites (unchanged triggers)

- `applicationDidFinishLaunching` (initial)
- `tryStartTap()` (after first AX grant retry)
- `appActivated()` (after re-activation, existing)
- new `NSApp.effectiveAppearance` KVO observer

All four call the same `statusIcon()`-based refresh, which reads `AXIsProcessTrusted()` + `CGPreflightScreenCaptureAccess()` at draw time, so the badge and the menu title stay in sync.

### Menu text — `buildMenu()`

Unchanged. The "Needs Accessibility / Needs Screen Recording / Active" title remains the authoritative text status; the badge is a visual cue for the same state.

## Testing

Pure presentation, no new pure logic. Verified manually:

- Dark menubar: symbol adapts, badge red/amber visible.
- Light menubar: same.
- Menu open: symbol readable on blue highlight, badge color preserved.
- Toggle system appearance while idle: symbol re-renders on next KVO fire.
- Three permission states: no badge (active), amber badge (AX ok, SR missing), red badge (AX missing).

No new `Tests/` files.

## Docs

- README lines 36-40: replace "red dot / amber dot / green dot" with the new symbol + warning badge wording.
- Add a note to the existing specs that the menubar description is superseded by this document.

## Risks

- `NSImage(systemSymbolName:accessibilityDescription:)` requires macOS 11+. Project targets macOS 12+ (Info.plist `LSMinimumSystemVersion = 12.0`), so safe.
- KVO on `NSApp.effectiveAppearance` is the standard mechanism; the block-based `NSKeyValueObservation` self-invalidates on release of the stored token (no explicit `removeObserver`/`dealloc`), avoiding a dangling observer.
- Non-template images don't get the menu-open highlight automatically; mitigated by `alternateImage`.
