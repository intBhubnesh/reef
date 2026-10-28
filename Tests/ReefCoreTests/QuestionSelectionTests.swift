import XCTest
@testable import ReefCore

final class QuestionSelectionTests: XCTestCase {
    let questions = [
        Question(question: "Which framework?", header: "Framework",
                 options: [.init(label: "React", description: ""), .init(label: "Vue", description: ""), .init(label: "Svelte", description: "")],
                 multiSelect: false),
        Question(question: "Which features?", header: "Features",
                 options: [.init(label: "Auth", description: ""), .init(label: "Billing", description: "")],
                 multiSelect: true),
    ]

    func testSingleSelectReplaces() {
        var s = QuestionSelection(questions: questions)
        s.toggle(question: "Which framework?", label: "React", multiSelect: false)
        s.toggle(question: "Which framework?", label: "Vue", multiSelect: false)
        XCTAssertEqual(s.chosen["Which framework?"], ["Vue"])
    }

    func testMultiSelectToggles() {
        var s = QuestionSelection(questions: questions)
        s.toggle(question: "Which features?", label: "Auth", multiSelect: true)
        s.toggle(question: "Which features?", label: "Billing", multiSelect: true)
        XCTAssertEqual(s.chosen["Which features?"], ["Auth", "Billing"])
        s.toggle(question: "Which features?", label: "Auth", multiSelect: true)
        XCTAssertEqual(s.chosen["Which features?"], ["Billing"])
    }

    func testCanSubmitRequiresEveryQuestion() {
        var s = QuestionSelection(questions: questions)
        XCTAssertFalse(s.canSubmit)
        s.toggle(question: "Which framework?", label: "React", multiSelect: false)
        XCTAssertFalse(s.canSubmit)
        s.toggle(question: "Which features?", label: "Billing", multiSelect: true)
        XCTAssertTrue(s.canSubmit)
        s.toggle(question: "Which features?", label: "Billing", multiSelect: true)
        XCTAssertFalse(s.canSubmit, "zero options chosen on a multi-select disables submit")
    }

    func testAnswersOrderIsStable() {
        var s = QuestionSelection(questions: questions)
        s.toggle(question: "Which features?", label: "Billing", multiSelect: true)
        s.toggle(question: "Which features?", label: "Auth", multiSelect: true)
        s.toggle(question: "Which framework?", label: "Svelte", multiSelect: false)
        XCTAssertEqual(s.answers()["Which features?"], ["Auth", "Billing"], "option order, not click order")
        XCTAssertEqual(s.answers()["Which framework?"], ["Svelte"])
    }

    func testCustomAnswerCountsAsLabel() {
        var s = QuestionSelection(questions: questions)
        s.setCustom(question: "Which framework?", text: "  Solid  ")
        s.toggle(question: "Which features?", label: "Auth", multiSelect: true)
        XCTAssertTrue(s.canSubmit)
        XCTAssertEqual(s.answers()["Which framework?"], ["Solid"])
        s.setCustom(question: "Which framework?", text: "")
        XCTAssertFalse(s.canSubmit)
    }
}
