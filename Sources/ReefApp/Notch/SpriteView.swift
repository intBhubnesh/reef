import ReefCore
import SwiftUI

/// A 5×5 pixel glyph per agent, blinking while it works and tinted by what it needs from you.
struct SpriteView: View {
    let source: AgentSource
    let status: SessionStatus
    var pixel: CGFloat = 3
    var gap: CGFloat = 1

    static let claude: [[Int]] = [
        [1, 0, 1, 0, 1],
        [0, 1, 1, 1, 0],
        [1, 1, 0, 1, 1],
        [0, 1, 1, 1, 0],
        [1, 0, 1, 0, 1],
    ]
    static let codex: [[Int]] = [
        [1, 1, 1, 1, 1],
        [1, 0, 0, 0, 1],
        [1, 0, 1, 0, 1],
        [1, 0, 0, 0, 1],
        [1, 1, 1, 1, 1],
    ]

    private var pattern: [[Int]] { source == .claude ? Self.claude : Self.codex }

    private var color: Color {
        switch status {
        case .waitingForApproval, .waitingForQuestion, .waitingForPlan: return Theme.waiting
        case .done: return Theme.done
        case .failed: return Theme.failed
        default: return Theme.accent
        }
    }

    private var blinks: Bool {
        switch status {
        case .working, .runningTool, .compacting: return true
        default: return false
        }
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.25)) { context in
            let phase = Int(context.date.timeIntervalSinceReferenceDate * 2) % 2 == 0
            Grid(horizontalSpacing: gap, verticalSpacing: gap) {
                ForEach(0..<5, id: \.self) { row in
                    GridRow {
                        ForEach(0..<5, id: \.self) { col in
                            Rectangle()
                                .fill(pattern[row][col] == 1 ? color : .clear)
                                .frame(width: pixel, height: pixel)
                        }
                    }
                }
            }
            .opacity(blinks && !phase ? 0.45 : 1)
            .shadow(color: color.opacity(0.6), radius: 2)
        }
        .frame(width: pixel * 5 + gap * 4, height: pixel * 5 + gap * 4)
        .accessibilityLabel("\(source.rawValue) session")
    }
}
