import AppKit

struct LayoutDecision {
    let layout: KeyboardLayout
    let text: String
}

/// Решает, набрано ли слово не в той раскладке.
///
/// Логика намеренно консервативная: сначала словарь (сильный сигнал), и только если
/// оба варианта словарю неизвестны — эвристика по биграммам с большим запасом уверенности.
/// Ложное переключение раздражает сильнее, чем пропущенное.
final class LayoutDetector {
    static let shared = LayoutDetector()
    private init() {}

    private let heuristicMinScore = 0.62
    private let heuristicMaxCurrentScore = 0.45
    private let heuristicMinMargin = 0.25

    func decideTarget(word: [KeyStroke], current: KeyboardLayout) -> LayoutDecision? {
        let originalText = word.map(\.text).joined()
        guard originalText.contains(where: { $0.isLetter }) else { return nil }

        let currentLanguage = current.primaryLanguage
        let currentValid = LanguageModel.isSpelledCorrectly(originalText, languageCode: currentLanguage)
        if currentValid == true { return nil }
        let currentScore = LanguageModel.score(originalText, languageCode: currentLanguage) ?? 0.5

        guard let best = bestCandidate(word: word, excluding: current) else { return nil }

        if best.valid == true { return LayoutDecision(layout: best.layout, text: best.text) }

        if best.score >= heuristicMinScore,
           currentScore <= heuristicMaxCurrentScore,
           best.score - currentScore >= heuristicMinMargin {
            return LayoutDecision(layout: best.layout, text: best.text)
        }
        return nil
    }

    /// Принудительный выбор цели (для горячих клавиш — там пользователь уже решил за нас).
    func bestTarget(word: [KeyStroke], excluding current: KeyboardLayout) -> LayoutDecision? {
        guard let best = bestCandidate(word: word, excluding: current) else { return nil }
        return LayoutDecision(layout: best.layout, text: best.text)
    }

    /// То же самое, но для произвольного текста (выделение), где keyCode уже недоступны.
    func bestTargetForText(_ text: String, current: KeyboardLayout) -> LayoutDecision? {
        let layouts = LayoutManager.shared.convertibleLayouts
        guard layouts.count > 1 else { return nil }
        // Раскладка-источник — та, чей алфавит лучше покрывает текст.
        let source = layouts.max { LayoutManager.shared.coverage(of: text, by: $0) < LayoutManager.shared.coverage(of: text, by: $1) } ?? current
        var best: (layout: KeyboardLayout, text: String, rank: Double)?
        for candidate in layouts where candidate.id != source.id {
            let converted = LayoutManager.shared.convert(text: text, from: source, to: candidate)
            let rank = textRank(converted, languageCode: candidate.primaryLanguage)
            if best == nil || rank > best!.rank { best = (candidate, converted, rank) }
        }
        guard let winner = best else { return nil }
        return LayoutDecision(layout: winner.layout, text: winner.text)
    }

    // MARK: - Внутреннее

    private struct Candidate {
        let layout: KeyboardLayout
        let text: String
        let score: Double
        let valid: Bool?
    }

    private func bestCandidate(word: [KeyStroke], excluding current: KeyboardLayout) -> Candidate? {
        var best: Candidate?
        for layout in LayoutManager.shared.convertibleLayouts where layout.id != current.id {
            guard let rendered = LayoutManager.shared.render(word, in: layout) else { continue }
            let language = layout.primaryLanguage
            let valid = LanguageModel.isSpelledCorrectly(rendered.text, languageCode: language)
            let score = LanguageModel.score(rendered.text, languageCode: language) ?? 0.5
            let candidate = Candidate(layout: layout, text: rendered.text, score: score, valid: valid)
            if best == nil || rank(candidate) > rank(best!) { best = candidate }
        }
        return best
    }

    private func rank(_ c: Candidate) -> Double { (c.valid == true ? 10 : 0) + c.score }

    /// Оценка целого куска текста: доля слов, похожих на язык.
    private func textRank(_ text: String, languageCode: String) -> Double {
        let words = text.split { !$0.isLetter && $0 != "'" }.map(String.init).filter { $0.count > 1 }
        guard !words.isEmpty else { return 0 }
        var total = 0.0
        for word in words.prefix(40) {
            if LanguageModel.isSpelledCorrectly(word, languageCode: languageCode) == true {
                total += 1.5
            } else {
                total += LanguageModel.score(word, languageCode: languageCode) ?? 0.5
            }
        }
        return total / Double(min(words.count, 40))
    }
}
