import Foundation
import Combine
import CoreGraphics

extension Notification.Name {
    static let preferencesChanged = Notification.Name("LangSwitcher.preferencesChanged")
}

final class Preferences: ObservableObject {
    static let shared = Preferences()
    private let defaults = UserDefaults.standard
    private init() {}

    private func write<T>(_ value: T, _ key: String) {
        objectWillChange.send()
        defaults.set(value, forKey: key)
        NotificationCenter.default.post(name: .preferencesChanged, object: nil)
    }

    private func writeCodable<T: Codable>(_ value: T, _ key: String) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        write(data, key)
    }

    private func readCodable<T: Codable>(_ key: String, default fallback: T) -> T {
        guard let data = defaults.data(forKey: key),
              let value = try? JSONDecoder().decode(T.self, from: data) else { return fallback }
        return value
    }

    private func readBool(_ key: String, default fallback: Bool) -> Bool {
        defaults.object(forKey: key) as? Bool ?? fallback
    }

    // MARK: - Общие

    var autoSwitchEnabled: Bool {
        get { readBool("autoSwitchEnabled", default: true) }
        set { write(newValue, "autoSwitchEnabled") }
    }

    var minWordLength: Int {
        get { defaults.object(forKey: "minWordLength") as? Int ?? 3 }
        set { write(max(2, newValue), "minWordLength") }
    }

    var skipWordsWithDigits: Bool {
        get { readBool("skipWordsWithDigits", default: true) }
        set { write(newValue, "skipWordsWithDigits") }
    }

    var soundEnabled: Bool {
        get { readBool("soundEnabled", default: true) }
        set { write(newValue, "soundEnabled") }
    }

    var soundName: String {
        get { defaults.string(forKey: "soundName") ?? "Pop" }
        set { write(newValue, "soundName") }
    }

    var showLayoutInMenuBar: Bool {
        get { readBool("showLayoutInMenuBar", default: true) }
        set { write(newValue, "showLayoutInMenuBar") }
    }

    // MARK: - Горячие клавиши

    var doubleTapKey: DoubleTapKey {
        get { DoubleTapKey(rawValue: defaults.string(forKey: "doubleTapKey") ?? "") ?? .rightShift }
        set { write(newValue.rawValue, "doubleTapKey") }
    }

    var convertLayoutHotkey: Hotkey {
        get { readCodable("convertLayoutHotkey", default: .make(keyCode: 37, flags: [.maskControl, .maskAlternate])) } // ⌃⌥L
        set { writeCodable(newValue, "convertLayoutHotkey") }
    }

    var transliterateHotkey: Hotkey {
        get { readCodable("transliterateHotkey", default: .make(keyCode: 17, flags: [.maskControl, .maskAlternate])) } // ⌃⌥T
        set { writeCodable(newValue, "transliterateHotkey") }
    }

    var changeCaseHotkey: Hotkey {
        get { readCodable("changeCaseHotkey", default: .make(keyCode: 32, flags: [.maskControl, .maskAlternate])) } // ⌃⌥U
        set { writeCodable(newValue, "changeCaseHotkey") }
    }

    var toggleAutoSwitchHotkey: Hotkey {
        get { readCodable("toggleAutoSwitchHotkey", default: .make(keyCode: 0, flags: [.maskControl, .maskAlternate])) } // ⌃⌥A
        set { writeCodable(newValue, "toggleAutoSwitchHotkey") }
    }

    // MARK: - Автозамена

    var autoReplaceEnabled: Bool {
        get { readBool("autoReplaceEnabled", default: true) }
        set { write(newValue, "autoReplaceEnabled") }
    }

    var autoReplaceRules: [String: String] {
        get { defaults.dictionary(forKey: "autoReplaceRules") as? [String: String] ?? [:] }
        set { write(newValue, "autoReplaceRules") }
    }

    // MARK: - Исключения

    var excludedBundleIDs: [String] {
        get {
            defaults.object(forKey: "excludedBundleIDs") as? [String] ?? [
                "com.apple.Terminal",
                "com.googlecode.iterm2",
                "com.apple.keychainaccess",
                "com.1password.1password",
                "com.agilebits.onepassword7"
            ]
        }
        set { write(newValue, "excludedBundleIDs") }
    }

    var launchAtLogin: Bool {
        get { readBool("launchAtLogin", default: false) }
        set { write(newValue, "launchAtLogin") }
    }
}
