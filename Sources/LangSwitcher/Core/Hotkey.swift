import AppKit

struct Hotkey: Codable, Equatable {
    var keyCode: UInt16
    var modifiers: UInt64
    var enabled: Bool

    static let relevantMask: CGEventFlags = [.maskCommand, .maskAlternate, .maskControl, .maskShift]

    static func make(keyCode: UInt16, flags: CGEventFlags, enabled: Bool = true) -> Hotkey {
        Hotkey(keyCode: keyCode, modifiers: flags.intersection(relevantMask).rawValue, enabled: enabled)
    }

    func matches(keyCode: UInt16, flags: CGEventFlags) -> Bool {
        guard enabled, keyCode == self.keyCode else { return false }
        return flags.intersection(Hotkey.relevantMask).rawValue == modifiers
    }

    var display: String {
        var result = ""
        let flags = CGEventFlags(rawValue: modifiers)
        if flags.contains(.maskControl) { result += "⌃" }
        if flags.contains(.maskAlternate) { result += "⌥" }
        if flags.contains(.maskShift) { result += "⇧" }
        if flags.contains(.maskCommand) { result += "⌘" }
        return result + KeyTranslator.displayName(for: keyCode)
    }
}

/// Клавиша-модификатор, двойное нажатие которой служит горячей клавишей.
/// Различаем левую и правую по device-dependent битам в CGEventFlags —
/// keyCode сам по себе их различает, но флаг нужен, чтобы понять «нажатие или отпускание».
enum DoubleTapKey: String, CaseIterable, Codable {
    case rightShift, leftShift, rightCommand, leftCommand, rightOption, rightControl, disabled

    var title: String {
        switch self {
        case .rightShift: return "Двойной правый ⇧ Shift"
        case .leftShift: return "Двойной левый ⇧ Shift"
        case .rightCommand: return "Двойной правый ⌘ Command"
        case .leftCommand: return "Двойной левый ⌘ Command"
        case .rightOption: return "Двойной правый ⌥ Option"
        case .rightControl: return "Двойной правый ⌃ Control"
        case .disabled: return "Отключено"
        }
    }

    var keyCode: UInt16? {
        switch self {
        case .rightShift: return 60
        case .leftShift: return 56
        case .rightCommand: return 54
        case .leftCommand: return 55
        case .rightOption: return 61
        case .rightControl: return 62
        case .disabled: return nil
        }
    }

    /// NX_DEVICE*KEYMASK — младшие биты CGEventFlags, различающие левый/правый модификатор.
    var deviceMask: UInt64 {
        switch self {
        case .rightShift: return 0x0000_0004
        case .leftShift: return 0x0000_0002
        case .rightCommand: return 0x0000_0010
        case .leftCommand: return 0x0000_0008
        case .rightOption: return 0x0000_0040
        case .rightControl: return 0x0000_2000
        case .disabled: return 0
        }
    }
}

/// Детектор двойного нажатия модификатора.
/// Любое нажатие обычной клавиши между двумя тапами сбрасывает счётчик —
/// иначе обычный набор заглавных букв через Shift постоянно давал бы ложные срабатывания.
final class DoubleTapDetector {
    var key: DoubleTapKey = .rightShift
    var interval: TimeInterval = 0.4

    private var lastPress: TimeInterval = 0
    private var armed = false

    func noteOtherInput() {
        armed = false
        lastPress = 0
    }

    func handle(keyCode: UInt16, flags: CGEventFlags, timestamp: TimeInterval) -> Bool {
        guard let target = key.keyCode else { return false }
        guard keyCode == target else {
            noteOtherInput()
            return false
        }
        let pressed = (flags.rawValue & key.deviceMask) != 0
        guard pressed else { return false }

        if armed, timestamp - lastPress <= interval {
            armed = false
            lastPress = 0
            return true
        }
        armed = true
        lastPress = timestamp
        return false
    }
}
