import CoreGraphics

protocol WindowRaising: AnyObject {
    @discardableResult
    func raise(_ window: WindowInfo) -> Bool
}

/// Cycling state machine for window switching. Pure: raises are delegated to a
/// `WindowRaising` instance so this class is fully unit-testable with a mock.
final class Switcher {
    private let raiser: WindowRaising
    private(set) var snapshot: [WindowInfo] = []
    private(set) var cursor: Int = 0
    private(set) var isCmdDown: Bool = false

    init(raiser: WindowRaising) {
        self.raiser = raiser
    }

    /// Called on Cmd-down. Freezes the MRU window list for the session. The frontmost
    /// window (index 0) is already in front so no raise is issued here.
    func beginSession(windows: [WindowInfo]) {
        snapshot = windows
        cursor = 0
        isCmdDown = true
    }

    /// Called on Tab keydown while Cmd is held. `forward = !shift`.
    /// Returns true if a window was raised; false if the session was inactive or
    /// there was nothing to cycle to.
    @discardableResult
    func tap(forward: Bool) -> Bool {
        guard isCmdDown, snapshot.count >= 2 else { return false }
        cursor = forward
            ? (cursor + 1) % snapshot.count
            : (cursor - 1 + snapshot.count) % snapshot.count
        return raiser.raise(snapshot[cursor])
    }

    /// Called on Cmd-up. Ends the session; subsequent taps are no-ops until the
    /// next `beginSession`.
    func endSession() {
        isCmdDown = false
    }
}
