import Cocoa
import ApplicationServices
import WindowsSwitcherCore

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var eventTap: EventTap!
    private var switcher: Switcher!
    private var raiser: WindowRaiser!
    private var capturer: ThumbnailCapturer!
    private var previewer: ThumbnailOverlay!
    private var tapStarted: Bool = false
    private var appearanceObserver: NSKeyValueObservation?

    func applicationDidFinishLaunching(_ notification: Notification) {
        raiser = WindowRaiser()
        capturer = ThumbnailCapturer()
        previewer = ThumbnailOverlay()
        switcher = Switcher(raiser: raiser, previewer: previewer, capturer: capturer)
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        refreshStatusIcon()
        buildMenu()

        eventTap = EventTap { [weak self] action in
            self?.handle(action)
        }
        tryStartTap()

        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(appActivated),
            name: NSWorkspace.didActivateApplicationNotification, object: nil
        )
        _ = AXIsProcessTrustedWithOptions(
            [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        )
        _ = CGPreflightScreenCaptureAccess() || CGRequestScreenCaptureAccess()
    }

    private func tryStartTap() {
        guard AXIsProcessTrusted() else {
            tapStarted = false
            refreshStatusIcon()
            buildMenu()
            return
        }
        do {
            try eventTap.start()
            tapStarted = true
        } catch {
            tapStarted = false
        }
        refreshStatusIcon()
        buildMenu()
    }

    @objc private func appActivated() {
        if !tapStarted { tryStartTap() }
        refreshStatusIcon()
    }

    private func handle(_ action: KeyAction) {
        switch action {
        case .cmdDown:
            break  // Session starts on the first Tab, not on Cmd-down.
        case .cmdUp:
            switcher.endSession()
        case .tabForward:
            if switcher.sessionActive {
                switcher.tap(forward: true)
            } else {
                switcher.beginSession(windows: WindowLister.currentSpaceWindows(), forward: true)
            }
        case .tabBackward:
            if switcher.sessionActive {
                switcher.tap(forward: false)
            } else {
                switcher.beginSession(windows: WindowLister.currentSpaceWindows(), forward: false)
            }
        case .ignore:
            break
        }
    }

    private struct StatusImages {
        let primary: NSImage
        let alternate: NSImage
    }

    private func statusImages() -> StatusImages {
        let trusted = AXIsProcessTrusted()
        let screenRecordingOk = CGPreflightScreenCaptureAccess()
        let badgeColor: NSColor?
        if !trusted { badgeColor = .systemRed }
        else if !screenRecordingOk { badgeColor = .systemOrange }
        else { badgeColor = nil }

        let symbol = NSImage(
            systemSymbolName: "arrow.right.arrow.left.square",
            accessibilityDescription: "Windows Switcher"
        )!
        let canvasSize = NSSize(width: 18, height: 18)
        let symbolSize = NSSize(width: 14, height: 14)
        let badgeRadius: CGFloat = 3.0
        let badgeInset: CGFloat = 1.5

        func compose(symbolTint: NSColor) -> NSImage {
            let image = NSImage(size: canvasSize, flipped: false) { rect in
                let symbolRect = NSRect(
                    x: (canvasSize.width - symbolSize.width) / 2,
                    y: (canvasSize.height - symbolSize.height) / 2,
                    width: symbolSize.width,
                    height: symbolSize.height
                )
                let tinted = symbol.tinted(symbolTint)
                tinted.draw(in: symbolRect,
                            from: .zero,
                            operation: .sourceOver,
                            fraction: 1.0)
                if let badgeColor {
                    let badgeRect = NSRect(
                        x: rect.maxX - badgeInset - badgeRadius * 2,
                        y: rect.minY + badgeInset,
                        width: badgeRadius * 2,
                        height: badgeRadius * 2
                    )
                    badgeColor.setFill()
                    NSBezierPath(ovalIn: badgeRect).fill()
                }
                return true
            }
            image.isTemplate = false
            return image
        }

        return StatusImages(
            primary: compose(symbolTint: .controlTextColor),
            alternate: compose(symbolTint: .white)
        )
    }

    private func refreshStatusIcon() {
        let images = statusImages()
        statusItem.button?.image = images.primary
        statusItem.button?.alternateImage = images.alternate
    }

    private func buildMenu() {
        let menu = NSMenu()
        let trusted = AXIsProcessTrusted()
        let screenRecordingOk = CGPreflightScreenCaptureAccess()
        let title: String
        if !trusted {
            title = "Windows Switcher: Needs Accessibility Permission"
        } else if !screenRecordingOk {
            title = "Windows Switcher: Needs Screen Recording Permission"
        } else {
            title = "Windows Switcher: Active"
        }
        menu.addItem(withTitle: title, action: nil, keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        statusItem.menu = menu
    }
}

MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    app.run()
}

private extension NSImage {
    func tinted(_ color: NSColor) -> NSImage {
        let tinted = NSImage(size: size, flipped: false) { rect in
            self.draw(in: rect)
            color.setFill()
            rect.fill(using: .sourceAtop)
            return true
        }
        tinted.isTemplate = false
        return tinted
    }
}
