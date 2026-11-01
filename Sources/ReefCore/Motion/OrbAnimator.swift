import CoreGraphics
import Foundation

/// One projected capsule eye. Width/height are in circle-radius units; the 2×2 matrix is the
/// tangent basis produced by Bloub's spherical eye model, including screen-space blinking.
public struct OrbEyeFrame: Equatable {
    public var x: CGFloat
    public var y: CGFloat
    public var width: CGFloat
    public var height: CGFloat
    public var a: CGFloat
    public var b: CGFloat
    public var c: CGFloat
    public var d: CGFloat
    public var alpha: CGFloat

    public init(x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat,
                a: CGFloat, b: CGFloat, c: CGFloat, d: CGFloat, alpha: CGFloat) {
        self.x = x; self.y = y
        self.width = width; self.height = height
        self.a = a; self.b = b; self.c = c; self.d = d
        self.alpha = alpha
    }
}

/// One vector-avatar pose. Geometry uses the same radius-relative coordinate system as Bloub.
public struct OrbFrame: Equatable {
    public var emotion: AvatarEmotion
    public var bodyScaleY: CGFloat = 1
    public var driftX: CGFloat = 0
    public var driftY: CGFloat = 0
    public var eyes: [OrbEyeFrame] = []
    public var badgeScale: CGFloat = 0
    public var showsOrbit = false
    public var orbitAngle: Double = 0

    public init(emotion: AvatarEmotion = .neutral) { self.emotion = emotion }
}

/// Native, clock-free port of Bloub's expression and eye-projection pipeline.
public enum OrbAnimator {
    public static func frame(status: SessionStatus, elapsed: TimeInterval, seed: UInt64,
                             emotion override: AvatarEmotion? = nil,
                             reduceMotion: Bool = false) -> OrbFrame {
        let emotion = override ?? AvatarStatusSlot.emotion(for: status)
        let expression = emotion.expression
        // Gallery previews in Bloub freeze at t=1. A session seed only de-phases live avatars;
        // it does not change their measured expression.
        let seedOffset = Double(seed % 1_009) / 1_009 * 3.7
        let t = reduceMotion ? 1 : max(0, elapsed) + seedOffset
        let life = liveliness(t)
        let gaze = AvatarHeadGaze(
            yaw: expression.gaze.yaw + life.dYaw,
            pitch: expression.gaze.pitch + life.dPitch,
            roll: expression.gaze.roll + life.dRoll
        )

        var frame = OrbFrame(emotion: emotion)
        frame.bodyScaleY = CGFloat(life.breath)
        frame.driftX = CGFloat(life.driftX / 2)
        frame.driftY = CGFloat(life.driftY / 2)

        let projections = eyePoses(gaze: gaze, split: expression.split)
        for index in 0..<2 {
            let projection = projections[index]
            guard projection.depth > 0.02 else { continue }
            let config = expression.eyes[index]
            let phi = radians(config.tilt)
            let cp = cos(phi), sp = sin(phi)
            let ax = projection.a * cp + projection.c * sp
            let ay = projection.b * cp + projection.d * sp
            let cx = -projection.a * sp + projection.c * cp
            let cy = -projection.b * sp + projection.d * cp
            let blink = blinkScale(min(life.lid, config.open))
            frame.eyes.append(OrbEyeFrame(
                x: CGFloat(projection.x), y: CGFloat(projection.y),
                width: CGFloat(config.width), height: CGFloat(config.height),
                a: CGFloat(ax), b: CGFloat(ay * blink),
                c: CGFloat(cx), d: CGFloat(cy * blink),
                alpha: CGFloat(clamp(projection.depth / 0.12))
            ))
        }

        // The expression controls the exact face. Status adds only the non-face decoration.
        switch status {
        case .working:
            frame.showsOrbit = true
            frame.orbitAngle = t * 1.7
        case .runningTool:
            frame.showsOrbit = true
            frame.orbitAngle = t * 2.8
        case .compacting:
            frame.showsOrbit = true
            frame.orbitAngle = -t * 1.3
        case .waitingForApproval:
            frame.badgeScale = reduceMotion ? 1 : CGFloat(1 + sin(t * 2 * .pi / 1.1) * 0.12)
        case .waitingForPlan:
            frame.badgeScale = reduceMotion ? 0.78 : CGFloat(0.78 + sin(t * 2 * .pi / 1.8) * 0.08)
        case .idle, .waitingForQuestion, .done, .failed:
            break
        }
        return frame
    }

