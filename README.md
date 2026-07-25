# Windows Switcher

A minimal macOS app that replaces the default Cmd+Tab app-switcher with Windows/Linux-style **window** switching: cycling across every open window regardless of which app owns it, on the current Space.

- **Native Swift + AppKit** — no third-party dependencies
- **Background app** (`LSUIElement`) — menubar dot, no Dock icon
- **Instant switching** — no overlay; each Tab tap raises a window live
- **Small footprint** — no caching, no timers, no thumbnails; idle between taps

## Requirements

- macOS 12+
- Swift 5.9+ (builds with just Command Line Tools — no Xcode needed)
- **Accessibility permission** (the app prompts on first launch)

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

On first launch:
1. A **red dot** appears in the menubar — the app needs Accessibility permission.
2. Open **System Settings → Privacy & Security → Accessibility** and enable *Windows Switcher*.
3. The dot turns **green** and Cmd+Tab now cycles windows.

To quit: click the menubar dot → *Quit*.

## Usage

| Shortcut | Action |
|----------|--------|
| Hold `Cmd` + tap `Tab` | Cycle forward through windows (most-recently-used) |
| Hold `Cmd` + tap `Shift`+`Tab` | Cycle backward |

The window list is snapshotted when you press Cmd, so cycling stays stable while you tap. Release Cmd to end the session; a fresh list is taken on the next Cmd+Tab.

## How it works

1. A system-wide `CGEventTap` intercepts `KeyDown` + `FlagsChanged` events.
2. A pure `KeyClassifier` translates each event into a `KeyAction` (`cmdDown`, `cmdUp`, `tabForward`, `tabBackward`, `ignore`).
3. On Cmd-down, `WindowLister` snapshots on-screen windows on the current Space via `CGWindowListCopyWindowInfo`.
4. Each Tab tap advances a cursor in a frozen MRU list and calls `WindowRaiser`.
5. `WindowRaiser` resolves the window's AX element by matching its frame and raises it via `AXUIElementPerformAction(kAXRaiseAction)`.

Only Tab keydowns with Cmd held are consumed; all other keystrokes pass through untouched.

## Tests

```bash
./test.sh
```

Uses Swift Testing (`import Testing`). The `test.sh` wrapper wires up the `Testing.framework` paths for Command Line Tools-only environments (Xcode is not required). Pure logic — window filtering, the cycling state machine, key classification, and frame matching — is fully unit-tested; the event tap and AX integration are verified manually.

## Project layout

```
Sources/
  WindowsSwitcherCore/   # Testable core: WindowLister, Switcher, KeyClassifier, WindowRaiser, EventTap
  WindowsSwitcher/       # App entry point: AppDelegate + menubar status item
Tests/
  WindowsSwitcherTests/  # Swift Testing suites
```

## Limitations / Future work

- **Current Space only** — windows on other Spaces are not included. Cross-Space support is isolated in `WindowLister.currentSpaceWindows()`.
- **Minimized windows excluded** — unminimizing is slow without a preview overlay.
- **Private AX API for window identity** — AX does not expose the `CGWindowID` publicly, so windows are matched via the private `_AXUIElementGetWindow` bridge (macOS 10.10+, used by AltTab, DockDoor, Loop). A frame-matching fallback (1pt epsilon) covers apps where the bridge errors but cannot distinguish two same-app windows with identical frames.
- **No autostart** — add it as a Login Item or LaunchAgent yourself.

## License

[MIT](LICENSE)
