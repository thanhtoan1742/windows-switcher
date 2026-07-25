import Testing
import CoreGraphics
@testable import WindowsSwitcherCore

@Suite("RowLayout")
struct RowLayoutTests {
    private let screen = CGRect(x: 0, y: 0, width: 1920, height: 1080)

    @Test func cellSizeFewWindowsClampsToMax() {
        let s = RowLayout.cellSize(count: 3, availableWidth: screen.width)
        #expect(s.width == 240)
        #expect(s.height == 180)
    }
    @Test func cellSizeManyWindowsShrinksBelowMin() {
        let s = RowLayout.cellSize(count: 50, availableWidth: screen.width)
        // 50 cells in 1920-80=1840 width: (1840 - 49*8) / 50 = 29.0
        #expect(s.width < 80)          // below the former minCell floor
        #expect(s.width > 0)
        #expect(s.height == s.width * (180.0 / 240.0))
    }
    @Test func cellSizeZeroCountReturnsZero() {
        let s = RowLayout.cellSize(count: 0, availableWidth: screen.width)
        #expect(s == .zero)
    }
    @Test func rowSizeMatchesCellSizeAndCount() {
        let cell = CGSize(width: 100, height: 75)
        let r = RowLayout.rowSize(cellSize: cell, count: 4)
        // 4*100 + 3*8 = 424
        #expect(r.width == 424)
        #expect(r.height == 75)
    }
    @Test func rowSizeZeroCountReturnsZero() {
        let r = RowLayout.rowSize(cellSize: CGSize(width: 100, height: 75), count: 0)
        #expect(r == .zero)
    }
    @Test func originCentersRowOnScreen() {
        let row = CGSize(width: 400, height: 100)
        let o = RowLayout.origin(rowSize: row, screenFrame: screen)
        #expect(o.x == CGFloat((1920 - 400) / 2))
        #expect(o.y == CGFloat((1080 - 100) / 2))
    }
    @Test func rowFitsWithinVisibleWidthForManyWindows() {
        // 50 windows at shrink-to-fit must produce a row that fits within
        // screen.width - 2*defaultMargin.
        let cell = RowLayout.cellSize(count: 50, availableWidth: screen.width)
        let row = RowLayout.rowSize(cellSize: cell, count: 50)
        let availWidth = screen.width - 2 * RowLayout.defaultMargin
        #expect(row.width <= availWidth)
    }
}
