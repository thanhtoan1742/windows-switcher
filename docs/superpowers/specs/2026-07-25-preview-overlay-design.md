# Windows Switcher — Preview Overlay Design

Date: 2026-07-25
Status: Draft
Supersedes (in part): `2026-07-25-windows-switcher-design.md` sections
"User Interaction", "Cycling State Machine", "Permissions + UI", "Performance /
Footprint", and "Testing" — the decoupled-preview behavior described here
replaces the live-raise-on-each-tap model those sections describe. All other
sections of the original design (window set, window raising, event tap rules,
build/packaging) remain in force.

## Goal

Add a **decoupled preview overlay** to Cmd+Tab cycling: while Cmd is held, each
Tab tap cycles a centered on-screen thumbnail of the next window **without
raising it**. The selected window is raised only once, on Cmd-up. This lets
the user browse candidate windows without shuffling z-order mid-cycle.

Preview content is a single live thumbnail of the currently selected window.
Thumbnails are captured once at Cmd-down; cycling is an image swap. If
thumbnail capture fails for every window, the session is a silent no-op
(strict mode — no fallback to live-raise-on-tap).

## Non-Goals (explicit)

- **No thumbnail row / app-icon strip.** A single centered thumbnail only, not
  a native-Cmd+Tab-style row.
- **No re-capture on tap.** Thumbnails are frozen for the session; refresh on
  next Cmd-down.
- **No decoupled "peek" mode** beyond the existing session. Preview and raise
  are coupled to the Cmd-hold session lifecycle.
- **No minimized-window support.** Same constraint as the original design;
  `.optionOnScreenOnly` continues to exclude them.
- **No settings UI.** Permission state is shown via the menubar dot only.

## User Interaction

1. Press and hold Cmd → session begins. The MRU window list is snapshotted and
   a thumbnail of window 0 (the current frontmost) is shown centered on screen.
2. Tap Tab (no Shift) → thumbnail swaps to the next window forward; nothing is
   raised.
3. Tap Tab+Shift → thumbnail swaps to the previous window; nothing is raised.
4. Release Cmd → the thumbnail overlay hides and the currently selected window
   is raised via the existing `WindowRaiser`. A fresh session on the next
   Cmd-down re-snapshots and re-captures.

The window list is frozen for the session (same stability guarantee as
today). MRU does not bounce mid-cycle because no raises occur during the
session.

## Architecture

Approach B from the brainstorm: extend the existing
`WindowRaising`/`WindowRaiser` dependency-injection pattern in
`WindowsSwitcherCore` with two sibling protocols. The core stays pure and
unit-testable; the app target supplies the AppKit/CoreGraphics-backed
implementations.

New files in `Sources/WindowsSwitcherCore/`:
- None — the new protocols are defined alongside the existing `Switcher` in
  `Switcher.swift` to keep the cycling state machine and its dependencies in
  one place.

New files in `Sources/WindowsSwitcher/`:
- `ThumbnailCapturer.swift` — `ThumbnailCapturing` implementation wrapping
  `CGWindowListCreateImage`.
- `ThumbnailOverlay.swift` — `WindowPreviewing` implementation backed by a
  borderless `NSPanel` + `NSImageView`.

Modified files:
- `Sources/WindowsSwitcherCore/Switcher.swift` — gains `previewer` and
  `capturer` dependencies; `tap` no longer raises; `endSession` performs the
  deferred raise.
- `Sources/WindowsSwitcher/main.swift` — wires the new dependencies into
  `Switcher.init`; adds Screen Recording permission preflight/prompt; adds a
  third menubar-dot state.
- `Tests/WindowsSwitcherTests/` — existing `Switcher` tests rewritten for the
  new call shape; new tests for capture-failure and partial-capture cases.

## Core Protocols

Three protocols in `WindowsSwitcherCore` (two new, one existing), all using
`CGImage` so the core target stays in `CoreGraphics`/`Foundation` land and does
not import AppKit:

```swift
public protocol WindowRaising: AnyObject {
    @discardableResult
    func raise(_ window: WindowInfo) -> Bool
}

public protocol ThumbnailCapturing: AnyObject {
    func capture(_ window: WindowInfo) -> CGImage?
}

public protocol WindowPreviewing: AnyObject {
    func show(thumbnails: [(WindowInfo, CGImage)], startingAt index: Int)
    func update(index: Int)
    func hide()
}
```

Thumbnails are passed as an array of `(WindowInfo, CGImage)` tuples aligned
1:1 with `Switcher.snapshot` (built together in `beginSession`). Cursor and
`update(index:)` share this single index space — no lookup, no clamping.
`NSImage` conversion is deferred to the app-side `ThumbnailOverlay`.

## Cycling State Machine (revised)

