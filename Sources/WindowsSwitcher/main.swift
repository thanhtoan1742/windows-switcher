import Cocoa
import ApplicationServices
import WindowsSwitcherCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var eventTap: EventTap!
    private var switcher: Switcher!
    private var raiser: WindowRaiser!
    private var tapStarted: Bool = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        raiser = WindowRaiser()
        switcher = Switcher(raiser: raiser)
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = statusIcon(trusted: AXIsProcessTrusted())
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
    }

    private func tryStartTap() {
        guard AXIsProcessTrusted() else {
            tapStarted = false
            statusItem.button?.image = statusIcon(trusted: false)
            buildMenu()
            return
        }
        do {
            try eventTap.start()
            tapStarted = true
            statusItem.button?.image = statusIcon(trusted: true)
        } catch {
            tapStarted = false
            statusItem.button?.image = statusIcon(trusted: false)
        }
        buildMenu()
    }

    @objc private func appActivated() {
        if !tapStarted { tryStartTap() }
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

    private func statusIcon(trusted: Bool) -> NSImage {
        let image = NSImage(size: NSSize(width: 14, height: 14), flipped: false) { rect in
            (trusted ? NSColor.systemGreen : NSColor.systemRed).setFill()
            NSBezierPath(ovalIn: rect.insetBy(dx: 2.5, dy: 2.5)).fill()
            return true
        }
        image.isTemplate = false
        return image
    }

    private func buildMenu() {
        let menu = NSMenu()
        let title = AXIsProcessTrusted()
            ? "Windows Switcher: Active"
            : "Windows Switcher: Needs Accessibility Permission"
        menu.addItem(withTitle: title, action: nil, keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        statusItem.menu = menu
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
