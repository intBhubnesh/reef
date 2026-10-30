import Foundation

public struct SessionKey: Hashable, Codable {
    public let source: AgentSource
    public let sessionID: String
    public init(source: AgentSource, sessionID: String) { self.source = source; self.sessionID = sessionID }
}

public enum SessionStatus: Equatable {
    case idle, working, runningTool(String), waitingForApproval, waitingForQuestion, waitingForPlan, done, failed, compacting

    /// Statuses that share one sprite behaviour. A busy agent changes status several times a
    /// second as tools start and stop; the animation phase must follow the family, not the
    /// status, or the character restarts its cycle constantly and appears frozen.
    public enum AnimationFamily: Equatable { case working, waiting, done, failed }

    public var animationFamily: AnimationFamily {
        switch self {
        case .idle, .working, .runningTool, .compacting: return .working
        case .waitingForApproval, .waitingForQuestion, .waitingForPlan: return .waiting
        case .done: return .done
        case .failed: return .failed
        }
    }

    public var isWaitingOnUser: Bool {
        switch self {
        case .waitingForApproval, .waitingForQuestion, .waitingForPlan: return true
        default: return false
        }
    }
}

public struct PendingRequest: Equatable {
    public enum Kind: Equatable { case permission, question, plan }

    public let requestID: String
    public let event: HookEvent
    public let receivedAt: Date
    public var kind: Kind
    /// False once the request was handed back to the terminal (focus release or timeout); the card stays, read-only.
    public var isLive: Bool

    public init(requestID: String, event: HookEvent, receivedAt: Date, isLive: Bool = true) {
        self.requestID = requestID
        self.event = event
        self.receivedAt = receivedAt
        self.isLive = isLive
        switch event.toolName {
        case "AskUserQuestion": kind = .question
        case "ExitPlanMode": kind = .plan
        default: kind = .permission
        }
    }

    public var status: SessionStatus {
        switch kind {
        case .permission: return .waitingForApproval
        case .question: return .waitingForQuestion
        case .plan: return .waitingForPlan
        }
    }
}

public struct Subagent: Equatable {
    public let id: String
    public var description: String
    public var status: SessionStatus
    public let startedAt: Date
    public init(id: String, description: String, status: SessionStatus, startedAt: Date) {
        self.id = id; self.description = description; self.status = status; self.startedAt = startedAt
    }
}

public struct Session: Equatable {
    public let key: SessionKey
    public var cwd: String?
    public var project: String?
    public var branch: String?
    public var terminal: TerminalIdentity
    public var startedAt: Date
    public var lastEventAt: Date
    public var status: SessionStatus
    /// When `status` last changed. Animation phases are measured from here, so a blink or a
    /// bob starts when the state does rather than at an arbitrary global instant.
    public var statusChangedAt: Date
    /// When the sprite's behaviour last changed. Unlike `statusChangedAt` this survives tool
    /// churn, so the animation keeps running while an agent works.
    public var animationPhaseStart: Date
    /// Stable per-session value that de-phases animation between sessions.
    public let animationSeed: UInt64
    public var model: String?
    public var lastPrompt: String?
    public var lastAssistantMessage: String?
    public var currentTool: String?
    public var subagents: [Subagent]
    public var pending: [PendingRequest]
    public var elapsedToolStart: Date?

    public init(key: SessionKey, startedAt: Date) {
        self.key = key
        terminal = TerminalIdentity()
        self.startedAt = startedAt
        lastEventAt = startedAt
        statusChangedAt = startedAt
        animationPhaseStart = startedAt
        animationSeed = Session.seed(for: key)
        status = .idle
        subagents = []
        pending = []
    }

    /// FNV-1a over the key, so the seed is stable across launches and platforms
    /// (unlike `hashValue`, which is salted per process).
    static func seed(for key: SessionKey) -> UInt64 {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in "\(key.source.rawValue):\(key.sessionID)".utf8 {
            hash = (hash ^ UInt64(byte)) &* 0x1000_0000_01b3
        }
        return hash
    }
}

public enum SoundKind: String, Codable { case inputNeeded, done, failed }

public enum SessionEffect: Equatable {
    case revealCompletion(SessionKey)
    case revealFailure(SessionKey)
    case requestArrived(SessionKey, PendingRequest)
    case requestCleared(SessionKey, requestID: String)
    case sound(SoundKind)
    case removed(SessionKey)
}

public struct SessionState: Equatable {
    public var sessions: [SessionKey: Session]
    public init() { sessions = [:] }

    public var ordered: [Session] { sessions.values.sorted { $0.startedAt < $1.startedAt } }
}
