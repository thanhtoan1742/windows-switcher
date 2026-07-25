import CoreGraphics
import Foundation

struct WindowInfo: Equatable {
    let windowID: CGWindowID
    let ownerPID: pid_t
    let ownerName: String
    let bounds: CGRect
    let layer: Int
    let alpha: Double
}

enum WindowLister {
    /// Filter raw CGWindowList entries down to actual switchable windows, preserving
    /// the front-to-back order returned by the Window Server (index 0 == frontmost).
    static func filter(_ raw: [[String: Any]]) -> [WindowInfo] {
        var out: [WindowInfo] = []
        for entry in raw {
            guard let layer = (entry[kCGWindowLayer as String] as? NSNumber)?.intValue,
                  layer == 0 else { continue }
            guard let alpha = (entry[kCGWindowAlpha as String] as? NSNumber)?.doubleValue,
                  alpha > 0 else { continue }
            guard let wid = (entry[kCGWindowNumber as String] as? NSNumber)?.uint32Value else { continue }
            guard let pid = (entry[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value else { continue }
            let ownerName = (entry[kCGWindowOwnerName as String] as? String) ?? ""
            guard let boundsDict = entry[kCGWindowBounds as String] as? [String: Any],
                  let bounds = CGRect(dictionaryRepresentation: boundsDict as CFDictionary),
                  bounds.width > 0, bounds.height > 0 else { continue }
            if isSystemOwner(ownerName) { continue }
            out.append(WindowInfo(
                windowID: wid, ownerPID: pid, ownerName: ownerName,
                bounds: bounds, layer: layer, alpha: alpha
            ))
        }
        return out
    }

    /// Live fetch from the Window Server. `.optionOnScreenOnly` is Space-aware so this
    /// returns only windows on the current Space. Cross-Space support would change only
    /// this method (see spec "Non-Goals").
    static func currentSpaceWindows() -> [WindowInfo] {
        guard let raw = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[String: Any]] else { return [] }
        return filter(raw)
    }

    private static let systemOwners: Set<String> = [
        "Dock", "SystemUIServer", "WindowServer",
        "Control Center", "Wallpaper", "WindowManager"
    ]
    private static func isSystemOwner(_ name: String) -> Bool {
        systemOwners.contains(name)
    }
}
