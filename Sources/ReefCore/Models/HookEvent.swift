import Foundation

/// One hook event as delivered by an agent CLI (Claude Code or Codex) on the hook's stdin.
public struct HookEvent {
    public enum Error: Swift.Error, Equatable {
        case notAnObject
        case missingField(String)
    }

    public let source: AgentSource
    public let name: String
    public let sessionID: String
    public let cwd: String?
    public let toolName: String?
    public let toolInput: [String: Any]?
    public let toolUseID: String?
    public let notificationType: String?
    public let lastAssistantMessage: String?
    public let prompt: String?
    public let transcriptPath: String?
    public let permissionSuggestions: [[String: Any]]?
    public let raw: [String: Any]

    public init(source: AgentSource, json: [String: Any]) throws {
        guard let name = json["hook_event_name"] as? String else { throw Error.missingField("hook_event_name") }
        guard let sessionID = json["session_id"] as? String else { throw Error.missingField("session_id") }
        self.source = source
        self.name = name
        self.sessionID = sessionID
        cwd = json["cwd"] as? String
        toolName = json["tool_name"] as? String
        toolInput = json["tool_input"] as? [String: Any]
        toolUseID = json["tool_use_id"] as? String
        notificationType = json["notification_type"] as? String
        lastAssistantMessage = json["last_assistant_message"] as? String
        prompt = json["prompt"] as? String
        transcriptPath = json["transcript_path"] as? String
        permissionSuggestions = json["permission_suggestions"] as? [[String: Any]]
        raw = json
    }

    public static func parse(source: AgentSource, data: Data) throws -> HookEvent {
        guard let object = try? JSONSerialization.jsonObject(with: data),
              let json = object as? [String: Any]
        else { throw Error.notAnObject }
        return try HookEvent(source: source, json: json)
    }
}

extension HookEvent: Equatable {
    public static func == (lhs: HookEvent, rhs: HookEvent) -> Bool {
        lhs.source == rhs.source && lhs.name == rhs.name && lhs.sessionID == rhs.sessionID
            && lhs.cwd == rhs.cwd && lhs.toolName == rhs.toolName && lhs.toolUseID == rhs.toolUseID
            && lhs.notificationType == rhs.notificationType
            && lhs.lastAssistantMessage == rhs.lastAssistantMessage && lhs.prompt == rhs.prompt
            && lhs.transcriptPath == rhs.transcriptPath
            && NSDictionary(dictionary: lhs.toolInput ?? [:]).isEqual(to: rhs.toolInput ?? [:])
            && NSArray(array: lhs.permissionSuggestions ?? []).isEqual(to: rhs.permissionSuggestions ?? [])
    }
}
