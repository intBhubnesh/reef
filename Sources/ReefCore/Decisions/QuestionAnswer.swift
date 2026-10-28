import Foundation

public struct Question: Equatable {
    public struct Option: Equatable {
        public let label: String
        public let description: String
        public init(label: String, description: String) { self.label = label; self.description = description }
    }

    public let question: String
    public let header: String
    public let options: [Option]
    public let multiSelect: Bool

    public init(question: String, header: String, options: [Option], multiSelect: Bool) {
        self.question = question; self.header = header; self.options = options; self.multiSelect = multiSelect
    }
}

/// Claude Code `AskUserQuestion`: parse the questions and build the `updatedInput` that answers them.
public enum QuestionAnswer {
    public static func parse(toolInput: [String: Any]) -> [Question] {
        guard let items = toolInput["questions"] as? [[String: Any]] else { return [] }
        return items.compactMap { item in
            guard let question = item["question"] as? String else { return nil }
            let options = (item["options"] as? [[String: Any]] ?? []).compactMap { opt -> Question.Option? in
                guard let label = opt["label"] as? String else { return nil }
                return Question.Option(label: label, description: opt["description"] as? String ?? "")
            }
            return Question(question: question, header: item["header"] as? String ?? "",
                            options: options, multiSelect: item["multiSelect"] as? Bool ?? false)
        }
    }

    /// Original input plus `answers: {question: "label, label"}`.
    public static func updatedInput(original toolInput: [String: Any], answers: [String: [String]]) -> [String: Any] {
        var out = toolInput
        out["answers"] = answers.mapValues { $0.joined(separator: ", ") }
        return out
    }
}

/// Claude Code `ExitPlanMode`: an allow must echo the injected plan fields.
public enum PlanAnswer {
    public static func updatedInput(original toolInput: [String: Any]) -> [String: Any] {
        var out: [String: Any] = [:]
        if let plan = toolInput["plan"] { out["plan"] = plan }
        if let path = toolInput["planFilePath"] { out["planFilePath"] = path }
        return out
    }
}
