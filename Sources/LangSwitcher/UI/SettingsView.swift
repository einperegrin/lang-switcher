import SwiftUI
import AppKit
import ServiceManagement

extension Preferences {
    /// Мостик между вычисляемыми свойствами класса и SwiftUI-биндингами.
    func binding<T>(_ keyPath: ReferenceWritableKeyPath<Preferences, T>) -> Binding<T> {
        Binding(get: { self[keyPath: keyPath] }, set: { self[keyPath: keyPath] = $0 })
    }
}

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralTab().tabItem { Label("Основные", systemImage: "gearshape") }
            HotkeysTab().tabItem { Label("Клавиши", systemImage: "keyboard") }
            AutoReplaceTab().tabItem { Label("Автозамена", systemImage: "text.badge.checkmark") }
            ExclusionsTab().tabItem { Label("Исключения", systemImage: "nosign") }
        }
        .frame(width: 540, height: 400)
    }
}

// MARK: - Основные

private struct GeneralTab: View {
    @ObservedObject private var prefs = Preferences.shared
    @State private var trusted = AXIsProcessTrusted()

    var body: some View {
        Form {
            if !trusted {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundColor(.orange)
                    Text("Нет доступа к вводу. Добавьте LangSwitcher в «Конфиденциальность и безопасность → Универсальный доступ».")
                        .font(.callout)
                    Button("Открыть") { AppDelegate.openAccessibilitySettings() }
                }
                .padding(.bottom, 6)
            }

            Toggle("Автоматически исправлять раскладку", isOn: prefs.binding(\.autoSwitchEnabled))
            Toggle("Не трогать слова с цифрами", isOn: prefs.binding(\.skipWordsWithDigits))

            HStack {
                Text("Минимальная длина слова")
                Stepper(value: prefs.binding(\.minWordLength), in: 2...8) {
                    Text("\(prefs.minWordLength)").monospacedDigit()
                }
            }

            Divider().padding(.vertical, 4)

            Toggle("Звук при переключении", isOn: prefs.binding(\.soundEnabled))
            Picker("Звук", selection: prefs.binding(\.soundName)) {
                ForEach(Sounds.available, id: \.self) { Text($0).tag($0) }
            }
            .disabled(!prefs.soundEnabled)
            .frame(maxWidth: 260)

            Toggle("Показывать раскладку в строке меню", isOn: prefs.binding(\.showLayoutInMenuBar))
            Toggle("Запускать при входе в систему", isOn: launchAtLogin)

            Spacer()
        }
        .padding(20)
        .onAppear { trusted = AXIsProcessTrusted() }
    }

    private var launchAtLogin: Binding<Bool> {
        Binding(
            get: { SMAppService.mainApp.status == .enabled },
            set: { enable in
                do {
                    if enable { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
                    Preferences.shared.launchAtLogin = enable
                } catch {
                    NSSound.beep()
                }
            }
        )
    }
}

// MARK: - Горячие клавиши

private struct HotkeysTab: View {
    @ObservedObject private var prefs = Preferences.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Исправить раскладку последнего слова").font(.headline)
                Picker("", selection: prefs.binding(\.doubleTapKey)) {
                    ForEach(DoubleTapKey.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .labelsHidden()
                .frame(maxWidth: 320)
                Text("Двойное нажатие модификатора подряд, без других клавиш между ними.")
                    .font(.caption).foregroundColor(.secondary)
            }

            Divider()

            HotkeyRow(title: "Раскладка выделенного (или последнего слова)",
                      hotkey: prefs.binding(\.convertLayoutHotkey))
            HotkeyRow(title: "Транслитерация выделенного",
                      hotkey: prefs.binding(\.transliterateHotkey))
            HotkeyRow(title: "Смена регистра выделенного",
                      hotkey: prefs.binding(\.changeCaseHotkey))
            HotkeyRow(title: "Вкл/выкл автопереключение",
                      hotkey: prefs.binding(\.toggleAutoSwitchHotkey))

            Spacer()
            Text("Нажмите на сочетание и введите новое. Esc — отмена.")
                .font(.caption).foregroundColor(.secondary)
        }
        .padding(20)
    }
}

private struct HotkeyRow: View {
    let title: String
    @Binding var hotkey: Hotkey
    @State private var recording = false
    @State private var monitor: Any?

