import Foundation

/// What the user has picked so far for an `AskUserQuestion` card.
public struct QuestionSelection: Equatable {
    public private(set) var chosen: [String: [String]] = [:]
    private var custom: [String: String] = [:]
    private let questions: [Question]

    public init(questions: [Question]) {
        self.questions = questions
    }

    public mutating func toggle(question: String, label: String, multiSelect: Bool) {
        var labels = chosen[question] ?? []
        if multiSelect {
            if let index = labels.firstIndex(of: label) { labels.remove(at: index) } else { labels.append(label) }
        } else {
            labels = labels == [label] ? [] : [label]
        }
        chosen[question] = labels
    }

    /// A free-text answer; whitespace-only clears it.
    public mutating func setCustom(question: String, text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        custom[question] = trimmed.isEmpty ? nil : trimmed
    }

    public func customText(question: String) -> String { custom[question] ?? "" }

    public func isChosen(question: String, label: String) -> Bool {
        chosen[question]?.contains(label) ?? false
    }

    /// Every question has at least one option or a custom answer.
    public var canSubmit: Bool {
        !questions.isEmpty && questions.allSatisfy { !(chosen[$0.question] ?? []).isEmpty || custom[$0.question] != nil }
    }

    /// Labels in the question's option order, then the custom answer.
    public func answers() -> [String: [String]] {
        var out: [String: [String]] = [:]
        for q in questions {
            let picked = q.options.map(\.label).filter { chosen[q.question]?.contains($0) ?? false }
            let all = picked + (custom[q.question].map { [$0] } ?? [])
            if !all.isEmpty { out[q.question] = all }
        }
        return out
    }
}
