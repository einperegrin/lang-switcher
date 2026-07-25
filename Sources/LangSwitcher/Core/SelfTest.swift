import AppKit

/// Проверка ядра без интерфейса: `LangSwitcher --selftest`.
/// Синтезирует настоящие keyCode из установленных в системе раскладок,
/// поэтому прогоняется весь путь: клавиша → символ → решение детектора.
enum SelfTest {

    static func run() -> Int32 {
        LayoutManager.shared.reload()
        let layouts = LayoutManager.shared.convertibleLayouts
        print("Раскладки в системе:")
        for layout in layouts {
            print("  • \(layout.name)  [\(layout.primaryLanguage)]  \(layout.id)")
        }

        guard let ru = layouts.first(where: { $0.primaryLanguage == "ru" }),
              let en = layouts.first(where: { $0.primaryLanguage == "en" }) else {
            print("\n⚠️  Нужны включённые русская и английская раскладки — тест пропущен.")
            return 0
        }

        print("\nСловари орфографии: ru=\(LanguageModel.isSpelledCorrectly("привет", languageCode: "ru").map(String.init(describing:)) ?? "нет") " +
              "en=\(LanguageModel.isSpelledCorrectly("hello", languageCode: "en").map(String.init(describing:)) ?? "нет")")

        var failures = 0

        // Слова, набранные не в той раскладке → должны исправляться.
        let shouldSwitch: [(String, KeyboardLayout, KeyboardLayout, String)] = [
            ("ghbdtn", en, ru, "привет"),
            ("cjj,otybt", en, ru, "сообщение"),
            ("hfcrkflrf", en, ru, "раскладка"),
            ("gjxnf", en, ru, "почта"),
            ("ntrcn", en, ru, "текст"),
            ("руддщ", ru, en, "hello"),
            ("цшслув", ru, en, "wicked"),
            ("зкщоусе", ru, en, "project"),
            ("ыефке", ru, en, "start")
        ]
        print("\nДолжно переключать:")
        for (typed, from, to, expected) in shouldSwitch {
            guard let strokes = synthesize(typed, in: from) else {
                print("  ?  \(typed) — не удалось собрать нажатия"); failures += 1; continue
            }
            let decision = LayoutDetector.shared.decideTarget(word: strokes, current: from)
            let ok = decision?.layout.id == to.id && decision?.text.lowercased() == expected
            print("  \(ok ? "✓" : "✗")  \(typed) → \(decision?.text ?? "—") (ждали \(expected))")
            if !ok { failures += 1 }
        }

        // Нормальный текст → трогать нельзя.
        let shouldStay: [(String, KeyboardLayout)] = [
            ("привет", ru), ("раскладка", ru), ("сообщение", ru), ("который", ru), ("данные", ru),
            ("работает", ru), ("функция", ru), ("почта", ru), ("текст", ru), ("файл", ru),
            ("hello", en), ("project", en), ("switcher", en), ("npm", en), ("git", en),
            ("github", en), ("swift", en), ("xcode", en), ("макос", ru), ("апи", ru),
            ("ssh", en), ("curl", en), ("brew", en), ("sudo", en), ("docker", en), ("kubectl", en)
        ]
        print("\nНе должно трогать:")
        for (typed, layout) in shouldStay {
            guard let strokes = synthesize(typed, in: layout) else {
                print("  ?  \(typed) — не удалось собрать нажатия"); failures += 1; continue
            }
            let decision = LayoutDetector.shared.decideTarget(word: strokes, current: layout)
            let ok = decision == nil
            print("  \(ok ? "✓" : "✗")  \(typed)\(ok ? "" : " → предложено «\(decision!.text)»")")
            if !ok { failures += 1 }
        }

        // Двойное нажатие модификатора. Тест закрывает баг с единицами времени:
        // CGEvent.timestamp считался наносекундами, а содержал тики 24 МГц.
        print("\nДвойное нажатие правого Shift:")
        let press = CGEventFlags(rawValue: 0x0000_0004).union(.maskShift)
        let release = CGEventFlags(rawValue: 0)
        let doubleTapCases: [(String, Bool)] = [
            ("быстрое двойное (0.2 с)", {
                let d = DoubleTapDetector()
                _ = d.handle(keyCode: 60, flags: press, timestamp: 10.0)
                _ = d.handle(keyCode: 60, flags: release, timestamp: 10.1)
                return d.handle(keyCode: 60, flags: press, timestamp: 10.2)
            }()),
            ("медленное двойное (1.5 с) — не должно", {
                let d = DoubleTapDetector()
                _ = d.handle(keyCode: 60, flags: press, timestamp: 10.0)
                return d.handle(keyCode: 60, flags: press, timestamp: 11.5)
            }() == false),
            ("набор заглавной между тапами — не должно", {
                let d = DoubleTapDetector()
                _ = d.handle(keyCode: 60, flags: press, timestamp: 10.0)
                d.noteOtherInput()
                return d.handle(keyCode: 60, flags: press, timestamp: 10.1)
            }() == false),
            ("левый Shift не срабатывает", {
                let d = DoubleTapDetector()
                _ = d.handle(keyCode: 56, flags: .maskShift, timestamp: 10.0)
                return d.handle(keyCode: 56, flags: .maskShift, timestamp: 10.1)
            }() == false)
        ]
        for (name, ok) in doubleTapCases {
            print("  \(ok ? "✓" : "✗")  \(name)")
            if !ok { failures += 1 }
        }

        // Транслитерация и регистр.
        print("\nПрочее:")
        let checks: [(String, String, String)] = [
            ("транслит ru→lat", Transliterator.toLatin("Щука ёжик"), "Schuka yozhik"),
            ("транслит lat→ru", Transliterator.toCyrillic("privet"), "привет"),
            ("регистр", CaseCycler.cycle("привет мир"), "ПРИВЕТ МИР"),
            ("регистр 2", CaseCycler.cycle("ПРИВЕТ МИР"), "Привет Мир")
        ]
        for (name, got, expected) in checks {
            let ok = got == expected
            print("  \(ok ? "✓" : "✗")  \(name): «\(got)»\(ok ? "" : " (ждали «\(expected)»)")")
            if !ok { failures += 1 }
        }

        print(failures == 0 ? "\nВсе проверки пройдены." : "\nПровалено проверок: \(failures)")
        return failures == 0 ? 0 : 1
    }

    /// Обратная задача: подобрать физические клавиши, дающие нужный текст в заданной раскладке.
    private static func synthesize(_ text: String, in layout: KeyboardLayout) -> [KeyStroke]? {
        guard let data = layout.layoutData else { return nil }
        var table: [Character: (UInt16, CGEventFlags)] = [:]
        for keyCode in UInt16(0)...UInt16(127) {
            for flags in [CGEventFlags(), .maskShift] {
                guard let produced = KeyTranslator.string(keyCode: keyCode, flags: flags, layoutData: data),
                      produced.count == 1, let character = produced.first else { continue }
                if table[character] == nil { table[character] = (keyCode, flags) }
            }
        }
        var strokes: [KeyStroke] = []
        for character in text {
            guard let (keyCode, flags) = table[character] else { return nil }
            strokes.append(KeyStroke(keyCode: keyCode, flags: flags, text: String(character), layoutID: layout.id))
        }
        return strokes
    }
}
