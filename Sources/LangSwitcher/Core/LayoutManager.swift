import AppKit
import Carbon.HIToolbox

/// Одно нажатие клавиши: физический код + модификаторы + то, что реально напечаталось.
struct KeyStroke {
    let keyCode: UInt16
    let flags: CGEventFlags
    let text: String
    let layoutID: String

    var isWordCharacter: Bool {
        guard let c = text.first, text.count == 1 else { return false }
        return c.isLetter || c.isNumber || c == "'" || c == "\u{2019}"
    }
}

struct RenderedWord {
    let strokes: [KeyStroke]
    let text: String
}

struct KeyboardLayout: Identifiable, Equatable {
    let id: String
    let name: String
    let languages: [String]
    let layoutData: Data?
    let source: TISInputSource

    var primaryLanguage: String {
        languages.first.map { $0.split(separator: "-").first.map(String.init) ?? $0 } ?? ""
    }

    var shortCode: String {
        primaryLanguage.isEmpty ? String(name.prefix(2)).uppercased() : primaryLanguage.uppercased()
    }

    static func == (lhs: KeyboardLayout, rhs: KeyboardLayout) -> Bool { lhs.id == rhs.id }
}

extension Notification.Name {
    static let layoutDidChange = Notification.Name("LangSwitcher.layoutDidChange")
}

/// Роль нажатия в составе слова.
///
/// Ключевой момент: «буква» — понятие, зависящее от раскладки. Клавиши `,` и `.`
/// в английской раскладке дают пунктуацию, а в ЙЦУКЕН — буквы «б» и «ю».
/// Поэтому `,.hj` («бюро», набранное не в той раскладке) — одно слово, а не два
/// разделителя и «hj».
enum StrokeRole {
    /// Буква или цифра в текущей раскладке.
    case letter
    /// В текущей раскладке не буква, но в какой-то другой — буква.
    case ambiguous
    /// Разделитель в любой из установленных раскладок.
    case separator
}

final class LayoutManager {
    static let shared = LayoutManager()

    /// Все включённые раскладки, для которых доступны данные UCKeyboardLayout
    /// (иероглифические IME сюда не попадают — конвертировать их нечем).
    private(set) var convertibleLayouts: [KeyboardLayout] = []
    private(set) var currentLayout: KeyboardLayout?

    private init() {}

    func start() {
        reload()
        let center = DistributedNotificationCenter.default()
        center.addObserver(self,
                           selector: #selector(selectedSourceChanged),
                           name: NSNotification.Name(kTISNotifySelectedKeyboardInputSourceChanged as String),
                           object: nil)
        center.addObserver(self,
                           selector: #selector(enabledSourcesChanged),
                           name: NSNotification.Name(kTISNotifyEnabledKeyboardInputSourcesChanged as String),
                           object: nil)
    }

    @objc private func selectedSourceChanged() {
        refreshCurrent()
        NotificationCenter.default.post(name: .layoutDidChange, object: nil)
    }

    @objc private func enabledSourcesChanged() {
        reload()
        NotificationCenter.default.post(name: .layoutDidChange, object: nil)
    }

    func reload() {
        var found: [KeyboardLayout] = []
        let filter = [kTISPropertyInputSourceCategory as String: kTISCategoryKeyboardInputSource as String] as CFDictionary
        if let list = TISCreateInputSourceList(filter, false)?.takeRetainedValue() {
            for index in 0..<CFArrayGetCount(list) {
                guard let raw = CFArrayGetValueAtIndex(list, index) else { continue }
                let source = Unmanaged<TISInputSource>.fromOpaque(raw).takeUnretainedValue()
                guard boolProperty(source, kTISPropertyInputSourceIsSelectCapable) else { continue }
                guard let layout = makeLayout(source), layout.layoutData != nil else { continue }
                if !found.contains(where: { $0.id == layout.id }) { found.append(layout) }
            }
        }
        convertibleLayouts = found
        roleCache.removeAll()
        alphabetCache.removeAll()
        characterMapCache.removeAll()
        refreshCurrent()
    }

    private func refreshCurrent() {
        guard let source = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue() else { return }
        if let layout = makeLayout(source), layout.layoutData != nil {
            currentLayout = layout
            return
        }
        // Активен IME без uchr-данных — берём подложенную под него ASCII-раскладку.
        if let fallback = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue() {
            currentLayout = makeLayout(fallback)
        }
    }

    /// - Parameter initiatedBySwitcher: переключение сделали мы сами в рамках коррекции.
    ///   Подписчикам это важно: смену раскладки пользователем нужно считать разрывом
    ///   ввода и сбрасывать буфер, а собственную — нет, иначе исправленное слово
    ///   тут же забывается и повторной коррекцией его уже не вернуть.
    func select(_ layout: KeyboardLayout, initiatedBySwitcher: Bool = false) {
        TISSelectInputSource(layout.source)
        currentLayout = layout
        NotificationCenter.default.post(name: .layoutDidChange,
                                        object: nil,
                                        userInfo: ["initiatedBySwitcher": initiatedBySwitcher])
    }

    /// Определяет, может ли нажатие быть частью слова — с оглядкой на все раскладки.
    func role(of stroke: KeyStroke) -> StrokeRole {
        if stroke.isWordCharacter { return .letter }
        let key = UInt64(stroke.keyCode) | (stroke.flags.rawValue << 16)
        if let cached = roleCache[key] { return cached }

        var role = StrokeRole.separator
        for layout in convertibleLayouts where layout.id != stroke.layoutID {
            guard let data = layout.layoutData,
                  let produced = KeyTranslator.string(keyCode: stroke.keyCode, flags: stroke.flags, layoutData: data),
                  produced.count == 1, let character = produced.first, character.isLetter else { continue }
            role = .ambiguous
            break
        }
        roleCache[key] = role
        return role
    }

