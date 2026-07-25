import AppKit
import Carbon.HIToolbox

/// Обёртка над UCKeyTranslate: «какой символ даст эта физическая клавиша в этой раскладке».
/// Ключевая деталь всего приложения — конвертация делается не по таблице символов,
/// а повторным переводом исходных keyCode через данные другой раскладки.
enum KeyTranslator {

    static func string(keyCode: UInt16, flags: CGEventFlags, layoutData: Data) -> String? {
        var deadKeyState: UInt32 = 0
        var chars = [UniChar](repeating: 0, count: 8)
        var length = 0
        let modifierKeyState = UInt32((carbonModifiers(flags) >> 8) & 0xFF)
        let kbdType = UInt32(LMGetKbdType())

        let status: OSStatus = layoutData.withUnsafeBytes { raw in
            guard let base = raw.baseAddress else { return OSStatus(paramErr) }
            let layout = base.assumingMemoryBound(to: UCKeyboardLayout.self)
            return UCKeyTranslate(layout,
                                  keyCode,
                                  UInt16(kUCKeyActionDown),
                                  modifierKeyState,
                                  kbdType,
                                  OptionBits(kUCKeyTranslateNoDeadKeysMask),
                                  &deadKeyState,
                                  chars.count,
                                  &length,
                                  &chars)
        }
        guard status == noErr, length > 0 else { return nil }
        return String(utf16CodeUnits: chars, count: length)
    }

    /// CGEventFlags -> классические карбоновские модификаторы (их ждёт UCKeyTranslate).
    static func carbonModifiers(_ flags: CGEventFlags) -> UInt32 {
        var result: UInt32 = 0
        if flags.contains(.maskShift) { result |= UInt32(shiftKey) }
        if flags.contains(.maskAlphaShift) { result |= UInt32(alphaLock) }
        if flags.contains(.maskAlternate) { result |= UInt32(optionKey) }
        if flags.contains(.maskControl) { result |= UInt32(controlKey) }
        if flags.contains(.maskCommand) { result |= UInt32(cmdKey) }
        return result
    }

    /// Читаемое имя клавиши для интерфейса настроек.
    static func displayName(for keyCode: UInt16) -> String {
        if let special = specialNames[keyCode] { return special }
        if let data = asciiLayoutData,
           let s = string(keyCode: keyCode, flags: [], layoutData: data),
           !s.isEmpty, s.first!.isLetter || s.first!.isNumber || s.first!.isPunctuation || s.first!.isSymbol {
            return s.uppercased()
        }
        return "#\(keyCode)"
    }

    private static var asciiLayoutData: Data? {
        guard let source = TISCopyCurrentASCIICapableKeyboardLayoutInputSource()?.takeRetainedValue(),
              let ptr = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else { return nil }
        return Unmanaged<CFData>.fromOpaque(ptr).takeUnretainedValue() as Data
    }

    private static let specialNames: [UInt16: String] = [
        36: "↩", 48: "⇥", 49: "Space", 51: "⌫", 53: "⎋", 76: "⌤", 117: "⌦",
        123: "←", 124: "→", 125: "↓", 126: "↑",
        122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6",
        98: "F7", 100: "F8", 101: "F9", 109: "F10", 103: "F11", 111: "F12",
        115: "Home", 119: "End", 116: "PgUp", 121: "PgDn"
    ]

    /// Клавиши, после которых буфер набранного слова теряет смысл.
    static let resetKeyCodes: Set<UInt16> = [
        36, 48, 53, 76, 71, 114, 115, 116, 117, 119, 121,
        123, 124, 125, 126,
        122, 120, 99, 118, 96, 97, 98, 100, 101, 109, 103, 111
    ]
}
