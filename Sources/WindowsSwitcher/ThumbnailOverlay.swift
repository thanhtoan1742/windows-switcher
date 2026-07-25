import Cocoa
import CoreGraphics
import WindowsSwitcherCore

/// Centered, borderless, non-activating panel showing a single window thumbnail.
/// Conforms to `WindowPreviewing` so the `Switcher` can stay pure and unit-testable.
final class ThumbnailOverlay: WindowPreviewing {
    private let panel: NSPanel
    private let imageView: NSImageView
    private var pairs: [(WindowInfo, CGImage)] = []

    private static let maxSize = CGSize(width: 320, height: 240)

    init() {
        self.panel = NSPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .statusBar
        panel.hidesOnDeactivate = false
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        self.imageView = NSImageView()
        imageView.imageAlignment = .alignCenter
        imageView.imageScaling = .scaleProportionallyDown
        panel.contentView = imageView
    }

    func show(thumbnails: [(WindowInfo, CGImage)], startingAt index: Int) {
        pairs = thumbnails
        guard pairs.indices.contains(index) else { return }
        let cg = pairs[index].1
        imageView.image = NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
        panel.setContentSize(cappedSize(cg))
        centerOnMainScreen()
        panel.orderFront(nil)
        if index != 0 { update(index: index) }
    }

    func update(index: Int) {
        guard pairs.indices.contains(index) else { return }
        let cg = pairs[index].1
        imageView.image = NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
    }

    func hide() {
        panel.orderOut(nil)
        pairs = []
        imageView.image = nil
    }

    private func cappedSize(_ cg: CGImage) -> NSSize {
        let natural = NSSize(width: cg.width, height: cg.height)
        let max = ThumbnailOverlay.maxSize
        let scaleW = max.width / natural.width
        let scaleH = max.height / natural.height
        let scale = min(1.0, min(scaleW, scaleH))
        return NSSize(width: natural.width * scale, height: natural.height * scale)
    }

    private func centerOnMainScreen() {
        guard let screen = NSScreen.main else { return }
        let frame = screen.visibleFrame
        let pf = panel.frame
        let x = frame.midX - pf.width / 2
        let y = frame.midY - pf.height / 2
        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }
}
