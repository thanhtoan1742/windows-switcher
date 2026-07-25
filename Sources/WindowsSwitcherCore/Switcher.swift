import CoreGraphics

public protocol WindowRaising: AnyObject {
    @discardableResult
    func raise(_ window: WindowInfo) -> Bool
}

public protocol ThumbnailCapturing: AnyObject {
    func capture(_ window: WindowInfo) -> CGImage?
}

public protocol WindowPreviewing: AnyObject {
    func show(thumbnails: [(WindowInfo, CGImage)], startingAt index: Int)
    func update(index: Int)
    func hide()
}

@MainActor public final class Switcher {
    private let raiser: WindowRaising
    private let previewer: WindowPreviewing
    private let capturer: ThumbnailCapturing
    private(set) var snapshot: [WindowInfo] = []
    private(set) var cursor: Int = 0
    /// True after `beginSession` is called, regardless of capture success.
    /// Cleared on `endSession`. Gates `tap` and the deferred raise so a stray
    /// Cmd-up with no prior Cmd-down is a no-op. Note: remains true even when
    /// all captures return nil (strict-mode silent no-op session) so that
    /// `endSession` still calls `previewer.hide()` for symmetry.
    public private(set) var sessionActive: Bool = false

    public init(raiser: WindowRaising, previewer: WindowPreviewing, capturer: ThumbnailCapturing) {
        self.raiser = raiser
        self.previewer = previewer
        self.capturer = capturer
    }

    /// Called on the first Tab while Cmd is held. Captures a thumbnail per
    /// window, filters the snapshot to only successfully captured windows,
    /// advances the cursor once in the requested direction, and tells the
    /// previewer to show at the advanced index. If every capture failed, the
    /// session is a silent no-op (strict mode). Holding Cmd alone does
    /// nothing; the session starts here, not on Cmd-down.
    public func beginSession(windows: [WindowInfo], forward: Bool) {
        let pairs: [(WindowInfo, CGImage)] = windows.compactMap {
            guard let img = capturer.capture($0) else { return nil }
            return ($0, img)
        }
        snapshot = pairs.map { $0.0 }
        cursor = 0
        sessionActive = true
        guard !pairs.isEmpty else { return }
        if snapshot.count >= 2 {
            cursor = forward ? 1 : snapshot.count - 1
        }
        previewer.show(thumbnails: pairs, startingAt: cursor)
    }

    /// Called on Tab keydown while Cmd is held. `forward = !shift`. Advances the
    /// cursor and notifies the previewer. Does NOT raise. Returns true if the
    /// cursor advanced; false if the session was inactive or had <2 windows.
    @discardableResult
    public func tap(forward: Bool) -> Bool {
        guard sessionActive, snapshot.count >= 2 else { return false }
        cursor = forward
            ? (cursor + 1) % snapshot.count
            : (cursor - 1 + snapshot.count) % snapshot.count
        previewer.update(index: cursor)
        return true
    }

    /// Called on Cmd-up. Hides the overlay and raises the selected window once.
    /// Guards `sessionActive` so a stray Cmd-up with no prior Cmd-down is a no-op.
    public func endSession() {
        guard sessionActive else { return }
        sessionActive = false
        previewer.hide()
        guard snapshot.indices.contains(cursor) else { return }
        raiser.raise(snapshot[cursor])
    }
}