    // MARK: - Exact spherical projection from src/bot/face.ts

    private struct Vector3 {
        var x: Double
        var y: Double
        var z: Double
    }

    private struct EyeProjection {
        var x: Double
        var y: Double
        var a: Double
        var b: Double
        var c: Double
        var d: Double
        var depth: Double
    }

    private static func spin(_ u: Vector3, _ v: Vector3, _ angle: Double) -> (Vector3, Vector3) {
        let c = cos(angle), s = sin(angle)
        return (
            Vector3(x: u.x * c + v.x * s, y: u.y * c + v.y * s, z: u.z * c + v.z * s),
            Vector3(x: v.x * c - u.x * s, y: v.y * c - u.y * s, z: v.z * c - u.z * s)
        )
    }

    private static func eyePoses(gaze: AvatarHeadGaze, split: Double) -> [EyeProjection] {
        var forward = Vector3(x: 0, y: 0, z: 1)
        var right = Vector3(x: 1, y: 0, z: 0)
        var down = Vector3(x: 0, y: 1, z: 0)

        (forward, right) = spin(forward, right, radians(gaze.yaw))
        (down, forward) = spin(down, forward, radians(gaze.pitch))
        (right, down) = spin(right, down, radians(gaze.roll))

        return [-1.0, 1.0].map { side in
            let (eyeForward, eyeRight) = spin(forward, right, radians(split * side))
            return EyeProjection(x: eyeForward.x, y: eyeForward.y,
                                 a: eyeRight.x, b: eyeRight.y,
                                 c: down.x, d: down.y, depth: eyeForward.z)
        }
    }

    // MARK: - Exact idle liveliness from src/bot/face.ts and math.ts

    private struct Liveliness {
        var dYaw: Double
        var dPitch: Double
        var dRoll: Double
        var lid: Double
        var driftX: Double
        var driftY: Double
        var breath: Double
    }

    private static func liveliness(_ t: Double) -> Liveliness {
        Liveliness(
            dYaw: loopNoise(t, period: 11.3, seed: 0.4) * 5.5
                + loopNoise(t, period: 3.7, seed: 2.1) * 1.6,
            dPitch: loopNoise(t, period: 9.1, seed: 1.3) * 4.2
                + loopNoise(t, period: 4.3, seed: 0.7) * 1.3,
            dRoll: loopNoise(t, period: 13.7, seed: 3.2) * 2.2,
            lid: blinkLid(t),
            driftX: loopNoise(t, period: 7.9, seed: 1.9) * 0.006,
            driftY: loopNoise(t, period: 5.3, seed: 0.3) * 0.007,
            breath: 1 + sin((t / 3.4) * .pi * 2) * 0.005
        )
    }

    private static func loopNoise(_ t: Double, period: Double, seed: Double) -> Double {
        let p = (t / period) * .pi * 2
        return 0.55 * sin(p + seed)
            + 0.3 * sin(2 * p + seed * 1.7 + 1.1)
            + 0.15 * sin(3 * p + seed * 2.3 + 2.4)
    }

    private static let blinks: [Double] = {
        var random = Mulberry32(seed: 0x5eed)
        var result: [Double] = []
        var t = 1.4
        while t < 900 {
            result.append(t)
            t += 1.9 + random.next() * 2.7
            if random.next() < 0.18 {
                result.append(t)
                t += 0.24
            }
        }
        return result
    }()

    private static func blinkLid(_ time: Double) -> Double {
        let t = time.truncatingRemainder(dividingBy: 900)
        for start in blinks {
            if t < start { break }
            let progress = (t - start) / 0.18
            if progress >= 0, progress <= 1 {
                return progress < 0.45 ? 1 - progress / 0.45 : (progress - 0.45) / 0.55
            }
        }
        return 1
    }

    private static func blinkScale(_ lid: Double) -> Double { 0.06 + 0.94 * clamp(lid) }
    private static func clamp(_ value: Double) -> Double { min(1, max(0, value)) }
    private static func radians(_ degrees: Double) -> Double { degrees * .pi / 180 }

    private struct Mulberry32 {
        var state: UInt32
        init(seed: UInt32) { state = seed }

        mutating func next() -> Double {
            state &+= 0x6d2b79f5
            var value = (state ^ (state >> 15)) &* (1 | state)
            value = (value &+ ((value ^ (value >> 7)) &* (61 | value))) ^ value
            return Double((value ^ (value >> 14))) / 4_294_967_296
        }
    }
}
