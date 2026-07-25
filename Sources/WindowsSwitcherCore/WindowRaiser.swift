import ApplicationServices
import Cocoa
import CoreGraphics

/// Private Accessibility API: maps an AX window element to its CGWindowID. macOS
/// 10.10+; no public equivalent. Frame matching is the only public-API alternative
/// and fails for same-app windows sharing a frame (e.g. two maximized windows).
@_silgen_name("_AXUIElementGetWindow") @discardableResult
fileprivate func _AXUIElementGetWindow(_ element: AXUIElement,
                                       _ windowID: UnsafeMutablePointer<CGWindowID>) -> AXError

/// Pure two-pass matcher for finding the AX window corresponding to a
/// `WindowInfo` target. Pass 1 matches by `CGWindowID` (via the private
/// `_AXUIElementGetWindow` bridge). Pass 2 falls back to frame matching
/// with a 1pt epsilon. Extracted from `WindowRaiser.raise(_:)` so the
/// matching strategy is unit-testable without AXUIElement mocks.
public enum RaiseMatcher {
    public static func matchIndex(
        candidates: [(windowID: CGWindowID?, frame: CGRect?)],
        target: WindowInfo,
        epsilon: CGFloat = 1
    ) -> Int? {
        // Pass 1: windowID match (preferred — distinguishes same-app windows
        // with identical frames).
        for (i, c) in candidates.enumerated() {
            if let wid = c.windowID, wid == target.windowID {
                return i
            }
        }
        // Pass 2: frame fallback (for apps where the private bridge errors).
        for (i, c) in candidates.enumerated() {
            guard let f = c.frame else { continue }
            if framesMatch(f, target.bounds, epsilon: epsilon) {
                return i
            }
        }
        return nil
    }

    /// Pure helper used by the frame-matching fallback. Tolerant of sub-pixel
    /// rounding (1pt epsilon).
    static func framesMatch(_ a: CGRect, _ b: CGRect, epsilon: CGFloat = 1) -> Bool {
        abs(a.origin.x - b.origin.x) < epsilon &&
        abs(a.origin.y - b.origin.y) < epsilon &&
        abs(a.width - b.width) < epsilon &&
        abs(a.height - b.height) < epsilon
    }
}

/// Raises a cross-app window via the Accessibility API. Conforms to `WindowRaising`
/// so the `Switcher` can stay pure and unit-testable.
public final class WindowRaiser: WindowRaising {
    public init() {}

    @discardableResult
    public func raise(_ window: WindowInfo) -> Bool {
        let app = AXUIElementCreateApplication(window.ownerPID)
        AXUIElementSetMessagingTimeout(app, 0.2)
        var windowsRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            app, kAXWindowsAttribute as CFString, &windowsRef
        ) == .success,
        let axWindows = windowsRef as? [AXUIElement] else {
            return false
        }
        var candidates: [(windowID: CGWindowID?, frame: CGRect?)] = []
        for ax in axWindows {
            var wid: CGWindowID = 0
            let hasWid = (_AXUIElementGetWindow(ax, &wid) == .success)
            candidates.append((hasWid ? wid : nil, axFrame(ax)))
        }
        guard let idx = RaiseMatcher.matchIndex(candidates: candidates, target: window) else {
            return false
        }
        return raiseAX(axWindows[idx], pid: window.ownerPID)
    }

    private func raiseAX(_ ax: AXUIElement, pid: pid_t) -> Bool {
        AXUIElementPerformAction(ax, kAXRaiseAction as CFString)
        AXUIElementSetAttributeValue(ax, kAXMainAttribute as CFString, kCFBooleanTrue)
        if let running = NSRunningApplication(processIdentifier: pid) {
            running.activate()
        }
        return true
    }

    private func axFrame(_ ax: AXUIElement) -> CGRect? {
        var posRef: CFTypeRef?
        var sizeRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(ax, kAXPositionAttribute as CFString, &posRef) == .success,
              AXUIElementCopyAttributeValue(ax, kAXSizeAttribute as CFString, &sizeRef) == .success,
              let posVal = posRef, let sizeVal = sizeRef,
              CFGetTypeID(posVal) == AXValueGetTypeID(),
              CFGetTypeID(sizeVal) == AXValueGetTypeID() else {
            return nil
        }
        var origin = CGPoint.zero
        var size = CGSize.zero
        AXValueGetValue(posVal as! AXValue, .cgPoint, &origin)
        AXValueGetValue(sizeVal as! AXValue, .cgSize, &size)
        return CGRect(origin: origin, size: size)
    }
}
