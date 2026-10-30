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
    /// The motion that belongs to the most recent state change; the view reads this to pick its spring.
    public private(set) var lastTransition: NotchTransition = .snap

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
        let before = state
        switch intent {
        case let .hoverEnter(now):
            hovering = true
            switch state {
            case .closed:
                hoverDeadline = now.addingTimeInterval(timing.hoverDelay)
            case .transient(kind: .hover, _):
                state = .transient(kind: .hover, until: .distantFuture)
            case let .transient(kind, _):
                // A peek the pointer is reading stays open; its hold restarts on exit (M9).
                state = .transient(kind: kind, until: .distantFuture)
            default: break
            }
        case let .hoverExit(now):
            hovering = false
            hoverDeadline = nil
            switch state {
            case .transient(kind: .hover, _):
                if timing.autoCollapseOnLeave {
                    state = .transient(kind: .hover, until: now.addingTimeInterval(timing.leaveCollapse))
                }
            case let .transient(kind, _):
                state = .transient(kind: kind, until: now.addingTimeInterval(timing.revealDwell))
            default: break
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
        recordTransition(from: before, to: state, intent: intent)
        return state
    }

    /// Which motion the view should use for the change that just happened.
    private mutating func recordTransition(from before: NotchState, to after: NotchState, intent: NotchIntent) {
        guard before != after else { return }
        if after == .closed {
            lastTransition = .collapse
            return
        }
        switch intent {
        case .requestArrived: lastTransition = .requestExpand
        case .taskComplete, .taskFailed: lastTransition = .peekExpand
        case .click: lastTransition = .hoverExpand
        case .tick, .hoverEnter, .hoverExit:
            // A tick that opens the panel is the hover dwell firing; one that only moves a
            // deadline is not a visible change at all.
            lastTransition = before == .closed ? .hoverExpand : .snap
        default: lastTransition = .snap
        }
    }

    private var isTransient: Bool {
        if case .transient = state { return true }
        return false
    }
}
