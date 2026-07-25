import AppKit
import SwiftUI

final class SettingsWindowController {
    static let shared = SettingsWindowController()
    private var window: NSWindow?

    private init() {}

    func show() {
        if window == nil {
            let hosting = NSHostingView(rootView: SettingsView())
            let newWindow = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 540, height: 400),
                                     styleMask: [.titled, .closable, .miniaturizable],
                                     backing: .buffered,
                                     defer: false)
            newWindow.title = "Настройки LangSwitcher"
            newWindow.contentView = hosting
            newWindow.isReleasedWhenClosed = false
            newWindow.center()
            window = newWindow
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}
