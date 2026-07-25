# Windows Switcher — Design

Date: 2026-07-25
Status: Approved

## Goal

Replace macOS Cmd+Tab's default application-switching with Windows/Linux-style
**window** switching: cycling across every open window regardless of which app
owns it. Minimal, fast, low-memory, native Swift + AppKit, no external dependencies.

## Non-Goals (explicit)

- Cross-Space window switching — deferred to a future iteration. The
  `WindowLister` is the only component affected, so it can be swapped later.
- Overlay / thumbnail UI — instant in-place switching only.
- Autostart via Login Items / LaunchAgent — user adds it themselves.
- Minimized-window cycling — skipped for now (unminimizing is slow and jarring
  without a preview overlay).

## User Interaction

Hold Cmd, tap Tab to step forward through windows in most-recently-used order;
each tap raises the next window live (no overlay). Cmd+Shift+Tab cycles backward.
Release Cmd to end the session. Matches the native Cmd+Tab hold-and-tap feel.

## Architecture

Single Swift Package, no third-party dependencies. Native Swift + AppKit +
CoreGraphics + ApplicationServices. Background app (`LSUIElement=true`) with one
menubar status item.

Files:

- `main.swift` — `NSApplication` entry point, `AppDelegate`, `NSStatusItem` menu.
- `EventTap.swift` — `CGEventTapCreate` wrapper; callback dispatches to a handler.
- `Switcher.swift` — `WindowLister` (CG window list), `WindowRaiser` (AX raise),
  cycling state machine.

`Package.swift` declares an executable target. `make-app.sh` assembles
`WindowsSwitcher.app` with `Info.plist` (`LSUIElement=true`) and the release
binary.

## Cycling State Machine

- **Cmd flagsChanged → down**: snapshot the MRU list (front-to-back from
  `CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements])`),
  `cursor = 0` (points at current frontmost).
- **Tab keydown, Cmd held, no Shift**: `cursor = (cursor + 1) % count`; raise
  `list[cursor]`.
- **Tab keydown, Cmd held, Shift**: `cursor = (cursor - 1 + count) % count`;
  raise `list[cursor]`.
- **Cmd flagsChanged → up**: end session. State is held until the next Cmd-down.

The snapshot is frozen for the session so cycling is stable (doesn't bounce when
MRU changes mid-cycle). Re-snapshotted on the next Cmd-down.

## Window Set (current Space only)

Filter `kCGWindowLayer == 0` (normal layer), `kCGWindowAlpha > 0`, has non-zero
bounds, and owner is a normal app (excludes Dock, SystemUIServer, WindowServer).
`.optionOnScreenOnly` is Space-aware → only the current Space. Minimized windows
are not on-screen, so they are excluded automatically.

Future cross-Space support lives entirely in `WindowLister`; no other component
changes.

## Window Raising

Resolve owner PID → `AXUIElementCreateApplication(pid)` →
`kAXWindowsAttribute`. Match by `kCGWindowNumber` to find the right AX window.
Then:

1. `AXUIElementSetMessagingTimeout(window, 0.2)` so a stuck app cannot hang
   cycling.
2. `AXUIElementPerformAction(window, kAXRaiseAction)`.
3. `AXUIElementSetAttributeValue(window, kAXMainAttribute, true)`.
4. `NSRunningApplication(processIdentifier: pid)?.activate()` to bring the app
   forward.

Minimized windows are skipped (already filtered out). Windows on other Spaces
would need `kAXRaiseAction` + Space activation — deferred (not needed for
current-Space scope).

## Event Tap Rules

- Mask: `KeyDown` + `FlagsChanged`.
- Swallow only Tab keydowns when the Cmd flag is set (Shift optional). Return
  `nil` to consume.
- All other events pass through unmodified.
- Re-enable the tap if the system disables it (watch
  `kCGEventTapDisabledByTimeout`, re-enable on `kCGEventTapEnabled`).

## Permissions + UI

- On launch: `AXIsProcessTrusted(options: [.prompt])` opens System Settings →
  Accessibility.
- Menubar icon: green dot when trusted + tap active, red dot otherwise.
- Menu: a status line + Quit. No preferences window.

## Performance / Footprint

- No thumbnails, no overlays, no timers, no caching between sessions.
- Window list fetched once per Cmd-down (~30–100 windows, O(n), sub-ms to low-ms).
- AX raise per Tab tap (~5–20ms typical; capped at 200ms via messaging timeout).
- Idle between taps: nothing running. RSS ~10–20 MB.

## Error Handling

- No windows / cursor on empty list: no-op.
- AX raise fails: silently move on; user taps again.
- Event tap creation fails (no permission): menubar shows red, retry on next
  app activation notification.

## Testing

- Unit-test the cycling state machine (pure: given list + key sequence →
  expected raises) with a mock raiser.
- Unit-test window filtering against fixture `CGWindowList`-style dictionaries.
- Skip live event-tap / AX integration tests (require UI automation).

## Build / Packaging

- `swift build -c release` produces the binary.
- `make-app.sh` wraps the binary into `WindowsSwitcher.app` with `Info.plist`
  (`LSUIElement=true`).
- No Xcode project, no signing (user can self-sign or notarize if they choose
  to distribute).
