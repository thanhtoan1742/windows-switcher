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

        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap = self.tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return Unmanaged.passRetained(event)
        }

        let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
        let action = KeyClassifier.classify(
            keyCode: keyCode, flags: event.flags, isKeyDown: type == .keyDown
        )
        switch action {
        case .tabForward, .tabBackward:
            self.handler(action)
            return nil  // consume
        case .cmdDown, .cmdUp:
            self.handler(action)
            return Unmanaged.passRetained(event)  // let Cmd state reach the system
        case .ignore:
            return Unmanaged.passRetained(event)
        }
    }
}
