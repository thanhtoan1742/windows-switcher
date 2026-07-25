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
        panel.ignoresMouseEvents = true
    }

    func show(thumbnails: [(WindowInfo, CGImage)], startingAt index: Int) {
        guard !thumbnails.isEmpty,
              let screen = NSScreen.screens.first else { return }
        tearDownCells()
        pairs = thumbnails
        let cellSize = computeCellSize(count: pairs.count, screen: screen)
        buildCells(cellSize: cellSize)
        layoutRow(cellSize: cellSize)
        sizeAndCenterPanel(cellSize: cellSize, screen: screen)
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
        applyRing(to: index)
    }

    func hide() {
        panel.orderOut(nil)
        tearDownCells()
        pairs = []
    }

    // MARK: - Cell sizing

    private func computeCellSize(count: Int, screen: NSScreen) -> CGSize {
        RowLayout.cellSize(count: count, availableWidth: screen.visibleFrame.width)
    }

    // MARK: - Cell building

    private func buildCells(cellSize: CGSize) {
        for _ in 0..<pairs.count {
            let cell = NSImageView()
            cell.imageScaling = .scaleProportionallyDown
            cell.imageAlignment = .alignCenter
            cell.wantsLayer = true
            cell.layer?.cornerRadius = ThumbnailOverlay.cornerRadius
            cell.layer?.masksToBounds = true
            cell.frame = CGRect(origin: .zero, size: cellSize)
            panel.contentView?.addSubview(cell)
            imageViews.append(cell)
        }
    }

    private func layoutRow(cellSize: CGSize) {
        let stride = cellSize.width + RowLayout.defaultSpacing
        for (i, cell) in imageViews.enumerated() {
            let origin = CGPoint(x: CGFloat(i) * stride, y: 0)
            cell.frame = CGRect(origin: origin, size: cellSize)
        }
    }

    private func sizeAndCenterPanel(cellSize: CGSize, screen: NSScreen) {
        let row = RowLayout.rowSize(cellSize: cellSize, count: imageViews.count)
        panel.setContentSize(row)
        let o = RowLayout.origin(rowSize: row, screenFrame: screen.visibleFrame)
        panel.setFrameOrigin(o)
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
