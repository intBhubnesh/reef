import Foundation

public enum NotchState: Equatable {
    public enum TransientKind: Equatable { case hover, completion, failure }

    case closed
    case transient(kind: TransientKind, until: Date)
    case blocking
    case manualExpanded

    public var isExpanded: Bool { self != .closed }
}

/// Why the island is open. The reason controls activation and dismissal independently from the
/// visual state: a click may activate the panel, while a notification must not steal focus.
public enum NotchOpenReason: String, Codable, Equatable {
    case hover, click, blockingRequest, completion, failure, boot
}

/// The content currently routed into the island. Carrying stable identifiers prevents a late
/// render from showing a card that no longer belongs to the active request/session.
public enum ReefSurface: Equatable {
    case sessionList(actionableRequestID: String?)
    case approval(requestID: String)
    case question(requestID: String)
    case plan(requestID: String)
    case completion(SessionKey)
    case failure(SessionKey)

    public var isBlocking: Bool {
        switch self {
        case .approval, .question, .plan: return true
        default: return false
        }
    }

    /// Questions stay visible while the user considers an answer. Other actionable cards remain
    /// pending in the pill but should not hold the expanded island open after the pointer leaves.
    public var keepsOpenOnPointerExit: Bool {
        if case .question = self { return true }
        return false
    }
}

public enum NotchIntent: Equatable {
    case hoverEnter(Date), hoverExit(Date), click(Date)
    case requestArrived(Date), requestsCleared(Date)
    case taskComplete(Date), taskFailed(Date)
    case escape(Date), outsideClick(Date), tick(Date)
    case present(ReefSurface, reason: NotchOpenReason, at: Date)
    case surfaceEntered(Date)
}

public struct NotchTiming: Equatable {
    public var hoverDelay: TimeInterval = 0.15
    public var revealDwell: TimeInterval = 5
    /// MouseMonitor already supplies a 100 ms edge-cancellation grace. Once that expires the
    /// visual collapse starts immediately and its 300 ms smooth animation provides the easing.
    public var leaveCollapse: TimeInterval = 0
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
    public private(set) var openReason: NotchOpenReason?
    public private(set) var surface: ReefSurface = .sessionList(actionableRequestID: nil)
    /// Notifications opened under a stationary cursor should not collapse until the user has
    /// actually entered and then left the island.
    public private(set) var notificationWasEntered = false

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
            if surface.keepsOpenOnPointerExit { break }
            switch state {
            case .transient(kind: .hover, _):
                if timing.autoCollapseOnLeave {
                    state = .transient(kind: .hover, until: now.addingTimeInterval(timing.leaveCollapse))
                }
            case let .transient(kind, _):
                state = .transient(kind: kind, until: now.addingTimeInterval(timing.leaveCollapse))
            case .manualExpanded, .blocking:
                state = .closed
            default: break
            }
        case .click:
            hoverDeadline = nil
            if state == .manualExpanded {
                state = .closed
            } else {
                state = .manualExpanded
                openReason = .click
                surface = .sessionList(actionableRequestID: nil)
            }
        case .requestArrived:
            hoverDeadline = nil
            if state != .manualExpanded { state = .blocking }
            openReason = .blockingRequest
        case .requestsCleared:
            if state == .blocking, pendingCount == 0 { state = .closed }
        case let .taskComplete(now):
            if state == .closed || isTransient {
                state = .transient(kind: .completion, until: now.addingTimeInterval(timing.revealDwell))
                openReason = .completion
                notificationWasEntered = false
            }
        case let .taskFailed(now):
            if state == .closed || isTransient {
                state = .transient(kind: .failure, until: now.addingTimeInterval(timing.revealDwell))
                openReason = .failure
                notificationWasEntered = false
            }
        case .escape:
            hoverDeadline = nil
            if !surface.isBlocking { state = .closed }
        case .outsideClick:
            if !surface.isBlocking, state == .manualExpanded || isTransient { state = .closed }
        case let .tick(now):
            if let deadline = hoverDeadline, now >= deadline {
                hoverDeadline = nil
                if hovering, state == .closed {
                    state = .transient(kind: .hover, until: .distantFuture)
                    openReason = .hover
                    surface = .sessionList(actionableRequestID: nil)
                }
            }
            if case let .transient(_, until) = state, now >= until { state = .closed }
        case let .present(newSurface, reason, now):
            surface = newSurface
            openReason = reason
            hoverDeadline = nil
            notificationWasEntered = false
            if newSurface.isBlocking {
                state = .blocking
            } else {
                let kind: NotchState.TransientKind = reason == .failure ? .failure : .completion
                state = .transient(kind: kind, until: now.addingTimeInterval(timing.revealDwell))
            }
        case .surfaceEntered:
            notificationWasEntered = true
        }
        if state == .closed {
            openReason = nil
            surface = .sessionList(actionableRequestID: nil)
            notificationWasEntered = false
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
        case let .present(_, reason, _):
            lastTransition = reason == .blockingRequest ? .requestExpand : .peekExpand
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
