import CoreGraphics

/// Pure layout math for a centered horizontal row of equal-sized cells, extracted
/// from `ThumbnailOverlay` so the sizing/clamping/centering logic is unit-testable
/// without AppKit. The overlay calls these functions and applies the result to its
/// `NSPanel` and `NSImageView` subviews.
public enum RowLayout {
    public static let defaultMargin: CGFloat = 40
    public static let defaultSpacing: CGFloat = 8
    public static let defaultMaxCell = CGSize(width: 240, height: 180)
    // Reference only; not enforced. Shrink-to-fit drops the floor to avoid
    // off-screen overflow when window count is very high.
    public static let defaultMinCell = CGSize(width: 80, height: 60)

    /// Uniform cell size so all `count` cells fit within `availableWidth` (minus
    /// margins and inter-cell spacing). Cells clamp to `maxCell` when there are
    /// few windows; shrink below `minCell` when there are too many to fit (no floor).
    public static func cellSize(
        count: Int,
        availableWidth: CGFloat,
        margin: CGFloat = defaultMargin,
        spacing: CGFloat = defaultSpacing,
        maxCell: CGSize = defaultMaxCell,
        minCell: CGSize = defaultMinCell
    ) -> CGSize {
        guard count > 0 else { return .zero }
        let aspect = maxCell.height / maxCell.width
        let availWidth = availableWidth - 2 * margin
        let naturalWidth = (availWidth - CGFloat(count - 1) * spacing) / CGFloat(count)
        let cellWidth = min(maxCell.width, naturalWidth)  // shrink-to-fit, no floor
        return CGSize(width: cellWidth, height: cellWidth * aspect)
    }

    /// Total row size for `count` cells of `cellSize` separated by `spacing`.
    public static func rowSize(
        cellSize: CGSize, count: Int, spacing: CGFloat = defaultSpacing
    ) -> CGSize {
        guard count > 0 else { return .zero }
        let width = CGFloat(count) * cellSize.width + CGFloat(count - 1) * spacing
        return CGSize(width: width, height: cellSize.height)
    }

    /// Top-left origin that centers `rowSize` within `screenFrame`.
    public static func origin(rowSize: CGSize, screenFrame: CGRect) -> CGPoint {
        CGPoint(x: screenFrame.midX - rowSize.width / 2,
                y: screenFrame.midY - rowSize.height / 2)
    }
}