```swift
public final class Switcher {
    private let raiser: WindowRaising
    private let previewer: WindowPreviewing
    private let capturer: ThumbnailCapturing
    private(set) var snapshot: [WindowInfo] = []
    private(set) var thumbnails: [CGImage] = []   // parallel to snapshot
    private(set) var cursor: Int = 0
    private(set) var isCmdDown: Bool = false

    public init(raiser: WindowRaising, previewer: WindowPreviewing,
                capturer: ThumbnailCapturing) { /* assign */ }

    public func beginSession(windows: [WindowInfo]) {
        let pairs: [(WindowInfo, CGImage)] = windows.compactMap {
            guard let img = capturer.capture($0) else { return nil }
            return ($0, img)
        }
        snapshot = pairs.map { $0.0 }   // snapshot holds only captured windows
        thumbnails = pairs.map { $0.1 }
        cursor = 0
        isCmdDown = true
        guard !pairs.isEmpty else { return }   // strict: silent no-op session
        previewer.show(thumbnails: pairs, startingAt: 0)
    }

    @discardableResult
    public func tap(forward: Bool) -> Bool {
        guard isCmdDown, snapshot.count >= 2 else { return false }
        cursor = forward
            ? (cursor + 1) % snapshot.count
            : (cursor - 1 + snapshot.count) % snapshot.count
        previewer.update(index: cursor)
        return true
    }

    public func endSession() {
        guard isCmdDown else { return }
        isCmdDown = false
        previewer.hide()
        guard snapshot.indices.contains(cursor) else { return }
        raiser.raise(snapshot[cursor])
    }
}
```

Key behavior changes from the original design:

- `tap(forward:)` no longer calls `raiser.raise`. It advances the cursor and
  notifies the previewer only. The return value flips from "raised?" to
  "advanced?".
- `endSession()` performs the single deferred raise of `snapshot[cursor]`.
  Guards `isCmdDown` so a stray Cmd-up with no prior Cmd-down is a no-op.
- `beginSession` captures thumbnails up front (frozen for the session),
  filters the snapshot to only successfully captured windows, and tells the
  previewer to show at index 0. If every capture returns nil the session
  degrades to a silent no-op — no overlay, no raise on end.

Indexing model: `snapshot`, `thumbnails`, and the previewer's pairs array are
all the same length and aligned by construction (built together in
`beginSession`). `cursor` and `previewer.update(index:)` reference the same
index space — no dictionary lookup, no clamping. A window whose capture
failed is absent from `snapshot`, so it is neither previewable nor
switchable for this session; it is reachable again on the next Cmd-down (a
fresh capture attempt). This makes "what you see" and "what you raise"
always agree.

## ThumbnailCapturer (app target)

Conforms to `ThumbnailCapturing`. A thin wrapper around
`CGWindowListCreateImage`:

```swift
public final class ThumbnailCapturer: ThumbnailCapturing {
    public init() {}

    public func capture(_ window: WindowInfo) -> CGImage? {
        let rect = window.bounds
        guard let image = CGWindowListCreateImage(
            rect,
            .optionIncludingWindow,
            window.windowID,
            [.nominalResolution, .boundsIgnoreFraming]
        ) else { return nil }
        return image
    }
}
```

Capture uses `.optionIncludingWindow` scoped to the single `windowID`, so
capturing N windows is N independent single-window captures (no full-screen
screenshot per call). `boundsIgnoreFraming` returns just the window content,
not the shadow, keeping the thumbnail tight.

Screen Recording permission is required on macOS 10.15+ for the returned
image to contain content; without it, captures return a blank image (not
nil). The strict-mode "all nil" check therefore catches API failure but not
blank-image-without-permission. The permission preflight at launch (see
"Permissions + UI") handles the latter case before any session starts.

`ThumbnailCapturer` is a stateless wrapper; verified manually like
`WindowRaiser`.

## ThumbnailOverlay (app target)

Conforms to `WindowPreviewing`. A borderless, non-activating `NSPanel`
displaying a single `NSImageView`:

- Panel style: `borderless` + `nonactivatingPanel`, `level = .statusBar` so it
  floats above the frontmost app without stealing focus. `hidesOnDeactivate`
  is false (the app is an accessory; we manage visibility explicitly).
- `show(thumbnails:startingAt:)`: store the pairs array; size the panel to the
  first thumbnail's dimensions capped at 320×240pt (preserving aspect ratio);
  center on the main screen's visible frame; populate the image view;
  order-front.
- `update(index:)`: swap `NSImageView.image` to `pairs[index].1` (wrapped in
  `NSImage(cgImage:size:)`). Direct indexing is safe because `Switcher`
  guarantees `snapshot`, the previewer's pairs, and `cursor` share one index
  space (see "Indexing model" above). No panel resize on update — the panel is
  sized once at `show` time to the first thumbnail's dimensions.
- `hide()`: order-out the panel; clear the stored pairs.

Verified manually (AppKit panel behavior is not unit-tested).

## Permissions + UI (revised)

Two permissions are now required, both prompted at launch:

1. **Accessibility** (existing) — needed for `EventTap` and `AXUIElement*`
   calls. Preflight via `AXIsProcessTrusted()`; prompt via
   `AXIsProcessTrustedWithOptions([.prompt: true])`.
