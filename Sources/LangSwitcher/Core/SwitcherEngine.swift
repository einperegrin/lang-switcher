import AppKit
import Carbon.HIToolbox
import os

let appLog = Logger(subsystem: "com.langswitcher.app", category: "engine")

/// Ядро: перехватывает клавиатуру через CGEvent tap, ведёт буфер набранного,
/// принимает решения о переключении раскладки и выполняет коррекции.
final class SwitcherEngine {
    static let shared = SwitcherEngine()

    private let prefs = Preferences.shared
    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    /// Последние нажатия в текущей «строке». Хранится немного — только чтобы
    /// достать последнее слово и хвостовые разделители.
    private var strokes: [KeyStroke] = []
    private let maxStrokes = 96

    private let doubleTap = DoubleTapDetector()
    private var suppressedKeyCodes = Set<UInt16>()
    private var frontmostBundleID: String?
    private let work = DispatchQueue(label: "langswitcher.inject", qos: .userInteractive)

    /// Пока пользователь записывает горячую клавишу в настройках, ядро не реагирует на комбинации.
    var isRecordingHotkey = false

    var isRunning: Bool { tap != nil }
    var onStateChange: (() -> Void)?

    private init() {
        doubleTap.key = prefs.doubleTapKey
        NotificationCenter.default.addObserver(self, selector: #selector(preferencesChanged),
                                               name: .preferencesChanged, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(layoutChanged(_:)),
                                               name: .layoutDidChange, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(appActivated(_:)),
                                                          name: NSWorkspace.didActivateApplicationNotification, object: nil)
        frontmostBundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
    }

    @objc private func preferencesChanged() { doubleTap.key = prefs.doubleTapKey }

    @objc private func layoutChanged(_ note: Notification) {
        // Раскладку сменил пользователь — ввод прервался, буфер больше не описывает
        // то, что на экране. Своё же переключение буфер не трогает.
        let mine = note.userInfo?["initiatedBySwitcher"] as? Bool ?? false
        if !mine { resetBuffer() }
    }

    @objc private func appActivated(_ note: Notification) {
        let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
        frontmostBundleID = app?.bundleIdentifier ?? NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        resetBuffer()
    }

    // MARK: - Жизненный цикл перехвата

