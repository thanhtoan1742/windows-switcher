import ApplicationServices
import Cocoa
import CoreGraphics

/// Private Accessibility API: maps an AX window element to its CGWindowID. macOS
/// 10.10+; no public equivalent. Frame matching is the only public-API alternative
/// and fails for same-app windows sharing a frame (e.g. two maximized windows).
@_silgen_name("_AXUIElementGetWindow") @discardableResult
fileprivate func _AXUIElementGetWindow(_ element: AXUIElement,
                                       _ windowID: UnsafeMutablePointer<CGWindowID>) -> AXError

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
        for ax in axWindows {
            var wid: CGWindowID = 0
            if _AXUIElementGetWindow(ax, &wid) == .success, wid == window.windowID {
                return raiseAX(ax, pid: window.ownerPID)
            }
        }
        for ax in axWindows {
            guard let frame = axFrame(ax) else { continue }
            guard WindowRaiser.framesMatch(frame, window.bounds) else { continue }
            return raiseAX(ax, pid: window.ownerPID)
        }
        return false
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

    /// Pure helper used by the frame-matching fallback. Tolerant of sub-pixel
    /// rounding (1pt epsilon).
    static func framesMatch(_ a: CGRect, _ b: CGRect, epsilon: CGFloat = 1) -> Bool {
        abs(a.origin.x - b.origin.x) < epsilon &&
        abs(a.origin.y - b.origin.y) < epsilon &&
        abs(a.width - b.width) < epsilon &&
        abs(a.height - b.height) < epsilon
    }
}