    var body: some View {
        HStack {
            Toggle("", isOn: Binding(get: { hotkey.enabled }, set: { hotkey.enabled = $0 })).labelsHidden()
            Text(title)
            Spacer()
            Button(recording ? "Ждём…" : hotkey.display) { toggle() }
                .frame(minWidth: 110)
                .disabled(!hotkey.enabled)
        }
        .onDisappear(perform: stop)
    }

    private func toggle() {
        if recording { stop(); return }
        recording = true
        // Пока идёт запись, ядро игнорирует комбинации, иначе оно перехватит их первым.
        SwitcherEngine.shared.isRecordingHotkey = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { event in
            if event.keyCode == 53 { stop(); return nil }
            // Битовые значения NSEvent.ModifierFlags и CGEventFlags совпадают.
            let flags = CGEventFlags(rawValue: UInt64(event.modifierFlags.rawValue))
                .intersection(Hotkey.relevantMask)
            guard !flags.isEmpty else { NSSound.beep(); return nil }
            hotkey = Hotkey(keyCode: event.keyCode, modifiers: flags.rawValue, enabled: true)
            stop()
            return nil
        }
    }

    private func stop() {
        recording = false
        SwitcherEngine.shared.isRecordingHotkey = false
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }
}

// MARK: - Автозамена

private struct AutoReplaceTab: View {
    @ObservedObject private var prefs = Preferences.shared
    @State private var from = ""
    @State private var to = ""
    @State private var selection: String?

    private var keys: [String] { prefs.autoReplaceRules.keys.sorted() }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle("Включить автозамену", isOn: prefs.binding(\.autoReplaceEnabled))
            Text("Замена срабатывает, когда слово завершено пробелом или знаком препинания.")
                .font(.caption).foregroundColor(.secondary)

            List(selection: $selection) {
                ForEach(keys, id: \.self) { key in
                    HStack {
                        Text(key).frame(width: 160, alignment: .leading)
                        Text("→").foregroundColor(.secondary)
                        Text(prefs.autoReplaceRules[key] ?? "")
                        Spacer()
                    }
                    .tag(key)
                }
            }
            .frame(minHeight: 180)

            HStack {
                TextField("что", text: $from).frame(width: 150)
                TextField("на что", text: $to)
                Button("Добавить") {
                    let key = from.trimmingCharacters(in: .whitespaces)
                    guard !key.isEmpty, !to.isEmpty else { return }
                    var rules = prefs.autoReplaceRules
                    rules[key] = to
                    prefs.autoReplaceRules = rules
                    from = ""; to = ""
                }
                Button("Удалить") {
                    guard let selection else { return }
                    var rules = prefs.autoReplaceRules
                    rules.removeValue(forKey: selection)
                    prefs.autoReplaceRules = rules
                    self.selection = nil
                }
                .disabled(selection == nil)
            }
        }
        .padding(20)
    }
}

// MARK: - Исключения

private struct ExclusionsTab: View {
    @ObservedObject private var prefs = Preferences.shared
    @State private var selection: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("В этих программах LangSwitcher не анализирует ввод.")
                .font(.callout)

            List(selection: $selection) {
                ForEach(prefs.excludedBundleIDs, id: \.self) { bundleID in
                    HStack {
                        Text(displayName(for: bundleID))
                        Spacer()
                        Text(bundleID).font(.caption).foregroundColor(.secondary)
                    }
                    .tag(bundleID)
                }
            }
            .frame(minHeight: 220)

            HStack {
                Button("Добавить программу…", action: addApplication)
                Button("Удалить") {
                    guard let selection else { return }
                    prefs.excludedBundleIDs.removeAll { $0 == selection }
                    self.selection = nil
                }
                .disabled(selection == nil)
            }
        }
        .padding(20)
    }

    private func displayName(for bundleID: String) -> String {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return bundleID }
        return FileManager.default.displayName(atPath: url.path)
    }

    private func addApplication() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowsMultipleSelection = true
        guard panel.runModal() == .OK else { return }
        var list = prefs.excludedBundleIDs
        for url in panel.urls {
            if let bundleID = Bundle(url: url)?.bundleIdentifier, !list.contains(bundleID) {
                list.append(bundleID)
            }
        }
        prefs.excludedBundleIDs = list
    }
}
