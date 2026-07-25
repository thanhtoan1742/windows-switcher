import CoreGraphics

public enum KeyAction {
    case cmdDown
    case cmdUp
    case tabForward
    case tabBackward
    case ignore
}

/// Pure translation of a raw key event into a `KeyAction`. Extracted so the event
/// tap callback stays a thin adapter and the classification is unit-testable.
enum KeyClassifier {
    /// Key codes that act as the Command modifier. Both left (0x37) and right
    /// (0x36) Cmd set `.maskCommand` in `CGEventFlags` but are distinct key codes.
    static let cmdKeyCodes: Set<UInt16> = [0x37, 0x36]  // kVK_Command, kVK_RightCommand
    static let tabKeyCode: UInt16 = 0x30  // kVK_Tab

    static func classify(keyCode: UInt16, flags: CGEventFlags, isKeyDown: Bool) -> KeyAction {
        // FlagsChanged for a Cmd key: presence of .maskCommand == pressed, absence == released.
        if cmdKeyCodes.contains(keyCode) {
            return flags.contains(.maskCommand) ? .cmdDown : .cmdUp
        }
        // Tab keydown with Cmd held — Shift selects direction.
        if keyCode == tabKeyCode, isKeyDown, flags.contains(.maskCommand) {
            return flags.contains(.maskShift) ? .tabBackward : .tabForward
        }
        return .ignore
    }
}
