import AppKit

/// Фонотактическая модель языка. Вместо тяжёлых частотных таблиц описываем правила:
/// «согласная+гласная» валидна почти всегда, а вот скопления согласных — только из списка.
/// Этого достаточно, чтобы отличить «ghbdtn» от «привет» без словаря.
struct LanguageProfile {
    let code: String
    let vowels: Set<Character>
    let consonants: Set<Character>
    let signs: Set<Character>        // ь, ъ
    let semivowels: Set<Character>   // й
    let clusters: Set<String>        // допустимые пары согласных
    let vowelPairs: Set<String>
    let badPairs: Set<String>

    static let neutral: Set<Character> = ["'", "\u{2019}", "-"]

    enum CharClass { case vowel, consonant, sign, semivowel, neutral, unknown }

    func classify(_ c: Character) -> CharClass {
        if vowels.contains(c) { return .vowel }
        if semivowels.contains(c) { return .semivowel }
        if consonants.contains(c) { return .consonant }
        if signs.contains(c) { return .sign }
        // Пунктуация и цифры внутри слова ни о чём не говорят — в отличие от буквы
        // чужого алфавита, которая является сильным доводом против этого языка.
        if !c.isLetter { return .neutral }
        return .unknown
    }

    func score(pair: String) -> Double {
        if badPairs.contains(pair) { return 0.02 }
        let chars = Array(pair)
        let a = classify(chars[0]), b = classify(chars[1])
        if a == .unknown || b == .unknown { return 0.0 }
        if a == .neutral || b == .neutral { return 0.6 }

        switch (a, b) {
        case (.vowel, .consonant), (.consonant, .vowel): return 0.95
        case (.vowel, .semivowel), (.semivowel, .consonant): return 0.92
        case (.semivowel, .vowel): return 0.7
        case (.consonant, .semivowel), (.semivowel, .semivowel): return 0.05
        case (.consonant, .consonant): return clusters.contains(pair) ? 0.9 : 0.12
        case (.vowel, .vowel): return vowelPairs.contains(pair) ? 0.85 : 0.15
        case (.consonant, .sign), (.semivowel, .sign): return 0.9
        case (.vowel, .sign): return 0.03
        case (.sign, .vowel): return softVowels.contains(chars[1]) ? 0.9 : 0.05
        case (.sign, .consonant): return 0.75
        case (.sign, .sign): return 0.02
        case (.sign, .semivowel): return 0.1
        default: return 0.3
        }
    }

    private var softVowels: Set<Character> { ["я", "е", "ю", "ё", "и", "о"] }

    // MARK: - Готовые профили

    static let russian = LanguageProfile(
        code: "ru",
        vowels: Set("аеёиоуыэюя"),
        consonants: Set("бвгджзклмнпрстфхцчшщ"),
        signs: Set("ьъ"),
        semivowels: Set("й"),
        clusters: Set("""
        ст сп сн см сл ск св ср сх сц сч сш сф зд зв зл зм зг зб зр зн жд жн жм жг жб \
        шк шт шп шн шл шв шм тр тв тк тм тн тл тс тц тч тщ пр пл пт пс пн кр кл кв кт кс кн \
        гр гл гн гд гв др дв дн дл дм дс дц дж бр бл бн бщ вр вл вн вс вт вз вш вч вд вм вб \
        фр фл фт фс хр хл хв хн мн мб мп мс мч нт нд нн нс нз нг нк нц нч нш нф нх нр нм \
        рт рд рн рм рг рк рс рв рб рп рж рз рх рч рш рщ рл рф рц лн лк лг лд лт лс лз лб лп \
        лм лв лж лч лш лл цк цв чт чк чн чв щн сс тт мм жж дд кк пп бб вв зз рр гг нн \
        дк тк бк вк жк зк пк мк гк хк дт бт вт зт жт гт нб нв нг нж
        """.split(separator: " ").map(String.init)),
        vowelPairs: Set("""
        аи ае ау ао ая аю еа ео еи ея ею ие ии ио иа ию ия оа ое ои оо оу оя уе уи уа ую уо \
        ыи ые эа эо эи юа юи яе яи аэ уэ
        """.split(separator: " ").map(String.init)),
        badPairs: Set("""
        жы шы чы щы жя шя чя щя жэ шэ чэ щэ кы гы хы йы ъы ьы ыъ аъ еъ иъ оъ уъ
        """.split(separator: " ").map(String.init))
    )

