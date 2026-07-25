import AppKit
import ApplicationServices

final class MenuBarController: NSObject, NSMenuDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let prefs = Preferences.shared

    override init() {
        super.init()
        statusItem.menu = buildMenu()
        statusItem.menu?.delegate = self
        SwitcherEngine.shared.onStateChange = { [weak self] in
            DispatchQueue.main.async { self?.refresh() }
        }
        NotificationCenter.default.addObserver(self, selector: #selector(refresh), name: .layoutDidChange, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(refresh), name: .preferencesChanged, object: nil)
        refresh()
    }

    @objc func refresh() {
        guard let button = statusItem.button else { return }
        let code = LayoutManager.shared.currentLayout?.shortCode ?? "??"
        let title = prefs.showLayoutInMenuBar ? code : "⌨"
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 11, weight: .semibold),
            .foregroundColor: prefs.autoSwitchEnabled ? NSColor.labelColor : NSColor.tertiaryLabelColor
        ]
        button.attributedTitle = NSAttributedString(string: title, attributes: attributes)
        button.toolTip = SwitcherEngine.shared.isRunning
            ? "LangSwitcher — автопереключение \(prefs.autoSwitchEnabled ? "включено" : "выключено")"
            : "LangSwitcher — нет доступа к «Универсальному доступу»"
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        buildItems(into: menu)
    }

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()
        buildItems(into: menu)
        return menu
    }

    private func buildItems(into menu: NSMenu) {
        if !SwitcherEngine.shared.isRunning {
            let warning = NSMenuItem(title: "⚠️ Нужен доступ в «Универсальном доступе»",
                                     action: #selector(openAccessibility), keyEquivalent: "")
            warning.target = self
            menu.addItem(warning)
            menu.addItem(.separator())
        }

        let auto = NSMenuItem(title: "Автопереключение раскладки",
                              action: #selector(toggleAutoSwitch), keyEquivalent: "")
        auto.target = self
        auto.state = prefs.autoSwitchEnabled ? .on : .off
        menu.addItem(auto)
        menu.addItem(.separator())

        addAction(to: menu, title: "Исправить последнее слово", detail: prefs.doubleTapKey.title,
                  selector: #selector(correctLastWord))
        addAction(to: menu, title: "Исправить раскладку выделенного", detail: prefs.convertLayoutHotkey.display,
                  selector: #selector(convertLayout))
        addAction(to: menu, title: "Транслитерация выделенного", detail: prefs.transliterateHotkey.display,
                  selector: #selector(transliterate))
        addAction(to: menu, title: "Сменить регистр выделенного", detail: prefs.changeCaseHotkey.display,
                  selector: #selector(changeCase))

        menu.addItem(.separator())
        let settings = NSMenuItem(title: "Настройки…", action: #selector(openSettings), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)

        let quit = NSMenuItem(title: "Выйти из LangSwitcher", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
    }

    private func addAction(to menu: NSMenu, title: String, detail: String, selector: Selector) {
        let item = NSMenuItem(title: title, action: selector, keyEquivalent: "")
        item.target = self
        let attributed = NSMutableAttributedString(string: title, attributes: [
            .font: NSFont.menuFont(ofSize: 0)
        ])
        attributed.append(NSAttributedString(string: "   \(detail)", attributes: [
            .font: NSFont.menuFont(ofSize: 0),
            .foregroundColor: NSColor.secondaryLabelColor
        ]))
        item.attributedTitle = attributed
        menu.addItem(item)
    }

    // MARK: - Действия меню

    @objc private func toggleAutoSwitch() {
        prefs.autoSwitchEnabled.toggle()
        refresh()
    }

    @objc private func correctLastWord() { SwitcherEngine.shared.perform(.correctLastWord) }
    @objc private func convertLayout() { SwitcherEngine.shared.perform(.convertLayout) }
    @objc private func transliterate() { SwitcherEngine.shared.perform(.transliterate) }
    @objc private func changeCase() { SwitcherEngine.shared.perform(.changeCase) }

    @objc private func openAccessibility() { AppDelegate.openAccessibilitySettings() }

    @objc private func openSettings() { SettingsWindowController.shared.show() }

    @objc private func quit() { NSApp.terminate(nil) }
}
