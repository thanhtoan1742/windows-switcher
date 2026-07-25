import Testing
import CoreGraphics
import Foundation
@testable import WindowsSwitcherCore

final class MockPreviewer: WindowPreviewing {
    var showCalls: [(thumbnails: [(WindowInfo, CGImage)], startingAt: Int)] = []
    var updateCalls: [Int] = []
    var hideCallCount: Int = 0

    func show(thumbnails: [(WindowInfo, CGImage)], startingAt index: Int) {
        showCalls.append((thumbnails, index))
    }
    func update(index: Int) { updateCalls.append(index) }
    func hide() { hideCallCount += 1 }
}

final class MockCapturer: ThumbnailCapturing {
    var results: [UInt32: CGImage?] = [:]   // windowID -> image or nil
    var captureOrder: [UInt32] = []
    var defaultReturn: CGImage? = nil

    func capture(_ window: WindowInfo) -> CGImage? {
        captureOrder.append(window.windowID)
        if let r = results[window.windowID] {
            return r
        }
        return defaultReturn
    }
}

/// Makes a 1x1 CGImage suitable as a placeholder thumbnail in tests.
func makeTestImage() -> CGImage? {
    let context = CGContext(
        data: nil, width: 1, height: 1,
        bitsPerComponent: 8, bytesPerRow: 4,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )
    return context?.makeImage()
}
