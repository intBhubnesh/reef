import XCTest
@testable import ReefCore

final class DecisionTests: XCTestCase {
    private func json(_ data: Data) -> [String: Any] {
        (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
    }
    private func decision(_ data: Data) -> [String: Any] {
        ((json(data)["hookSpecificOutput"] as? [String: Any])?["decision"] as? [String: Any]) ?? [:]
    }

    func testClaudeAllowPlain() {
        let data = DecisionEncoder.encode(.allow(), for: .claude)
        let out = json(data)["hookSpecificOutput"] as? [String: Any]
        XCTAssertEqual(out?["hookEventName"] as? String, "PermissionRequest")
        XCTAssertEqual((out?["decision"] as? [String: Any])?["behavior"] as? String, "allow")
        XCTAssertEqual((out?["decision"] as? [String: Any])?.count, 1)
    }

    func testClaudeAlwaysAllowEchoesSuggestion() {
        let suggestion: [String: Any] = ["type": "addRules", "behavior": "allow", "destination": "localSettings",
                                         "rules": [["toolName": "Bash", "ruleContent": "npm run:*"]]]
        let always = AlwaysAllow(toolName: "Bash", suggestion: suggestion)
        let d = decision(DecisionEncoder.encode(.allow(alwaysAllow: always), for: .claude))
        let perms = d["updatedPermissions"] as? [[String: Any]]
        XCTAssertEqual(perms?.count, 1)
        XCTAssertTrue(NSDictionary(dictionary: perms?[0] ?? [:]).isEqual(to: suggestion))
    }

    func testClaudeAlwaysAllowWithoutSuggestionBuildsSessionRule() {
        let d = decision(DecisionEncoder.encode(.allow(alwaysAllow: AlwaysAllow(toolName: "Bash", suggestion: nil)), for: .claude))
        let perm = (d["updatedPermissions"] as? [[String: Any]])?.first
        XCTAssertEqual(perm?["type"] as? String, "addRules")
        XCTAssertEqual(perm?["behavior"] as? String, "allow")
        XCTAssertEqual(perm?["destination"] as? String, "session")
        let rules = perm?["rules"] as? [[String: String]]
        XCTAssertEqual(rules, [["toolName": "Bash"]])
    }

    func testCodexIgnoresAlwaysAllow() {
        let d = decision(DecisionEncoder.encode(.allow(alwaysAllow: AlwaysAllow(toolName: "Bash", suggestion: nil)), for: .codex))
        XCTAssertEqual(d["behavior"] as? String, "allow")
        XCTAssertNil(d["updatedPermissions"])
    }

    func testAllowWithUpdatedInput() {
        let d = decision(DecisionEncoder.encode(.allow(updatedInput: ["answers": ["q": "a"]]), for: .claude))
        XCTAssertEqual((d["updatedInput"] as? [String: Any])?["answers"] as? [String: String], ["q": "a"])
    }

    func testDenyCarriesMessage() {
        let d = decision(DecisionEncoder.encode(.deny(message: "Denied from Reef"), for: .claude))
        XCTAssertEqual(d["behavior"] as? String, "deny")
        XCTAssertEqual(d["message"] as? String, "Denied from Reef")
    }

    func testNoneIsEmptyObject() {
        XCTAssertEqual(String(data: DecisionEncoder.encode(.none, for: .claude), encoding: .utf8), "{}")
        XCTAssertEqual(String(data: DecisionEncoder.encode(.none, for: .codex), encoding: .utf8), "{}")
    }

    func testQuestionParseAndAnswerJoin() {
        let input: [String: Any] = ["questions": [[
            "question": "Which framework?", "header": "Framework", "multiSelect": true,
            "options": [["label": "React", "description": "Component library"], ["label": "Vue", "description": "Progressive framework"]],
        ]]]
        let qs = QuestionAnswer.parse(toolInput: input)
        XCTAssertEqual(qs.count, 1)
        XCTAssertEqual(qs[0].question, "Which framework?")
        XCTAssertEqual(qs[0].header, "Framework")
        XCTAssertTrue(qs[0].multiSelect)
        XCTAssertEqual(qs[0].options.map(\.label), ["React", "Vue"])
        let updated = QuestionAnswer.updatedInput(original: input, answers: ["Which framework?": ["React", "Vue"]])
        XCTAssertEqual(updated["answers"] as? [String: String], ["Which framework?": "React, Vue"])
        XCTAssertTrue(NSArray(array: updated["questions"] as? [Any] ?? []).isEqual(to: input["questions"] as? [Any] ?? []))
    }

    func testPlanAnswerEchoesPlan() {
        let input: [String: Any] = ["plan": "## Do it", "planFilePath": "/tmp/plan.md", "allowedPrompts": []]
        let updated = PlanAnswer.updatedInput(original: input)
        XCTAssertEqual(updated["plan"] as? String, "## Do it")
        XCTAssertEqual(updated["planFilePath"] as? String, "/tmp/plan.md")
    }
}