    private var roleCache: [UInt64: StrokeRole] = [:]

    /// Заново «проигрывает» нажатия в другой раскладке.
    func render(_ strokes: [KeyStroke], in layout: KeyboardLayout) -> RenderedWord? {
        guard let data = layout.layoutData else { return nil }
        var newStrokes: [KeyStroke] = []
        var text = ""
        for stroke in strokes {
            guard let produced = KeyTranslator.string(keyCode: stroke.keyCode, flags: stroke.flags, layoutData: data),
                  !produced.isEmpty,
                  let scalar = produced.unicodeScalars.first, scalar.value >= 0x20 else { return nil }
            newStrokes.append(KeyStroke(keyCode: stroke.keyCode, flags: stroke.flags, text: produced, layoutID: layout.id))
            text += produced
        }
        return RenderedWord(strokes: newStrokes, text: text)
    }

    /// Таблица «символ → символ» между двумя раскладками (нужна для выделенного текста,
    /// где исходных keyCode у нас уже нет). Строится один раз и кэшируется.
    func characterMap(from: KeyboardLayout, to target: KeyboardLayout) -> [Character: Character] {
        let key = "\(from.id)|\(target.id)"
        if let cached = characterMapCache[key] { return cached }
        var map: [Character: Character] = [:]
        guard let src = from.layoutData, let dst = target.layoutData else { return map }
        let modifierSets: [CGEventFlags] = [[], .maskShift, .maskAlternate, [.maskAlternate, .maskShift]]
        for keyCode in UInt16(0)...UInt16(127) {
            for flags in modifierSets {
                guard let a = KeyTranslator.string(keyCode: keyCode, flags: flags, layoutData: src),
                      let b = KeyTranslator.string(keyCode: keyCode, flags: flags, layoutData: dst),
                      a.count == 1, b.count == 1,
                      let ac = a.first, let bc = b.first,
                      ac.unicodeScalars.first!.value >= 0x20, bc.unicodeScalars.first!.value >= 0x20 else { continue }
                if map[ac] == nil { map[ac] = bc }
            }
        }
        characterMapCache[key] = map
        return map
    }

    private var characterMapCache: [String: [Character: Character]] = [:]

    func convert(text: String, from: KeyboardLayout, to target: KeyboardLayout) -> String {
        let map = characterMap(from: from, to: target)
        return String(text.map { map[$0] ?? $0 })
    }

    /// Насколько текст «похож» на набранный в данной раскладке (доля символов из её алфавита).
    func coverage(of text: String, by layout: KeyboardLayout) -> Double {
        guard let data = layout.layoutData else { return 0 }
        let key = layout.id
        let alphabet: Set<Character>
        if let cached = alphabetCache[key] {
            alphabet = cached
        } else {
            var set: Set<Character> = []
            for keyCode in UInt16(0)...UInt16(127) {
                for flags in [CGEventFlags(), .maskShift] {
                    if let s = KeyTranslator.string(keyCode: keyCode, flags: flags, layoutData: data),
                       s.count == 1, let c = s.first, c.isLetter {
                        set.insert(c)
                        // Обе формы кладём сразу: строить Character из результата
                        // lowercased() нельзя — у части букв он даёт не один символ.
                        set.formUnion(c.lowercased())
                        set.formUnion(c.uppercased())
                    }
                }
            }
            alphabetCache[key] = set
            alphabet = set
        }
        let letters = text.filter { $0.isLetter }
        guard !letters.isEmpty else { return 0 }
        let hits = letters.filter { alphabet.contains($0) }.count
        return Double(hits) / Double(letters.count)
    }

    private var alphabetCache: [String: Set<Character>] = [:]

    // MARK: - Чтение свойств TISInputSource

    private func makeLayout(_ source: TISInputSource) -> KeyboardLayout? {
        guard let id = stringProperty(source, kTISPropertyInputSourceID) else { return nil }
        let name = stringProperty(source, kTISPropertyLocalizedName) ?? id
        var languages: [String] = []
        if let ptr = TISGetInputSourceProperty(source, kTISPropertyInputSourceLanguages) {
            let array = Unmanaged<CFArray>.fromOpaque(ptr).takeUnretainedValue()
            for i in 0..<CFArrayGetCount(array) {
                if let value = CFArrayGetValueAtIndex(array, i) {
                    languages.append(Unmanaged<CFString>.fromOpaque(value).takeUnretainedValue() as String)
                }
            }
        }
        var data: Data?
        if let ptr = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) {
            data = Unmanaged<CFData>.fromOpaque(ptr).takeUnretainedValue() as Data
        }
        return KeyboardLayout(id: id, name: name, languages: languages, layoutData: data, source: source)
    }

    private func stringProperty(_ source: TISInputSource, _ key: CFString) -> String? {
        guard let ptr = TISGetInputSourceProperty(source, key) else { return nil }
        return (Unmanaged<CFString>.fromOpaque(ptr).takeUnretainedValue() as String)
    }

    private func boolProperty(_ source: TISInputSource, _ key: CFString) -> Bool {
        guard let ptr = TISGetInputSourceProperty(source, key) else { return false }
        return CFBooleanGetValue(Unmanaged<CFBoolean>.fromOpaque(ptr).takeUnretainedValue())
    }
}
