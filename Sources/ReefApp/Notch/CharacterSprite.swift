import ReefCore
import SwiftUI

/// Reef's own agent character: an original 8 × 6 cell creature drawn for this app.
/// Row 0 is the top. The body alternates between two poses; the eyes are drawn separately so
/// they can blink independently of the body cycle.
enum CharacterGlyph {
    /// Two body poses. The reference changes pose every fourth 150 ms step (M12), so frames
    /// 0–3 use pose 0 and frames 4–7 use pose 1.
    static let bodies: [[[Int]]] = [
        // Pose A: a rounded shell with the fins tucked in.
        [
            [0, 0, 1, 1, 1, 1, 0, 0],
            [0, 1, 1, 1, 1, 1, 1, 0],
            [1, 1, 1, 1, 1, 1, 1, 1],
            [1, 1, 1, 1, 1, 1, 1, 1],
            [0, 1, 1, 1, 1, 1, 1, 0],
            [0, 1, 0, 1, 1, 0, 1, 0],
        ],
        // Pose B: the shell lifts a row and the fins spread.
        [
            [0, 0, 1, 1, 1, 1, 0, 0],
            [0, 1, 1, 1, 1, 1, 1, 0],
            [1, 1, 1, 1, 1, 1, 1, 1],
            [1, 1, 1, 1, 1, 1, 1, 1],
            [1, 1, 1, 1, 1, 1, 1, 1],
            [1, 0, 1, 0, 0, 1, 0, 1],
        ],
    ]

    /// Eye cells, punched out of the body so they read as eyes on any pose.
    static let eyesOpen: [[Int]] = [
        [0, 0, 0, 0, 0, 0, 0, 0],
        [0, 0, 0, 0, 0, 0, 0, 0],
        [0, 1, 1, 0, 0, 1, 1, 0],
        [0, 0, 0, 0, 0, 0, 0, 0],
        [0, 0, 0, 0, 0, 0, 0, 0],
        [0, 0, 0, 0, 0, 0, 0, 0],
    ]

    /// A closed eye is a single cell, so a blink reads clearly at 16 pt.
    static let eyesClosed: [[Int]] = [
        [0, 0, 0, 0, 0, 0, 0, 0],
        [0, 0, 0, 0, 0, 0, 0, 0],
        [0, 0, 1, 0, 0, 1, 0, 0],
        [0, 0, 0, 0, 0, 0, 0, 0],
        [0, 0, 0, 0, 0, 0, 0, 0],
        [0, 0, 0, 0, 0, 0, 0, 0],
    ]

    /// Glyphs shown beside the character, on their own 3 × 6 grid.
    static let question: [[Int]] = [
        [1, 1, 1],
        [0, 0, 1],
        [0, 1, 1],
        [0, 1, 0],
        [0, 0, 0],
        [0, 1, 0],
    ]

    static let cursor: [[Int]] = [
        [1, 1, 1],
        [0, 1, 0],
        [0, 1, 0],
        [0, 1, 0],
        [0, 1, 0],
        [1, 1, 1],
    ]

    static let glyphColumns = 3
}

/// Draws the character for one session, animated by `SpriteAnimator`.
/// Owns the only per-frame timer in the app; nothing above it re-renders on the tick.
struct CharacterSprite: View {
    let status: SessionStatus
    let seed: UInt64
    let phaseStart: Date
    var cell: CGFloat = 2.5
    var reduceMotion: Bool = false

    private var totalWidth: CGFloat { cell * CGFloat(Metrics.spriteColumns + 1 + CharacterGlyph.glyphColumns) }
    private var totalHeight: CGFloat { cell * CGFloat(Metrics.spriteRows) }

    var body: some View {
        Group {
            if reduceMotion {
                draw(SpriteAnimator.frame(status: status, elapsed: 0, seed: seed, reduceMotion: true))
            } else {
                TimelineView(.periodic(from: phaseStart, by: Motion.spriteFramePeriod)) { context in
                    draw(SpriteAnimator.frame(status: status,
                                              elapsed: context.date.timeIntervalSince(phaseStart),
                                              seed: seed))
                }
            }
        }
        .frame(width: totalWidth, height: totalHeight, alignment: .leading)
        .accessibilityLabel(accessibilityText)
    }

    @ViewBuilder
    private func draw(_ frame: SpriteFrame) -> some View {
        let color = Theme.statusColor(status)
        Canvas { context, _ in
            let pose = CharacterGlyph.bodies[(frame.bodyFrame / 4) % CharacterGlyph.bodies.count]
            let eyes = frame.eyesOpen ? CharacterGlyph.eyesOpen : CharacterGlyph.eyesClosed
            for row in 0..<Metrics.spriteRows {
                for col in 0..<Metrics.spriteColumns where pose[row][col] == 1 {
                    // The eye cells are punched out of the body, shifted by where it is looking.
                    let eyeCol = col - frame.eyeShift
                    let isEye = eyeCol >= 0 && eyeCol < Metrics.spriteColumns && eyes[row][eyeCol] == 1
                    guard !isEye else { continue }
                    context.fill(Path(CGRect(x: CGFloat(col) * cell, y: CGFloat(row) * cell, width: cell, height: cell)),
                                 with: .color(color))
                }
            }
            guard let glyph = frame.glyph else { return }
            let pattern = glyph == .question ? CharacterGlyph.question : CharacterGlyph.cursor
            let visible = glyph == .cursor ? frame.cursorOn : true
            guard visible else { return }
            let originX = CGFloat(Metrics.spriteColumns + 1) * cell
            let originY = frame.glyphRaised ? -cell : 0
            for row in 0..<Metrics.spriteRows {
                for col in 0..<CharacterGlyph.glyphColumns where pattern[row][col] == 1 {
                    context.fill(Path(CGRect(x: originX + CGFloat(col) * cell, y: originY + CGFloat(row) * cell,
                                             width: cell, height: cell)),
                                 with: .color(color))
                }
            }
        }
        .shadow(color: color.opacity(0.55), radius: cell * 0.8)
    }

    private var accessibilityText: String {
        switch status {
        case .idle: return "Agent idle"
        case .working, .runningTool, .compacting: return "Agent working"
        case .waitingForApproval, .waitingForQuestion, .waitingForPlan: return "Agent waiting for you"
        case .done: return "Agent finished"
        case .failed: return "Agent failed"
        }
    }
}