    static let english = LanguageProfile(
        code: "en",
        vowels: Set("aeiouy"),
        consonants: Set("bcdfghjklmnpqrstvwxz"),
        signs: [],
        semivowels: [],
        clusters: Set("""
        th ch sh ph wh gh ck ng nk nd nt ns nc nf nv nj nm mp mb mn ms ct cl cr cs pl pr ps pt \
        bl br bs bt fl fr ft fs gl gr gn gs kn kl ks wr dr dw ds tr tw ts sc sk sl sm sn sp st \
        sw sq sf lt ld lk lm lp ls lv lf lb ll lc rt rd rn rm rl rk rs rv rb rp rc rg rf rw \
        ss tt ff pp mm nn dd gg bb cc rr zz dg xt xp xc ht bs gs ws hm vs zl
        """.split(separator: " ").map(String.init)),
        vowelPairs: Set("""
        aa ae ai ao au ay ea ee ei eo eu ey ia ie io iu oa oe oi oo ou oy ua ue ui uo uy \
        ya ye yo yu ay oy iy
        """.split(separator: " ").map(String.init)),
        badPairs: []
    )

    static func profile(for code: String) -> LanguageProfile? {
        switch code.lowercased() {
        case "ru", "be", "bg": return russian
        case "en": return english
        default: return nil
        }
    }
}

enum LanguageModel {

    /// Средняя «правдоподобность» биграмм слова: 1.0 — идеально похоже на язык, 0 — мусор.
    static func score(_ word: String, languageCode: String) -> Double? {
        guard let profile = LanguageProfile.profile(for: languageCode) else { return nil }
        let clean = word.lowercased()
        let chars = Array(clean)
        guard chars.count >= 2 else { return chars.count == 1 ? (profile.classify(chars[0]) == .unknown ? 0 : 0.5) : nil }
        var total = 0.0
        for i in 0..<(chars.count - 1) {
            total += profile.score(pair: String(chars[i...(i + 1)]))
        }
        return (total / Double(chars.count - 1)) * vowelBalance(chars, profile: profile)
    }

    /// Биграммы — признак локальный, поэтому «hfcrkflrf» набирает приличный балл:
    /// пары cr/rk/fl по отдельности английские. Спасает глобальная проверка —
    /// в настоящем слове гласные составляют примерно от 12% до 85% букв.
    private static func vowelBalance(_ chars: [Character], profile: LanguageProfile) -> Double {
        // Считаем долю среди букв: знаки препинания внутри слова баланс не искажают.
        let letters = chars.filter { $0.isLetter }
        guard letters.count >= 4 else { return 1.0 }
        let vowels = letters.filter { profile.classify($0) == .vowel }.count
        let ratio = Double(vowels) / Double(letters.count)
        return (ratio < 0.12 || ratio > 0.85) ? 0.35 : 1.0
    }

    // MARK: - Системная проверка орфографии

    private static var resolvedLanguages: [String: String?] = [:]

    private static func spellLanguage(for code: String) -> String? {
        if let cached = resolvedLanguages[code] { return cached }
        let available = NSSpellChecker.shared.availableLanguages
        let match = available.first { $0 == code }
            ?? available.first { $0.hasPrefix(code + "_") || $0.hasPrefix(code + "-") }
        resolvedLanguages[code] = match
        return match
    }

    /// nil — словаря для языка нет, судить не можем.
    static func isSpelledCorrectly(_ word: String, languageCode: String) -> Bool? {
        guard word.count > 1, let language = spellLanguage(for: languageCode) else { return nil }
        let range = NSSpellChecker.shared.checkSpelling(of: word,
                                                       startingAt: 0,
                                                       language: language,
                                                       wrap: false,
                                                       inSpellDocumentWithTag: 0,
                                                       wordCount: nil)
        return range.location == NSNotFound
    }

    /// Первое обращение к службе орфографии подгружает словари и может занять ~секунду —
    /// прогреваем заранее, чтобы не подвесить обработчик event tap (иначе система его отключит).
    static func warmUp() {
        DispatchQueue.global(qos: .utility).async {
            DispatchQueue.main.async {
                _ = isSpelledCorrectly("привет", languageCode: "ru")
                _ = isSpelledCorrectly("hello", languageCode: "en")
            }
        }
    }
}
