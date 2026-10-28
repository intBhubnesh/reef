import Foundation

/// "Always allow" payload: echo the agent's own suggestion when it sent one, else a whole-tool rule.
public struct AlwaysAllow {
    public let toolName: String
    public let suggestion: [String: Any]?

    public init(toolName: String, suggestion: [String: Any]?) {
        self.toolName = toolName
        self.suggestion = suggestion
    }
}

extension AlwaysAllow: Equatable {
    public static func == (lhs: AlwaysAllow, rhs: AlwaysAllow) -> Bool {
        lhs.toolName == rhs.toolName && NSDictionary(dictionary: lhs.suggestion ?? [:]).isEqual(to: rhs.suggestion ?? [:])
    }
}

/// What the user decided about a pending request. `.none` leaves the agent's own prompt in charge.
public enum Decision {
    case none
    case allow(updatedInput: [String: Any]? = nil, alwaysAllow: AlwaysAllow? = nil)
    case deny(message: String)
}

extension Decision: Equatable {
    public static func == (lhs: Decision, rhs: Decision) -> Bool {
        switch (lhs, rhs) {
        case (.none, .none): return true
        case let (.deny(a), .deny(b)): return a == b
        case let (.allow(ia, aa), .allow(ib, ab)):
            return aa == ab && NSDictionary(dictionary: ia ?? [:]).isEqual(to: ib ?? [:])
        default: return false
        }
    }
}

public enum DecisionEncoder {
    /// Encodes the decision as the hook's stdout JSON for the given agent (no trailing newline).
    public static func encode(_ decision: Decision, for source: AgentSource) -> Data {
        var inner: [String: Any]
        switch decision {
        case .none:
            return "{}".data(using: .utf8)!
        case let .deny(message):
            inner = ["behavior": "deny", "message": message]
        case let .allow(updatedInput, alwaysAllow):
            inner = ["behavior": "allow"]
            if let updatedInput { inner["updatedInput"] = updatedInput }
            if source == .claude, let alwaysAllow {
                inner["updatedPermissions"] = [alwaysAllow.suggestion ?? sessionRule(toolName: alwaysAllow.toolName)]
            }
        }
        let object: [String: Any] = ["hookSpecificOutput": ["hookEventName": "PermissionRequest", "decision": inner]]
        return (try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])) ?? "{}".data(using: .utf8)!
    }

    static func sessionRule(toolName: String) -> [String: Any] {
        ["type": "addRules", "behavior": "allow", "destination": "session", "rules": [["toolName": toolName]]]
    }
}
