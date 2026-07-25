# Windows Switcher — Preview All Windows (Row Overlay) Design

Date: 2026-07-25
Status: Draft
Supersedes (in part): `2026-07-25-preview-overlay-design.md` section
"ThumbnailOverlay (app target)" — the single-centered-thumbnail rendering
described there is replaced by a horizontal row showing all thumbnails
at once. All other sections of the preview-overlay design (core protocols,
cycling state machine, `ThumbnailCapturer`, permissions + UI, performance,
error handling, testing) remain in force unchanged.

## Goal

Show **all** window thumbnails simultaneously in a centered horizontal row
while Cmd is held, instead of a single thumbnail at a time. Tab cycling
moves a selection ring between thumbnails; the selected window is raised
once on Cmd-up. This lets the user see every candidate window at a glance
and pick directly, rather than paging through them one at a time.

## Non-Goals (explicit)

- **No grid / 2D layout.** A single horizontal row only. Tab moves the
  selection left/right along the MRU order — the same 1D navigation model
  as today.
- **No coexist / toggle mode.** The row replaces the single-thumbnail view
  outright. There is no key to switch back to single-thumbnail rendering.
- **No labels / titles** under thumbnails. The selection ring is the only
  chrome; thumbnails identify windows by their content.
- **No per-thumbnail re-capture on Tab.** Thumbnails stay frozen for the
  session (same guarantee as today); refresh on next Cmd-down.
- **No scaling/dimming of unselected thumbnails.** All cells are the same
  size; only the selection ring moves. (Chosen over "scale up selected" to
  avoid row reflow on every Tab, and over "dim others" to keep thumbnails
  readable.)
- **No app-target unit tests for layout math.** App-target rendering is
  verified manually, consistent with how `ThumbnailCapturer`,
  `WindowRaiser`, and `EventTap` are handled in this project.

## User Interaction (revised)

1. Press and hold Cmd → session begins. The MRU window list is snapshotted
   and a thumbnail of each window is captured. All thumbnails appear at
   once in a centered horizontal row; the leftmost thumbnail (index 0,
   the current frontmost) has the selection ring.
2. Tap Tab (no Shift) → the selection ring moves to the next thumbnail
   to the right; nothing is raised. All thumbnails remain visible.
3. Tap Tab+Shift → the selection ring moves left; nothing is raised.
4. Release Cmd → the row hides and the ringed (selected) window is raised
   via the existing `WindowRaiser`. A fresh session on the next Cmd-down
   re-snapshots and re-captures.

The window list is frozen for the session (same stability guarantee as
today). MRU does not bounce mid-cycle because no raises occur during the
session.

## Architecture (unchanged)

The `WindowPreviewing` protocol and the `Switcher` core are **untouched**.
The protocol already passes the full `pairs` array and the cursor index:

```swift
public protocol WindowPreviewing: AnyObject {
    func show(thumbnails: [(WindowInfo, CGImage)], startingAt index: Int)
    func update(index: Int)
    func hide()
}
```

Data flow is identical to today:
1. **Cmd-down** → `beginSession` → `capturer` builds `pairs` →
   `previewer.show(allPairs, 0)` → row renders all cells, ring on cell 0.
2. **Tab** → `tap(forward:)` → `previewer.update(newIndex)` → ring moves
   from old cell to new cell. (Today this swaps the single image; now it
   toggles the border.)
3. **Cmd-up** → `endSession` → `previewer.hide()` → `raiser.raise(selected)`.

The only code change is a rewrite of `ThumbnailOverlay.swift` (app target)
to render a row instead of a single image. `main.swift` needs **no** change
because the class name (`ThumbnailOverlay`) and its `WindowPreviewing`
conformance are unchanged — `AppDelegate` constructs `ThumbnailOverlay()`
and passes it to `Switcher` exactly as today.

The 14 existing `SwitcherTests` (using `MockPreviewer`) keep passing
unchanged because the protocol contract is unchanged.

## ThumbnailOverlay (app target, revised)

Conforms to `WindowPreviewing`. A single borderless, non-activating
`NSPanel` whose content view is a custom container laying out N
`NSImageView` subviews side-by-side. Approach A from the brainstorm:
single panel + custom container view + manual layout (no Auto Layout,
no `NSStackView`, no per-thumbnail panels).

### Panel setup (same as today)

- Style: `borderless` + `nonactivatingPanel`, `level = .statusBar`,
  `hidesOnDeactivate = false`, `backgroundColor = .clear`, `isOpaque = false`,
  `hasShadow = true`.
- Content view: a plain `NSView` (the container). Each thumbnail is an
  `NSImageView` added as a subview.

### Cell sizing — shrink all to fit

A single uniform cell size is computed once at `show` time so all N
thumbnails fit within the screen width:

```
let n = pairs.count
let margin: CGFloat = 40          // padding from screen edges
let spacing: CGFloat = 8           // gap between cells
let maxCell = CGSize(width: 240, height: 180)   // 4:3 aspect
let minCell = CGSize(width: 80, height: 60)
let aspect = maxCell.height / maxCell.width     // 0.75

let availWidth = screen.visibleFrame.width - 2 * margin
let naturalCellWidth = (availWidth - (n - 1) * spacing) / n
let cellWidth  = min(maxCell.width, naturalCellWidth)
let cellHeight = cellWidth * aspect
```

- With few windows, `cellWidth` hits `maxCell.width` (240) → large
  thumbnails.
- With many windows, `cellWidth` shrinks **past** `minCell.width` (80) →
  small thumbnails, but all remain visible (no off-screen overflow).
