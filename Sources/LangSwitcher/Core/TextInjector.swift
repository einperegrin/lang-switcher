import AppKit

/// Печать «за пользователя». Каждое отправленное событие помечается magic-значением,
/// чтобы наш собственный event tap не принял его за ввод человека и не зациклился.
enum TextInjector {
    static let magic: Int64 = 0x4C53_5749 // 'LSWI'

    /// Приватный источник не смешивается с реальным состоянием модификаторов:
    /// это важно, потому что коррекцию по двойному Shift мы делаем при зажатом Shift.
    private static let source = CGEventSource(stateID: .privateState)

    private static func stamp(_ event: CGEvent) {
        event.setIntegerValueField(.eventSourceUserData, value: magic)
    }

    /// Действие вызвано зажатым модификатором (двойной Shift, ⌃⌥L), а часть приложений
    /// сверяется с глобальным состоянием клавиатуры, а не с флагами события.
    /// Поэтому ждём отпускания — но не дольше, чем терпимо для отзывчивости.
    static func waitForModifiersRelease(timeout: TimeInterval = 0.4) {
        let watched: CGEventFlags = [.maskCommand, .maskAlternate, .maskControl, .maskShift]
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            let state = CGEventSource.flagsState(.combinedSessionState)
            if state.intersection(watched).isEmpty { return }
            usleep(10_000)
        }
    }

    static func backspace(_ count: Int) {
        guard count > 0 else { return }
        for _ in 0..<count {
            keyStroke(virtualKey: 51, flags: [])
        }
    }

    static func keyStroke(virtualKey: CGKeyCode, flags: CGEventFlags) {
        guard let down = CGEvent(keyboardEventSource: source, virtualKey: virtualKey, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: virtualKey, keyDown: false) else { return }
        down.flags = flags
        up.flags = flags
        stamp(down)
        stamp(up)
        down.post(tap: .cghidEventTap)
        usleep(900)
        up.post(tap: .cghidEventTap)
        usleep(900)
    }

    /// Текст вставляется посимвольно через unicode-строку: так результат не зависит
    /// от активной раскладки и не требует поиска keyCode для каждого символа.
    static func type(_ text: String) {
        for character in text {
            let utf16 = Array(String(character).utf16)
            guard let down = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true),
                  let up = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false) else { continue }
            down.flags = []
            up.flags = []
            down.keyboardSetUnicodeString(stringLength: utf16.count, unicodeString: utf16)
            up.keyboardSetUnicodeString(stringLength: utf16.count, unicodeString: utf16)
            stamp(down)
            stamp(up)
            down.post(tap: .cghidEventTap)
            usleep(700)
            up.post(tap: .cghidEventTap)
            usleep(700)
        }
    }
}
