import Foundation

/// Source-neutral event consumed by session state. Agent-specific spelling and wire quirks stop
/// at this boundary; adding another agent requires an adapter, not UI changes.
public struct AgentEvent: Equatable {
    public enum Kind: Equatable {
        case sessionStarted, sessionEnded, promptSubmitted
        case toolStarted, toolFinished, toolFailed
        case permissionRequested, notification
        case compactingStarted, compactingFinished
        case turnCompleted, turnFailed, interrupted
        case subagentStarted, subagentFinished
        case heartbeat, unknown(String)
    }

    public let kind: Kind
    public let hook: HookEvent

    public init(kind: Kind, hook: HookEvent) {
        self.kind = kind
        self.hook = hook
    }
}

public enum AgentEventAdapter {
    public static func normalize(_ event: HookEvent) -> AgentEvent {
        let normalized = event.name.replacingOccurrences(of: "_", with: "").lowercased()
        let kind: AgentEvent.Kind
        switch normalized {
        case "sessionstart": kind = .sessionStarted
        case "sessionend", "sessionshutdown": kind = .sessionEnded
        case "userpromptsubmit", "promptsubmit": kind = .promptSubmitted
        case "pretooluse", "toolexecutionstart": kind = .toolStarted
        case "posttooluse", "toolexecutionend": kind = .toolFinished
        case "posttoolusefailure": kind = .toolFailed
        case "permissionrequest": kind = .permissionRequested
        case "notification": kind = .notification
        case "precompact": kind = .compactingStarted
        case "postcompact": kind = .compactingFinished
        case "stop", "agentsettled": kind = .turnCompleted
        case "stopfailure": kind = .turnFailed
        case "interrupt", "stopcancelled": kind = .interrupted
        case "subagentstart": kind = .subagentStarted
        case "subagentstop": kind = .subagentFinished
        case "heartbeat": kind = .heartbeat
        default: kind = .unknown(event.name)
        }
        return AgentEvent(kind: kind, hook: event)
    }
}
