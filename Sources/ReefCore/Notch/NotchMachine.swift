import Foundation

public enum NotchState: Equatable {
    public enum TransientKind: Equatable { case hover, completion, failure }

    case closed
    case transient(kind: TransientKind, until: Date)
    case blocking
    case manualExpanded

    public var isExpanded: Bool { self != .closed }
}

public enum NotchIntent: Equatable {
    case hoverEnter(Date), hoverExit(Date), click(Date)
    case requestArrived(Date), requestsCleared(Date)
    case taskComplete(Date), taskFailed(Date)
    case escape(Date), outsideClick(Date), tick(Date)
}

public struct NotchTiming: Equatable {
    public var hoverDelay: TimeInterval = 0.15
    public var revealDwell: TimeInterval = 5
    public var leaveCollapse: TimeInterval = 1
    public var autoCollapseOnLeave = true
    public init() {}
}

/// Pure state machine for the island: expand on hover dwell, hold while a request blocks, reveal completions, collapse.
public struct NotchMachine: Equatable {
    public private(set) var state: NotchState = .closed
    public var timing: NotchTiming
    /// Number of live pending requests, maintained by the owner before sending request intents.
    public var pendingCount = 0

    private var hoverDeadline: Date?
    private var hovering = false

    public init(timing: NotchTiming) { self.timing = timing }

    /// When the owner should next send `.tick`.
    public var nextDeadline: Date? {
        if let hoverDeadline { return hoverDeadline }
        if case let .transient(_, until) = state, until != .distantFuture { return until }
        return nil
    }

    @discardableResult
    public mutating func apply(_ intent: NotchIntent) -> NotchState {
        switch intent {
        case let .hoverEnter(now):
            hovering = true
            switch state {
            case .closed:
                hoverDeadline = now.addingTimeInterval(timing.hoverDelay)
            case .transient(kind: .hover, _):
                state = .transient(kind: .hover, until: .distantFuture)
            default: break
            }
        case let .hoverExit(now):
            hovering = false
            hoverDeadline = nil
            if case .transient(kind: .hover, _) = state, timing.autoCollapseOnLeave {
                state = .transient(kind: .hover, until: now.addingTimeInterval(timing.leaveCollapse))
            }
        case .click:
            hoverDeadline = nil
            state = (state == .manualExpanded) ? .closed : .manualExpanded
        case .requestArrived:
            hoverDeadline = nil
            if state != .manualExpanded { state = .blocking }
        case .requestsCleared:
            if state == .blocking, pendingCount == 0 { state = .closed }
        case let .taskComplete(now):
            if state == .closed || isTransient { state = .transient(kind: .completion, until: now.addingTimeInterval(timing.revealDwell)) }
        case let .taskFailed(now):
            if state == .closed || isTransient { state = .transient(kind: .failure, until: now.addingTimeInterval(timing.revealDwell)) }
        case .escape:
            hoverDeadline = nil
            state = .closed
        case .outsideClick:
            if state == .manualExpanded || isTransient { state = .closed }
        case let .tick(now):
            if let deadline = hoverDeadline, now >= deadline {
                hoverDeadline = nil
                if hovering, state == .closed { state = .transient(kind: .hover, until: .distantFuture) }
            }
            if case let .transient(_, until) = state, now >= until { state = .closed }
        }
        return state
    }

    private var isTransient: Bool {
        if case .transient = state { return true }
        return false
    }
}
