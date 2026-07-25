import AppKit
import ApplicationServices

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var menuBar: MenuBarController?
    private var permissionTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        LayoutManager.shared.start()
        LanguageModel.warmUp()
        menuBar = MenuBarController()

        if AXIsProcessTrusted() {
            _ = SwitcherEngine.shared.start()
        } else {
            appLog.notice("Доступ к вводу пока не выдан — ждём разрешения пользователя")
            requestAccessibilityPermission()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        SwitcherEngine.shared.stop()
    }

    /// Без «Универсального доступа» CGEvent tap не создаётся — просим разрешение
    /// и ждём его в фоне, чтобы не заставлять пользователя перезапускать программу.
    func requestAccessibilityPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)

        permissionTimer?.invalidate()
        permissionTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] timer in
            guard AXIsProcessTrusted() else { return }
            // Доступ может «числиться», но не работать: запись TCC привязана к cdhash
            // предыдущей сборки. Тогда tap не создастся — и сдаваться нельзя,
            // иначе программа замолчит навсегда, хотя пользователь всё сделал верно.
            guard SwitcherEngine.shared.start() else {
                appLog.error("Доступ числится выданным, но перехват не запускается — устаревшая запись TCC")
                return
            }
            timer.invalidate()
            self?.permissionTimer = nil
            self?.menuBar?.refresh()
        }
    }

    static func openAccessibilitySettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }
}