- Edge case: at very high window counts (≈18+ on a typical screen)
  `naturalCellWidth` drops below `minCell.width` (80pt). The row
  continues to shrink-to-fit rather than clamping to `minCell.width`, so
  thumbnails become very small but **all remain visible within the screen
  width** — no off-screen overflow. This trades legibility for guaranteed
  visibility.

### Row layout — manual, no Auto Layout

```
rowWidth  = n * cellWidth + (n - 1) * spacing
rowHeight = cellHeight
panel.setContentSize(CGSize(width: rowWidth, height: rowHeight))
center panel on screen.visibleFrame

for i in 0..<n:
    cell[i].frame = CGRect(x: i * (cellWidth + spacing), y: 0,
                           width: cellWidth, height: cellHeight)
```

Each cell (`NSImageView`):
- `imageScaling = .scaleProportionallyDown` (fit within cell, preserve
  the thumbnail's own aspect ratio)
- `imageAlignment = .alignCenter`
- `wantsLayer = true`, `layer.cornerRadius = 6`,
  `layer.masksToBounds = true` (rounded thumbnail clipping)
- No cell background color (panel is transparent with shadow; thumbnails
  provide their own content)

### Selection ring

The currently-selected cell shows a border; all others have none.

```
// tracked state
private var selectedIndex: Int = 0

func show(thumbnails:startingAt index):
    build cells, set images, layout, orderFront
    selectedIndex = index
    applyRing(to: index)

func update(index: Int):
    guard pairs.indices.contains(index) else { return }
    if selectedIndex != index:
        imageViews[selectedIndex].layer?.borderWidth = 0
    selectedIndex = index
    imageViews[index].layer?.borderWidth = 3
    imageViews[index].layer?.borderColor = NSColor.controlAccentColor.cgColor
```

- Border width: 3pt. Color: `NSColor.controlAccentColor` (the system
  accent color — adapts to the user's appearance preference; the most
  native choice for a selection highlight).
- Toggling `layer.borderWidth` between 0 and 3 is cheap and does not
  reflow the row (the border draws inside the layer bounds thanks to
  `masksToBounds`/`cornerRadius`).

### show / hide

- `show(thumbnails:startingAt:)`: guard `!pairs.isEmpty` up front (defensive
  — the `Switcher` core won't call `show` with zero pairs, but the overlay's
  cell-size math divides by `n` and must not divide by zero); rebuild the
  cell array from scratch each call (the old cells are removed and
  released); compute the uniform cell size; lay out; size and center the
  panel; `orderFront(nil)`; apply the ring to the starting index.
- `hide()`: `orderOut(nil)`; clear each cell's image and border; empty the
  cell array and pairs; reset `selectedIndex = 0`. Idempotent (calling
  `hide()` twice is safe — the cell array is empty on the second call).

### File impact

- **Rewrite:** `Sources/WindowsSwitcher/ThumbnailOverlay.swift` — row
  layout replaces single-image layout. Class name stays `ThumbnailOverlay`
  so `main.swift` is unchanged.
- **No change:** `Sources/WindowsSwitcherCore/Switcher.swift`,
  `Sources/WindowsSwitcher/main.swift`,
  `Tests/WindowsSwitcherTests/PreviewingMocks.swift`,
  `Tests/WindowsSwitcherTests/SwitcherTests.swift`.
- **Update:** `README.md` — "How it works" and "Usage" sections describe
  the row instead of a single thumbnail.

## Testing (revised)

No test changes. The `WindowPreviewing` protocol contract is unchanged,
so the 14 `SwitcherTests` cases (using `MockPreviewer`) and the 42-test
total are unaffected. The row layout math lives in `ThumbnailOverlay` (app
target) and is verified manually, consistent with the project's
convention that app-target rendering is not unit-tested (same as
`ThumbnailCapturer`, `WindowRaiser`, `EventTap`).

Manual verification covers:
- Row appears centered on Cmd-down with all thumbnails visible.
- Ring starts on the leftmost thumbnail.
- Tab moves the ring right; Shift+Tab moves it left; wraps at both ends.
- All thumbnails remain the same size; only the ring moves.
- Release Cmd raises the ringed window and hides the row.
- With many windows, thumbnails shrink to fit; at extreme counts cells
  shrink below 80pt but all remain visible (no off-screen overflow).

## Performance / Footprint (unchanged from preview-overlay design)

- Thumbnails captured once per Cmd-down: N single-window
  `CGWindowListCreateImage` calls (same as today).
- Cycling is a `layer.borderWidth` toggle — effectively free (<1ms); no
  capture, no AX round-trip, no image swap, no row reflow during the
  session.
- One raise at Cmd-up (same cost as today).
- RSS impact unchanged: held `CGImage`s are transient, freed between
  sessions.

## Error Handling (unchanged)

- **All captures nil**: `beginSession` skips `previewer.show`; no row, no
  raise on end. Silent no-op session. (The row overlay never receives a
  `show` call with zero pairs.)
- **Partial capture failure**: failed windows are absent from `snapshot`
  and `pairs`; the row shows only the captured subset; the ring and
  cursor stay aligned within the filtered set.
- **AX raise fails at Cmd-up**: silently move on (same as today).
- **Screen Recording revoked mid-run**: thumbnails render blank; the row
  still shows and the ring still moves; amber badge updates on the next
  app-activation re-check. Documented limitation (unchanged). (Menubar-badge
  wording is described in `2026-07-25-menubar-icon-design.md`, which supersedes
  the earlier "dot" phrasing.)

## Migration Note

Users upgrading from the single-thumbnail overlay will notice: (a) all
window thumbnails now appear at once in a row instead of one at a time,
(b) Tab moves a selection ring between thumbnails rather than swapping
the centered image, (c) the selected window is still raised only on
Cmd-up. No new permissions are required (Screen Recording was already
added by the preview-overlay design).