    @discardableResult
    func start() -> Bool {
        guard tap == nil else { return true }
        let mask: CGEventMask =
            (1 << CGEventType.keyDown.rawValue) |
            (1 << CGEventType.keyUp.rawValue) |
            (1 << CGEventType.flagsChanged.rawValue) |
            (1 << CGEventType.leftMouseDown.rawValue) |
            (1 << CGEventType.rightMouseDown.rawValue)

        let callback: CGEventTapCallBack = { _, type, event, refcon in
            guard let refcon else { return Unmanaged.passUnretained(event) }
            let engine = Unmanaged<SwitcherEngine>.fromOpaque(refcon).takeUnretainedValue()
            return engine.handle(type: type, event: event)
        }

        guard let newTap = CGEvent.tapCreate(tap: .cgSessionEventTap,
                                             place: .headInsertEventTap,
                                             options: .defaultTap,
                                             eventsOfInterest: mask,
                                             callback: callback,
                                             userInfo: Unmanaged.passUnretained(self).toOpaque()) else {
            appLog.error("Не удалось создать event tap — нет доступа в «Универсальном доступе»")
            return false
        }
        tap = newTap
        appLog.notice("Перехват клавиатуры запущен, раскладок доступно: \(LayoutManager.shared.convertibleLayouts.count, privacy: .public)")
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, newTap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: newTap, enable: true)
        onStateChange?()
        return true
    }

    func stop() {
        if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let runLoopSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes) }
        tap = nil
        runLoopSource = nil
        onStateChange?()
    }

    // MARK: - Обработка событий

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        let passthrough = Unmanaged.passUnretained(event)

        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return nil
        }
        // Свои же синтетические события пропускаем без анализа.
        if event.getIntegerValueField(.eventSourceUserData) == TextInjector.magic { return passthrough }

        switch type {
        case .leftMouseDown, .rightMouseDown:
            resetBuffer()
            return passthrough
        case .flagsChanged:
            guard !isRecordingHotkey, isAllowedInFrontmostApp else { return passthrough }
            let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
            // CGEvent.timestamp числится в наносекундах, но содержит сырой mach_absolute_time.
            // На Apple Silicon это тики 24 МГц — разница с наносекундами в 41.7 раза,
            // из-за чего «0.4 с» превращались в 16 реальных секунд. Берём время сами.
            let timestamp = ProcessInfo.processInfo.systemUptime
            if doubleTap.handle(keyCode: keyCode, flags: event.flags, timestamp: timestamp) {
                correctLastWord()
            }
            return passthrough
        case .keyUp:
            let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
            if suppressedKeyCodes.remove(keyCode) != nil { return nil }
            return passthrough
        case .keyDown:
            return handleKeyDown(event) ? nil : passthrough
        default:
            return passthrough
        }
    }

    /// Возвращает true, если событие нужно поглотить.
    private func handleKeyDown(_ event: CGEvent) -> Bool {
        let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
        let flags = event.flags
        doubleTap.noteOtherInput()

        guard !isRecordingHotkey else { return false }

        // Горячие клавиши проверяются до исключений: пользователь нажал их осознанно,
        // и работать они должны везде. Исключения запрещают лишь молчаливый анализ ввода.
        if let action = matchedAction(keyCode: keyCode, flags: flags) {
            suppressedKeyCodes.insert(keyCode)
            perform(action)
            return true
        }

        // Пароли: система и так не отдаёт события в tap при secure input, но проверим явно.
        if IsSecureEventInputEnabled() {
            resetBuffer()
            return false
        }
        guard isAllowedInFrontmostApp else {
            resetBuffer()
            return false
        }

        // Любое сочетание с ⌘/⌃ — это команда, а не набор текста.
        if flags.contains(.maskCommand) || flags.contains(.maskControl) {
            resetBuffer()
            return false
        }

        if keyCode == 51 { // backspace
            if !strokes.isEmpty { strokes.removeLast() }
            return false
        }
        if KeyTranslator.resetKeyCodes.contains(keyCode) {
            resetBuffer()
            return false
        }

        guard let layout = LayoutManager.shared.currentLayout,
              let data = layout.layoutData,
              let text = KeyTranslator.string(keyCode: keyCode, flags: flags, layoutData: data),
              let scalar = text.unicodeScalars.first,
              scalar.value >= 0x20, scalar.value != 0x7F else {
            resetBuffer()
            return false
        }

        let stroke = KeyStroke(keyCode: keyCode, flags: flags, text: text, layoutID: layout.id)

        if stroke.isWordCharacter {
            append(stroke)
            return false
        }

        // Разделитель — слово закончено. Если нужна коррекция, событие поглощаем
        // и печатаем разделитель сами: так порядок символов гарантирован.
        let job = handleWordBoundary(separator: stroke)
        append(stroke)
        if let job {
            work.async(execute: job)
            return true
        }
        return false
    }

    private var isAllowedInFrontmostApp: Bool {
        guard let bundleID = frontmostBundleID else { return true }
        return !prefs.excludedBundleIDs.contains(bundleID)
    }

    // MARK: - Буфер

    private func append(_ stroke: KeyStroke) {
        strokes.append(stroke)
        if strokes.count > maxStrokes { strokes.removeFirst(strokes.count - maxStrokes) }
    }

    func resetBuffer() {
        strokes.removeAll(keepingCapacity: true)
        doubleTap.noteOtherInput()
    }

    /// Хвостовые разделители (например, уже набранный пробел) и слово перед ними.
    private func trailingWordWithTail() -> (word: [KeyStroke], tail: [KeyStroke]) {
        var tailCount = 0
        var index = strokes.count - 1
        while index >= 0, !strokes[index].isWordCharacter {
            tailCount += 1
            index -= 1
        }
        var wordCount = 0
        while index >= 0, strokes[index].isWordCharacter {
            wordCount += 1
            index -= 1
        }
        let tail = Array(strokes.suffix(tailCount))
        let word = Array(strokes.dropLast(tailCount).suffix(wordCount))
        return (word, tail)
    }

    // MARK: - Автокоррекция на границе слова

    private func handleWordBoundary(separator: KeyStroke) -> (() -> Void)? {
        let word = trailingWordWithTail().word
        guard !word.isEmpty else { return nil }
        let originalText = word.map(\.text).joined()

        var finalText = originalText
        var target: KeyboardLayout?

        if prefs.autoSwitchEnabled,
           word.count >= prefs.minWordLength,
           !(prefs.skipWordsWithDigits && originalText.contains(where: { $0.isNumber })),
           let current = LayoutManager.shared.currentLayout,
           let decision = LayoutDetector.shared.decideTarget(word: word, current: current) {
            finalText = decision.text
            target = decision.layout
        }

        var replaced = false
        if prefs.autoReplaceEnabled {
            let rules = prefs.autoReplaceRules
            if let replacement = rules[finalText] ?? rules[finalText.lowercased()] {
                finalText = Self.applyCase(of: finalText, to: replacement)
                replaced = true
            }
        }

        guard finalText != originalText else { return nil }

        let deleteCount = originalText.count
        let insertText = finalText + separator.text

        if let target, !replaced, let rendered = LayoutManager.shared.render(word, in: target) {
            let head = strokes.count - word.count
            strokes = Array(strokes.prefix(head)) + rendered.strokes
        } else {
            // Текст на экране больше не соответствует нажатиям (автозамена или
            // непереводимое слово) — держать рассинхронизированный буфер опаснее,
            // чем потерять историю: следующая коррекция удалила бы не те символы.
            strokes.removeAll(keepingCapacity: true)
        }

        let switchTo = target
        return {
            TextInjector.backspace(deleteCount)
            TextInjector.type(insertText)
            if let switchTo {
                DispatchQueue.main.async {
                    LayoutManager.shared.select(switchTo, initiatedBySwitcher: true)
                    Sounds.playSwitch()
                }
            }
        }
    }

    private static func applyCase(of source: String, to replacement: String) -> String {
        if source == source.uppercased(), source.contains(where: { $0.isLetter }), source.count > 1 {
            return replacement.uppercased()
        }
        if let first = source.first, first.isUppercase {
            return replacement.prefix(1).uppercased() + replacement.dropFirst()
        }
        return replacement
    }

    // MARK: - Действия

    enum Action {
        case correctLastWord
        case convertLayout
        case transliterate
        case changeCase
        case toggleAutoSwitch
    }

    private func matchedAction(keyCode: UInt16, flags: CGEventFlags) -> Action? {
        if prefs.convertLayoutHotkey.matches(keyCode: keyCode, flags: flags) { return .convertLayout }
        if prefs.transliterateHotkey.matches(keyCode: keyCode, flags: flags) { return .transliterate }
        if prefs.changeCaseHotkey.matches(keyCode: keyCode, flags: flags) { return .changeCase }
        if prefs.toggleAutoSwitchHotkey.matches(keyCode: keyCode, flags: flags) { return .toggleAutoSwitch }
        return nil
    }

    func perform(_ action: Action) {
        switch action {
        case .correctLastWord:
            correctLastWord()
        case .convertLayout:
            // Есть выделение — правим его; нет — последнее слово (как Shift+Break в Punto).
            SelectionService.transformSelection({ text in
                guard let current = LayoutManager.shared.currentLayout,
                      let decision = LayoutDetector.shared.bestTargetForText(text, current: current) else { return nil }
                DispatchQueue.main.async {
                    LayoutManager.shared.select(decision.layout, initiatedBySwitcher: true)
                    Sounds.playSwitch()
                }
                return decision.text
            }, fallback: { [weak self] in
                self?.correctLastWord()
            })
        case .transliterate:
            SelectionService.transformSelection({ Transliterator.transliterate($0) })
        case .changeCase:
            SelectionService.transformSelection({ CaseCycler.cycle($0) })
        case .toggleAutoSwitch:
            prefs.autoSwitchEnabled.toggle()
            Sounds.playSwitch()
            onStateChange?()
        }
    }

    /// Перевод последнего набранного слова в другую раскладку — основной ручной сценарий.
    func correctLastWord() {
        guard let current = LayoutManager.shared.currentLayout else { NSSound.beep(); return }
        let (word, tail) = trailingWordWithTail()
        guard !word.isEmpty else { NSSound.beep(); return }
        guard let decision = LayoutDetector.shared.bestTarget(word: word, excluding: current),
              let rendered = LayoutManager.shared.render(word, in: decision.layout) else {
            NSSound.beep()
            return
        }

        let tailText = tail.map(\.text).joined()
        let deleteCount = word.map(\.text).joined().count + tailText.count
        let insertText = rendered.text + tailText

        let head = strokes.count - (word.count + tail.count)
        strokes = Array(strokes.prefix(head)) + rendered.strokes + tail

        let target = decision.layout
        work.async {
            TextInjector.waitForModifiersRelease()
            TextInjector.backspace(deleteCount)
            TextInjector.type(insertText)
            DispatchQueue.main.async {
                LayoutManager.shared.select(target, initiatedBySwitcher: true)
                Sounds.playSwitch()
            }
        }
    }
}
