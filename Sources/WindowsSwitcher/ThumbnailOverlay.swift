import Cocoa
import CoreGraphics
import WindowsSwitcherCore

/// Centered, borderless, non-activating panel showing all window thumbnails
/// in a horizontal row. A selection ring indicates the currently-selected
/// window. Conforms to `WindowPreviewing` so the `Switcher` can stay pure
/// and unit-testable.
final class ThumbnailOverlay: WindowPreviewing {
    private let panel: NSPanel
    private var pairs: [(WindowInfo, CGImage)] = []
    private var imageViews: [NSImageView] = []
    private var selectedIndex: Int = 0

    private static let margin: CGFloat = 40
    private static let spacing: CGFloat = 8
    private static let maxCell = CGSize(width: 240, height: 180)
    private static let minCell = CGSize(width: 80, height: 60)
    private static let aspect = maxCell.height / maxCell.width   // 0.75 (4:3)
    private static let borderWidth: CGFloat = 3
    private static let cornerRadius: CGFloat = 6

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
    }

    func show(thumbnails: [(WindowInfo, CGImage)], startingAt index: Int) {
        guard !thumbnails.isEmpty else { return }
        tearDownCells()
        pairs = thumbnails
        let cellSize = computeCellSize(count: pairs.count)
        buildCells(cellSize: cellSize)
        layoutRow(cellSize: cellSize)
        sizeAndCenterPanel(cellSize: cellSize)
        applyImages()
        panel.orderFront(nil)
        guard pairs.indices.contains(index) else { return }
        selectedIndex = index
        applyRing(to: index)
    }

    func update(index: Int) {
        guard pairs.indices.contains(index) else { return }
        if selectedIndex != index {
            imageViews[selectedIndex].layer?.borderWidth = 0
        }
        selectedIndex = index
        imageViews[index].layer?.borderWidth = ThumbnailOverlay.borderWidth
        imageViews[index].layer?.borderColor = NSColor.controlAccentColor.cgColor
    }

    func hide() {
        panel.orderOut(nil)
        tearDownCells()
        pairs = []
    }

    // MARK: - Cell sizing

    private func computeCellSize(count: Int) -> CGSize {
        guard let screen = NSScreen.main else {
            return ThumbnailOverlay.maxCell
        }
        let availWidth = screen.visibleFrame.width - 2 * ThumbnailOverlay.margin
        let naturalWidth = (availWidth - CGFloat(count - 1) * ThumbnailOverlay.spacing) / CGFloat(count)
        let cellWidth = min(ThumbnailOverlay.maxCell.width,
                            max(ThumbnailOverlay.minCell.width, naturalWidth))
        let cellHeight = cellWidth * ThumbnailOverlay.aspect
        return CGSize(width: cellWidth, height: cellHeight)
    }

    // MARK: - Cell building

    private func buildCells(cellSize: CGSize) {
        for _ in 0..<pairs.count {
            let cell = NSImageView()
            cell.imageScaling = .scaleProportionallyDown
            cell.imageAlignment = .alignCenter
            cell.layer = CALayer()
            cell.wantsLayer = true
            cell.layer?.cornerRadius = ThumbnailOverlay.cornerRadius
            cell.layer?.masksToBounds = true
            cell.frame = CGRect(origin: .zero, size: cellSize)
            panel.contentView?.addSubview(cell)
            imageViews.append(cell)
        }
    }

    private func layoutRow(cellSize: CGSize) {
        let stride = cellSize.width + ThumbnailOverlay.spacing
        for (i, cell) in imageViews.enumerated() {
            let origin = CGPoint(x: CGFloat(i) * stride, y: 0)
            cell.frame = CGRect(origin: origin, size: cellSize)
        }
    }

    private func sizeAndCenterPanel(cellSize: CGSize) {
        let n = imageViews.count
        let rowWidth = CGFloat(n) * cellSize.width + CGFloat(n - 1) * ThumbnailOverlay.spacing
        let rowHeight = cellSize.height
        panel.setContentSize(CGSize(width: rowWidth, height: rowHeight))
        guard let screen = NSScreen.main else { return }
        let frame = screen.visibleFrame
        let x = frame.midX - rowWidth / 2
        let y = frame.midY - rowHeight / 2
        panel.setFrameOrigin(CGPoint(x: x, y: y))
    }

    private func applyImages() {
        for (i, pair) in pairs.enumerated() {
            let cg = pair.1
            imageViews[i].image = NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
        }
    }

    private func applyRing(to index: Int) {
        imageViews[index].layer?.borderWidth = ThumbnailOverlay.borderWidth
        imageViews[index].layer?.borderColor = NSColor.controlAccentColor.cgColor
    }

    private func tearDownCells() {
        for cell in imageViews {
            cell.image = nil
            cell.layer?.borderWidth = 0
            cell.removeFromSuperview()
        }
        imageViews.removeAll()
        selectedIndex = 0
    }
}
