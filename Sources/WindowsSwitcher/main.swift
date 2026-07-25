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

    func applicationDidFinishLaunching(_ notification: Notification) {
        raiser = WindowRaiser()
        capturer = ThumbnailCapturer()
        previewer = ThumbnailOverlay()
        switcher = Switcher(raiser: raiser, previewer: previewer, capturer: capturer)
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = statusIcon()
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
            statusItem.button?.image = statusIcon()
            buildMenu()
            return
        }
        do {
            try eventTap.start()
            tapStarted = true
        } catch {
            tapStarted = false
        }
        statusItem.button?.image = statusIcon()
        buildMenu()
    }

    @objc private func appActivated() {
        if !tapStarted { tryStartTap() }
        statusItem.button?.image = statusIcon()
    }

    private func handle(_ action: KeyAction) {
        switch action {
        case .cmdDown:
            switcher.beginSession(windows: WindowLister.currentSpaceWindows())
        case .cmdUp:
            switcher.endSession()
        case .tabForward:
            switcher.tap(forward: true)
        case .tabBackward:
            switcher.tap(forward: false)
        case .ignore:
            break
        }
    }

    private func statusIcon() -> NSImage {
        let trusted = AXIsProcessTrusted()
        let screenRecordingOk = CGPreflightScreenCaptureAccess()
        let color: NSColor
        if !trusted { color = .systemRed }
        else if !screenRecordingOk { color = .systemOrange }
        else { color = .systemGreen }
        let image = NSImage(size: NSSize(width: 14, height: 14), flipped: false) { rect in
            color.setFill()
            NSBezierPath(ovalIn: rect.insetBy(dx: 2.5, dy: 2.5)).fill()
            return true
        }
        image.isTemplate = false
        return image
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