2. **Screen Recording** (new) — needed for `CGWindowListCreateImage` to return
   content. Preflight via `CGPreflightScreenCaptureAccess()` (macOS 10.15+);
   prompt via `CGRequestScreenCaptureAccess()` (one-time, opens System Settings
   → Screen Recording). Both calls are non-blocking and return immediately if
   already granted.

Menubar dot gains a third state:

| State | Accessibility | Screen Recording | Dot color |
|-------|---------------|------------------|-----------|
| Not trusted | ✗ | — | Red |
| Partial | ✓ | ✗ | Amber |
| Active | ✓ | ✓ | Green |

`AppDelegate.tryStartTap()` is extended to also preflight Screen Recording and
set the dot color accordingly. Re-checks on the existing
`NSWorkspace.didActivateApplicationNotification` observer (already wired for
the Accessibility retry path).

## Performance / Footprint (revised)

- Thumbnails captured once per Cmd-down: N single-window `CGWindowListCreateImage`
  calls. Typical N = 5–20 on-screen windows; each capture is ~1–5ms, so total
  session-start cost is ~5–100ms. Acceptable latency for a Cmd-down event.
- Cycling is an `NSImageView.image` swap — effectively free (<1ms); no
  capture, no AX round-trip during the session.
- One raise at Cmd-up (same cost as the existing single raise: ~5–20ms).
- Thumbnails are released at the next `beginSession` (new array replaces the
  old); no cross-session caching, no timers, no background work between taps.
- RSS impact: held `CGImage`s are transient; for 20 windows at typical
  thumbnail sizes this is on the order of a few MB, freed between sessions.
  Same "idle between taps" footprint guarantee as the original design.

## Error Handling

- **All captures return nil** (API failure, no on-screen windows with valid
  IDs, etc.): `beginSession` skips `previewer.show`; `endSession` skips the
  raise. Silent no-op session. User simply sees no overlay and no switch;
  retries on next Cmd-down.
- **Partial capture failure**: windows whose capture returns nil are excluded
  from `snapshot` at `beginSession` time, so they are neither previewable nor
  switchable for this session. The session proceeds with the successfully
  captured subset; cursor math and the previewer's index space stay aligned.
  On the next Cmd-down, a fresh capture attempt is made for all windows
  (including the previously-failed one), so a transient failure does not
  permanently exclude a window.
- **AX raise fails at Cmd-up**: same as today — silently move on; the
  selected window stays where it was. No retry, no error UI.
- **Event tap creation fails**: unchanged — menubar shows red, retry on next
  app-activation notification.
- **Screen Recording permission revoked mid-run**: captures return blank
  images (not nil); the overlay shows blank thumbnails. The amber dot state
  only updates on the next app-activation re-check, not mid-session. Acceptable
  for a rare edge case; documented as a known limitation.

## Testing (revised)

All in `Tests/WindowsSwitcherTests/` using Swift Testing. Pure mocks added:

- `MockPreviewer` — records `show(thumbnails:startingAt:)`, `update(index:)`,
  and `hide()` calls; exposes call lists for assertions.
- `MockCapturer` — configurable per-window `CGImage` or nil; records capture
  calls.

Existing `Switcher` tests are rewritten for the new call shape:

- `tap(forward:)` asserts `previewer.update` called with the new cursor and
  `raiser.raise` **not** called.
- `endSession()` asserts `previewer.hide` called, then `raiser.raise` called
  exactly once with `snapshot[cursor]`.
- `beginSession(windows:)` asserts `capturer.capture` called once per window
  and `previewer.show` called with the successfully-captured pairs in order.

New tests:

- **All-nil capture**: `MockCapturer` returns nil for every window →
  `previewer.show` not called; `endSession` does not call `raiser.raise`;
  `snapshot` is empty.
- **Partial capture**: `MockCapturer` returns nil for one window → that
  window is absent from `snapshot`; `previewer.show` receives pairs excluding
  it; cycling calls `previewer.update` with indices into the filtered
  `snapshot`; `endSession` raises `snapshot[cursor]` (always a captured
  window). The failed-capture window is not switchable this session.
- **Stray endSession** (Cmd-up without Cmd-down): `endSession` is a no-op;
  `previewer.hide` and `raiser.raise` not called.

App-target wrappers (`ThumbnailCapturer`, `ThumbnailOverlay`, Screen Recording
permission wiring) are verified manually, like the existing `EventTap` and
`WindowRaiser`.

## Migration Note

The original design's "User Interaction" section said "each tap raises the
next window live (no overlay)". This spec replaces that with the
decoupled-preview model. Users upgrading will notice: (a) windows no longer
shuffle while cycling, (b) a thumbnail appears centered on screen during
cycling, (c) a new Screen Recording permission prompt on first launch. The
README's "Limitations / Future work" note about minimized windows being
excluded "without a preview overlay" is partially addressed by this feature
(thumbnails now exist) but minimized windows remain excluded by
`.optionOnScreenOnly` — that's unchanged and stays a Non-Goal here.
