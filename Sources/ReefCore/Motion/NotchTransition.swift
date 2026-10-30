import Foundation

/// Which motion a state change gets. Every event in the reference app has its own entrance:
/// a hover expansion, a request arriving, a completion peek and a collapse all move differently.
public enum NotchTransition: Equatable {
    /// Pointer dwelled on the pill (M2).
    case hoverExpand
    /// A blocking request arrived; the pill swaps first, the panel follows (M6).
    case requestExpand
    /// The turn finished and the panel peeks (M8).
    case peekExpand
    /// Anything closing (M7): no overshoot.
    case collapse
    /// Content changed while the panel was open (M11): no animation at all.
    case snap

    public var delay: TimeInterval {
        switch self {
        case .hoverExpand: return Motion.hoverDwell
        case .requestExpand: return Motion.requestExpandDelay
        case .peekExpand, .collapse, .snap: return 0
        }
    }

    public var response: TimeInterval {
        switch self {
        case .hoverExpand, .requestExpand, .peekExpand: return Motion.expandResponse
        case .collapse: return Motion.collapseResponse
        case .snap: return 0
        }
    }

    public var damping: Double {
        switch self {
        case .hoverExpand, .requestExpand, .peekExpand: return Motion.expandDamping
        case .collapse: return Motion.collapseDamping
        case .snap: return 1
        }
    }

    /// When the panel's content starts fading in, measured from the start of the frame change.
    public var revealDelay: TimeInterval {
        self == .hoverExpand ? Motion.headerFadeDelay : Motion.autoRevealFadeDelay
    }

    public var revealDuration: TimeInterval {
        self == .hoverExpand ? Motion.headerFadeDuration : Motion.autoRevealFadeDuration
    }

    /// Rows trail the header slightly on a hover expansion.
    public var rowRevealDelay: TimeInterval {
        self == .hoverExpand ? Motion.rowFadeDelay : Motion.autoRevealFadeDelay
    }

    public var rowRevealDuration: TimeInterval {
        self == .hoverExpand ? Motion.rowFadeDuration : Motion.autoRevealFadeDuration
    }
}
