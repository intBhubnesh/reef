import Foundation

public enum HookIntent: String, Codable, Equatable {
    case untouched, installed, uninstalled
}

public enum HookHealthIssue: String, Codable, Equatable {
    case bridgeMissing, bridgeNotExecutable, configMissing, configMalformed
    case missingManagedEvents, staleManagedCommand
}

public struct HookHealth: Equatable {
    public let source: AgentSource
    public let issues: [HookHealthIssue]
    public let missingEvents: [String]
    public let staleEvents: [String]

    public init(source: AgentSource, issues: [HookHealthIssue],
                missingEvents: [String] = [], staleEvents: [String] = []) {
        self.source = source
        self.issues = issues
        self.missingEvents = missingEvents
        self.staleEvents = staleEvents
    }

    public var isHealthy: Bool { issues.isEmpty }
    public var isAutoRepairable: Bool {
        !issues.contains(.configMalformed)
    }
}
