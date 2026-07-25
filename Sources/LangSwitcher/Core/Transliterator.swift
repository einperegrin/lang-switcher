import Foundation

/// Транслитерация кириллица ↔ латиница (как «Транслит» в Punto Switcher).
enum Transliterator {

    private static let cyrillicToLatin: [Character: String] = [
        "а": "a", "б": "b", "в": "v", "г": "g", "д": "d", "е": "e", "ё": "yo", "ж": "zh",
        "з": "z", "и": "i", "й": "y", "к": "k", "л": "l", "м": "m", "н": "n", "о": "o",
        "п": "p", "р": "r", "с": "s", "т": "t", "у": "u", "ф": "f", "х": "kh", "ц": "ts",
        "ч": "ch", "ш": "sh", "щ": "sch", "ъ": "", "ы": "y", "ь": "", "э": "e", "ю": "yu", "я": "ya"
    ]

    /// Порядок важен: диграфы разбираем раньше одиночных букв.
    private static let latinToCyrillic: [(String, String)] = [
        ("sch", "щ"), ("shch", "щ"), ("zh", "ж"), ("ch", "ч"), ("sh", "ш"), ("kh", "х"),
        ("ts", "ц"), ("yo", "ё"), ("yu", "ю"), ("ya", "я"), ("ye", "е"), ("jo", "ё"),
        ("ju", "ю"), ("ja", "я"),
        ("a", "а"), ("b", "б"), ("v", "в"), ("g", "г"), ("d", "д"), ("e", "е"), ("z", "з"),
        ("i", "и"), ("j", "й"), ("k", "к"), ("l", "л"), ("m", "м"), ("n", "н"), ("o", "о"),
        ("p", "п"), ("r", "р"), ("s", "с"), ("t", "т"), ("u", "у"), ("f", "ф"), ("h", "х"),
        ("c", "ц"), ("y", "ы"), ("w", "в"), ("x", "кс"), ("q", "к"), ("'", "ь")
    ]

    static func transliterate(_ text: String) -> String {
        let cyrillic = text.unicodeScalars.filter { CharacterSet.letters.contains($0) }
            .filter { ($0.value >= 0x0400 && $0.value <= 0x04FF) }.count
        let latin = text.unicodeScalars.filter { CharacterSet.letters.contains($0) }
            .filter { $0.value < 0x0250 }.count
        return cyrillic >= latin ? toLatin(text) : toCyrillic(text)
    }

    static func toLatin(_ text: String) -> String {
        var result = ""
        for character in text {
            let lower = Character(character.lowercased())
            if let mapped = cyrillicToLatin[lower] {
                result += character.isUppercase ? capitalizeFirst(mapped) : mapped
            } else {
                result.append(character)
            }
        }
        return result
    }

    static func toCyrillic(_ text: String) -> String {
        var result = ""
        var index = text.startIndex
        outer: while index < text.endIndex {
            for (latin, cyrillic) in latinToCyrillic {
                let end = text.index(index, offsetBy: latin.count, limitedBy: text.endIndex) ?? text.endIndex
                guard end > index else { continue }
                let slice = text[index..<end]
                if slice.lowercased() == latin {
                    let isUpper = slice.first!.isUppercase
                    result += isUpper ? capitalizeFirst(cyrillic) : cyrillic
                    index = end
                    continue outer
                }
            }
            result.append(text[index])
            index = text.index(after: index)
        }
        return result
    }

    private static func capitalizeFirst(_ s: String) -> String {
        guard let first = s.first else { return s }
        return first.uppercased() + s.dropFirst()
    }
}

enum CaseCycler {
    /// нижний → ВЕРХНИЙ → Заглавные Буквы → нижний
    static func cycle(_ text: String) -> String {
        let letters = text.filter { $0.isLetter }
        guard !letters.isEmpty else { return text }
        if text == text.lowercased() { return text.uppercased() }
        if text == text.uppercased() { return titlecase(text) }
        return text.lowercased()
    }

    private static func titlecase(_ text: String) -> String {
        var result = ""
        var atWordStart = true
        for character in text {
            if character.isLetter {
                result += atWordStart ? character.uppercased() : character.lowercased()
                atWordStart = false
            } else {
                result.append(character)
                atWordStart = true
            }
        }
        return result
    }
}
