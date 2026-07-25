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
