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

public final class Switcher {
    private let raiser: WindowRaising
    private let previewer: WindowPreviewing
    private let capturer: ThumbnailCapturing
    private(set) var snapshot: [WindowInfo] = []
    private(set) var thumbnails: [CGImage] = []
    private(set) var cursor: Int = 0
    private(set) var isCmdDown: Bool = false

    public init(raiser: WindowRaising, previewer: WindowPreviewing, capturer: ThumbnailCapturing) {
        self.raiser = raiser
        self.previewer = previewer
        self.capturer = capturer
    }

    /// Called on Cmd-down. Captures a thumbnail per window, filters the snapshot
    /// to only successfully captured windows, and tells the previewer to show.
    /// If every capture failed, the session is a silent no-op (strict mode).
    public func beginSession(windows: [WindowInfo]) {
        let pairs: [(WindowInfo, CGImage)] = windows.compactMap {
            guard let img = capturer.capture($0) else { return nil }
            return ($0, img)
        }
        snapshot = pairs.map { $0.0 }
        thumbnails = pairs.map { $0.1 }
        cursor = 0
        isCmdDown = true
        guard !pairs.isEmpty else { return }
        previewer.show(thumbnails: pairs, startingAt: 0)
    }

    /// Called on Tab keydown while Cmd is held. `forward = !shift`. Advances the
    /// cursor and notifies the previewer. Does NOT raise. Returns true if the
    /// cursor advanced; false if the session was inactive or had <2 windows.
    @discardableResult
    public func tap(forward: Bool) -> Bool {
        guard isCmdDown, snapshot.count >= 2 else { return false }
        cursor = forward
            ? (cursor + 1) % snapshot.count
            : (cursor - 1 + snapshot.count) % snapshot.count
        previewer.update(index: cursor)
        return true
    }

    /// Called on Cmd-up. Hides the overlay and raises the selected window once.
    /// Guards `isCmdDown` so a stray Cmd-up with no prior Cmd-down is a no-op.
    public func endSession() {
        guard isCmdDown else { return }
        isCmdDown = false
        previewer.hide()
        guard snapshot.indices.contains(cursor) else { return }
        raiser.raise(snapshot[cursor])
    }
}
