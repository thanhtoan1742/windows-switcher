import CoreGraphics

public enum EventTapError: Error {
    case creationFailed
}

/// Wraps a system-wide `CGEventTap` for `KeyDown` + `FlagsChanged`. Translates each
/// event to a `KeyAction` via `KeyClassifier` and dispatches it to `handler`. Tab
/// keydowns that we handle are consumed (return nil); Cmd flag events pass through
/// so the rest of the system still sees Cmd state.
public final class EventTap {
    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private let handler: (KeyAction) -> Void

    public init(handler: @escaping (KeyAction) -> Void) {
        self.handler = handler
    }

    /// Adds the event tap to the current run loop's common modes. **Must be called
    /// on the main run loop** — the callback fires on whatever run loop the source
    /// was added to, and the direct handler (`AppDelegate.handle`) is
    /// `@MainActor`-isolated, as is the `Switcher` it calls. `ThumbnailOverlay`
    /// (AppKit-touched) is not yet `@MainActor`-annotated but is reached only via
    /// `Switcher` on the main thread. Calling from a background thread would race
    /// on AppKit.
    public func start() throws {
        let mask = CGEventMask(
            (1 << CGEventType.keyDown.rawValue) |
            (1 << CGEventType.flagsChanged.rawValue)
        )
        let userInfo = Unmanaged.passUnretained(self).toOpaque()
        guard let port = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: EventTap.callback,
            userInfo: userInfo
        ) else {
            throw EventTapError.creationFailed
        }
        self.tap = port
        let source = CFMachPortCreateRunLoopSource(nil, port, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
        self.runLoopSource = source
        CGEvent.tapEnable(tap: port, enable: true)
    }

    func stop() {
        if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let runLoopSource { CFRunLoopRemoveSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes) }
        tap = nil
        runLoopSource = nil
    }

    private static let callback: CGEventTapCallBack = { _, type, event, userInfo in
        guard let userInfo else { return Unmanaged.passRetained(event) }
        let `self` = Unmanaged<EventTap>.fromOpaque(userInfo).takeUnretainedValue()

        let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
        let action = KeyClassifier.classify(
            keyCode: keyCode, flags: event.flags, isKeyDown: type == .keyDown
        )
        switch EventTap.decide(type: type, action: action) {
        case .reenable:
            if let tap = self.tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return Unmanaged.passRetained(event)
        case .consume:
            self.handler(action)
            return nil
        case .passthrough:
            self.handler(action)
            return Unmanaged.passRetained(event)
        case .pass:
            return Unmanaged.passRetained(event)
        }
    }
}

extension EventTap {
    enum Decision: Equatable {
        case pass          // pass event through, don't call handler
        case consume       // return nil, call handler
        case passthrough   // pass event, call handler
        case reenable      // tap was disabled by system; re-enable and pass
    }

    /// Pure decision logic for the C callback. Extracted so the consume-vs-passthrough
    /// contract and the tap-re-enable branch are unit-testable without a real
    /// `CGEventTap`. The side-effecting half (calling `handler`, re-enabling the tap,
    /// returning nil or the pass-retained event) stays in the callback.
    static func decide(type: CGEventType, action: KeyAction) -> Decision {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            return .reenable
        }
        switch action {
        case .tabForward, .tabBackward: return .consume
        case .cmdDown, .cmdUp:          return .passthrough
        case .ignore:                   return .pass
        }
    }
}
