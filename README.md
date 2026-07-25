# Windows Switcher

A minimal macOS app that replaces the default Cmd+Tab app-switcher with Windows/Linux-style **window** switching: cycling across every open window regardless of which app owns it, on the current Space.

- **Native Swift + AppKit** — no third-party dependencies
- **Background app** (`LSUIElement`) — menubar dot, no Dock icon
- **Preview overlay** — all window thumbnails shown at once in a centered row; a selection ring moves as you cycle, and nothing is raised until you release Cmd
- **Small footprint** — no caching, no timers; idle between taps

## Requirements

- macOS 12+
- Swift 5.9+ (builds with just Command Line Tools — no Xcode needed)
- **Accessibility permission** (the app prompts on first launch)
- **Screen Recording permission** (the app prompts on first launch; needed for window thumbnails)

## Build

```bash
swift build -c release
./make-app.sh
```

This produces `WindowsSwitcher.app` from the release binary.

## Run

```bash
open WindowsSwitcher.app
```

> **Note:** `make-app.sh` does not code-sign the bundle. On first launch macOS Gatekeeper will warn that the app is from an unidentified developer. To bypass: right-click `WindowsSwitcher.app` → **Open** → **Open**, or run `xattr -d com.apple.quarantine /path/to/WindowsSwitcher.app` before opening.

On first launch:
1. A **red dot** appears in the menubar — the app needs Accessibility permission.
2. Open **System Settings → Privacy & Security → Accessibility** and enable *Windows Switcher*.
3. The dot turns **amber** — the app now needs Screen Recording permission (for window thumbnails).
4. Open **System Settings → Privacy & Security → Screen Recording** and enable *Windows Switcher*.
5. The dot turns **green** and Cmd+Tab now cycles windows with a preview overlay.

To quit: click the menubar dot → *Quit*.

## Usage

| Shortcut | Action |
|----------|--------|
| Hold `Cmd` + tap `Tab` | Cycle forward through windows (most-recently-used) |
| Hold `Cmd` + tap `Shift`+`Tab` | Cycle backward |

The window list and thumbnails are snapshotted when you press Cmd, so cycling stays stable while you tap. A centered row shows all window thumbnails at once; a selection ring moves across the row as you tap Tab, and nothing is raised until you release Cmd, which raises the selected window. A fresh snapshot is taken on the next Cmd+Tab.

## How it works

1. A system-wide `CGEventTap` intercepts `KeyDown` + `FlagsChanged` events.
2. A pure `KeyClassifier` translates each event into a `KeyAction` (`cmdDown`, `cmdUp`, `tabForward`, `tabBackward`, `ignore`).
3. On Cmd-down, `WindowLister` snapshots on-screen windows on the current Space via `CGWindowListCopyWindowInfo`, and `ThumbnailCapturer` captures each window's content via `CGWindowListCreateImage`.
4. Each Tab tap advances a cursor in the frozen list and moves a selection ring across a centered row of `ThumbnailOverlay` thumbnails — no window is raised during cycling.
5. On Cmd-up, `WindowRaiser` resolves the selected window's AX element by matching its `CGWindowID` via the private `_AXUIElementGetWindow` bridge (primary path), with a frame-matching fallback (1pt epsilon) for apps where the bridge errors. It raises the window via `AXUIElementPerformAction(kAXRaiseAction)`.

Only Tab keydowns with Cmd held are consumed; all other keystrokes pass through untouched.

## Tests

```bash
./test.sh
```

Uses Swift Testing (`import Testing`). The `test.sh` wrapper wires up the `Testing.framework` paths for Command Line Tools-only environments (Xcode is not required). Pure logic — window filtering, the cycling state machine, key classification, event-tap consume/passthrough decisions, the raise-path two-pass matcher, row layout math, and frame matching — is fully unit-tested; the live `CGEventTap`, `AXUIElement` calls, and AppKit rendering are verified manually.

## Project layout

```
Sources/
  WindowsSwitcherCore/   # Testable core: WindowLister, Switcher, KeyClassifier, WindowRaiser, RaiseMatcher, EventTap, RowLayout
  WindowsSwitcher/       # App entry point: AppDelegate, ThumbnailCapturer, ThumbnailOverlay
Tests/
  WindowsSwitcherTests/  # Swift Testing suites
```

## Limitations / Future work

- **Current Space only** — windows on other Spaces are not included. Cross-Space support is isolated in `WindowLister.currentSpaceWindows()`.
- **Minimized windows excluded** — unminimizing is slow without a preview overlay.
- **Private AX API for window identity** — AX does not expose the `CGWindowID` publicly, so windows are matched via the private `_AXUIElementGetWindow` bridge (macOS 10.10+, used by AltTab, DockDoor, Loop). A frame-matching fallback (1pt epsilon) covers apps where the bridge errors but cannot distinguish two same-app windows with identical frames.
- **Screen Recording permission required** — without it, window thumbnails are blank (the session still runs and raises a window on Cmd-up, but previews are empty); the menubar dot shows amber.
- **No autostart** — add it as a Login Item or LaunchAgent yourself.

## License

[MIT](LICENSE)
