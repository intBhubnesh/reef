import Foundation

/// One rendered state of the agent character: which body frame, whether its eyes are open,
/// and the optional glyph beside it.
public struct SpriteFrame: Equatable {
    public enum Glyph: Equatable {
        /// Shown while the agent is waiting on the user; bobs one cell.
        case question
        /// Shown once the turn is done; blinks.
        case cursor
    }

    public let bodyFrame: Int
    public let eyesOpen: Bool
    /// Horizontal eye position in cells: -1, 0 or 1. The eyes move on every step so the
    /// character changes visibly at 150 ms, while the body only changes every fourth (M12).
    public let eyeShift: Int
    public let glyph: Glyph?
    public let glyphRaised: Bool
    public let cursorOn: Bool

    public init(bodyFrame: Int, eyesOpen: Bool, eyeShift: Int = 0, glyph: Glyph?, glyphRaised: Bool, cursorOn: Bool) {
        self.bodyFrame = bodyFrame
        self.eyesOpen = eyesOpen
        self.eyeShift = eyeShift
        self.glyph = glyph
        self.glyphRaised = glyphRaised
        self.cursorOn = cursorOn
    }
}

/// Turns a session's status and the time since it changed into a sprite frame.
/// Pure, so every cadence in `MOTION-SPEC.md` is unit-testable without a screen.
public enum SpriteAnimator {
    public static func frame(status: SessionStatus, elapsed: TimeInterval, seed: UInt64,
                             reduceMotion: Bool = false) -> SpriteFrame {
        let t = max(0, elapsed)

        switch status {
        case .idle, .working, .runningTool, .compacting:
            let step = reduceMotion ? 0 : Int(t / Motion.spriteFramePeriod) % Motion.spriteCycleFrames
            return SpriteFrame(bodyFrame: step, eyesOpen: true,
                               eyeShift: reduceMotion ? 0 : Self.lookCycle[step % Self.lookCycle.count],
                               glyph: nil, glyphRaised: false, cursorOn: false)

        case .waitingForApproval, .waitingForQuestion, .waitingForPlan:
            guard !reduceMotion else {
                return SpriteFrame(bodyFrame: 0, eyesOpen: true, glyph: .question, glyphRaised: false, cursorOn: false)
            }
            let phase = t.truncatingRemainder(dividingBy: Motion.bobUp + Motion.bobDown)
            return SpriteFrame(bodyFrame: 0, eyesOpen: eyesOpenWhileWaiting(t: t, seed: seed),
                               glyph: .question, glyphRaised: phase < Motion.bobUp, cursorOn: false)

        case .done:
            guard !reduceMotion else {
                return SpriteFrame(bodyFrame: 0, eyesOpen: true, glyph: .cursor, glyphRaised: false, cursorOn: true)
            }
            let blinkPhase = t.truncatingRemainder(dividingBy: Motion.blinkPeriod)
            let cursorPhase = (t - Motion.cursorFirstOn).truncatingRemainder(dividingBy: Motion.cursorOn + Motion.cursorOff)
            let cursorLit = t >= Motion.cursorFirstOn && cursorPhase < Motion.cursorOn
            return SpriteFrame(bodyFrame: 0, eyesOpen: blinkPhase >= Motion.blinkClosed,
                               glyph: .cursor, glyphRaised: false, cursorOn: cursorLit)

        case .failed:
            return SpriteFrame(bodyFrame: 0, eyesOpen: false, glyph: nil, glyphRaised: false, cursorOn: false)
        }
    }

    /// Where the eyes look on each step. No two neighbours match, so every 150 ms step
    /// changes the drawn frame; the pattern returns to centre at the end of the cycle.
    static let lookCycle = [0, 1, 0, -1]

    /// The eyes jump on an irregular schedule so two waiting agents never move in lockstep.
    /// Gaps come from a seeded generator, so the same session always animates the same way.
    private static func eyesOpenWhileWaiting(t: TimeInterval, seed: UInt64) -> Bool {
        var state = seed &* 0x9E37_79B9_7F4A_7C15 | 1
        var boundary: TimeInterval = 0
        var open = true
        let span = Motion.waitEyeMaxGap - Motion.waitEyeMinGap
        // The schedule is replayed from zero each call; a waiting state is short-lived and
        // the loop costs a few dozen iterations per frame at most.
        while boundary <= t {
            boundary += Motion.waitEyeMinGap + span * nextUnit(&state)
            open.toggle()
        }
        return open
    }

    /// SplitMix64, inlined so the schedule does not depend on the platform's RNG.
    private static func nextUnit(_ state: inout UInt64) -> Double {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        z ^= z >> 31
        return Double(z >> 11) / Double(1 << 53)
    }
}
