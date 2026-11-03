import ReefCore
import SwiftUI

/// Reef's native agent-avatar renderer: Bloub's expressive spherical eyes on either the original
/// orb or an object silhouette from open-bot-avatar. Everything is drawn directly in a SwiftUI
/// `Canvas`; no web view or raster sprite is involved.
///
/// The animation remains a pure function of status, elapsed time and session seed. That keeps
/// multiple agents from moving in lockstep and means Reduce Motion can freeze an exact pose.
struct CharacterSprite: View {
    let status: SessionStatus
    let seed: UInt64
    let phaseStart: Date
    /// Kept as a cell-based input so existing call sites retain their measured sizing.
    /// Eight cells now describe the diameter of the vector avatar.
    var cell: CGFloat = 2.5
    var reduceMotion: Bool = false
    /// When supplied, renders this face instead of the status mapping. Used by the emotion
    /// catalogue and by mapped live sessions.
    var emotion: AvatarEmotion? = nil
    /// The catalogue uses Bloub's original black/white treatment; live sessions keep Reef's
    /// status colour and island-coloured eye cut-outs.
    var bodyColor: Color? = nil
    var eyeColor: Color? = nil
    /// The original orb or one of the bundled open-bot-avatar silhouettes.
    var design: AvatarDesign = .orb

    private var diameter: CGFloat { cell * CGFloat(Metrics.spriteColumns) }

    var body: some View {
        Group {
            if reduceMotion {
                draw(elapsed: 0)
            } else {
                TimelineView(.periodic(from: phaseStart, by: 1.0 / 30.0)) { context in
                    draw(elapsed: max(0, context.date.timeIntervalSince(phaseStart)))
                }
            }
        }
        .frame(width: diameter, height: diameter)
        .accessibilityLabel(accessibilityText)
    }

    private func draw(elapsed: TimeInterval) -> some View {
        let pose = OrbAnimator.frame(status: status, elapsed: elapsed, seed: seed,
                                     emotion: emotion,
                                     reduceMotion: reduceMotion)
        let color = bodyColor ?? Theme.statusColor(status)

        return Canvas { context, size in
            let side = min(size.width, size.height)
            let center = CGPoint(x: size.width / 2 + pose.driftX * side,
                                 y: size.height / 2 + pose.driftY * side)
            // The orb reserves room for its orbit. Object paths already leave an 8% design
            // margin in their 0...100 viewBox and can use the complete square.
            let bodySide = design.isOrb ? side * 0.82 : side
            drawBody(in: &context, center: center, side: bodySide, pose: pose, color: color)

            if pose.showsOrbit {
                drawOrbit(in: &context, center: center, side: side,
                          angle: pose.orbitAngle, color: color)
            }

            if design.isOrb {
                drawOrbEyes(in: &context, center: center, bodySide: bodySide,
                            pose: pose, color: eyeColor ?? Theme.panel)
            } else {
                drawObjectEyes(in: &context, center: center, side: side,
                               pose: pose, color: eyeColor ?? Theme.panel)
            }

            if pose.badgeScale > 0 {
                let badgeRadius = bodySide * 0.115 * pose.badgeScale
                let badgeCenter = CGPoint(x: center.x + bodySide * 0.36,
                                          y: center.y - bodySide * 0.36)
                context.fill(Path(ellipseIn: CGRect(x: badgeCenter.x - badgeRadius - 1,
                                                    y: badgeCenter.y - badgeRadius - 1,
                                                    width: badgeRadius * 2 + 2,
                                                    height: badgeRadius * 2 + 2)),
                             with: .color(Theme.panel))
                context.fill(Path(ellipseIn: CGRect(x: badgeCenter.x - badgeRadius,
                                                    y: badgeCenter.y - badgeRadius,
                                                    width: badgeRadius * 2,
                                                    height: badgeRadius * 2)),
                             with: .color(Theme.avatarBadgeColor(status)))
            }
        }
        .shadow(color: color.opacity(0.42), radius: max(0.8, cell * 0.55))
    }

    private func drawBody(in context: inout GraphicsContext, center: CGPoint,
                          side: CGFloat, pose: OrbFrame, color: Color) {
        if let body = design.bodyPath {
            let scale = side / 100
            let transform = CGAffineTransform(a: scale, b: 0, c: 0,
                                              d: scale * pose.bodyScaleY,
                                              tx: center.x - 50 * scale,
                                              ty: center.y - 50 * scale * pose.bodyScaleY)
            context.fill(Path(body).applying(transform), with: .color(color))
        } else {
            let rect = CGRect(x: center.x - side / 2,
                              y: center.y - side * pose.bodyScaleY / 2,
                              width: side, height: side * pose.bodyScaleY)
            context.fill(Path(ellipseIn: rect), with: .color(color))
        }
    }

    private func drawOrbEyes(in context: inout GraphicsContext, center: CGPoint,
                             bodySide: CGFloat, pose: OrbFrame, color: Color) {
        let radius = bodySide / 2
        for eye in pose.eyes {
            // Bloub builds a capsule at the origin in radius-relative units, then applies the
            // projected tangent matrix. CGAffineTransform has the same a/b/c/d convention as
            // SVG's matrix(), so this is a direct rendering of the upstream geometry.
            let width = max(0.01, eye.width * radius)
            let height = max(0.01, eye.height * radius)
            let rect = CGRect(x: -width / 2, y: -height / 2,
                              width: width, height: height)
            var path = Path(roundedRect: rect, cornerRadius: min(width, height) / 2)
            path = path.applying(CGAffineTransform(
                a: eye.a, b: eye.b, c: eye.c, d: eye.d,
                tx: center.x + eye.x * radius,
                ty: center.y + eye.y * radius
            ))
            context.fill(path, with: .color(color.opacity(eye.alpha)))
        }
    }

    /// Keeps Reef's expressive eye shapes and deterministic gaze while anchoring the pair to the
    /// face location supplied by each object definition. The small shared shift carries the head
    /// turn without letting either eye escape narrow silhouettes.
    private func drawObjectEyes(in context: inout GraphicsContext, center: CGPoint,
                                side: CGFloat, pose: OrbFrame, color: Color) {
        guard !pose.eyes.isEmpty else { return }
        let radius = side / 2
        let unit = side / 100
        let meanX = pose.eyes.reduce(CGFloat.zero) { $0 + $1.x } / CGFloat(pose.eyes.count)
        let meanY = pose.eyes.reduce(CGFloat.zero) { $0 + $1.y } / CGFloat(pose.eyes.count)
        let shift = CGPoint(x: meanX * radius * 0.11, y: meanY * radius * 0.08)

        for (index, eye) in pose.eyes.prefix(2).enumerated() {
            let sideOfPair: CGFloat = index == 0 ? -1 : 1
            let anchor = CGPoint(
                x: center.x + (design.eyes.x + sideOfPair * design.eyeSpacing / 2 - 50) * unit + shift.x,
                y: center.y + (design.eyes.y - 50) * unit * pose.bodyScaleY + shift.y
            )
            // Object definitions use restrained four-unit eyes. Expression width still expands
            // surprised/scared faces, but this factor keeps neutral eyes at that native scale.
            let eyeFactor = 0.52 * design.eyeScale
            let width = max(0.01, eye.width * radius * eyeFactor)
            let height = max(0.01, eye.height * radius * eyeFactor)
            let rect = CGRect(x: -width / 2, y: -height / 2, width: width, height: height)
            var path = Path(roundedRect: rect, cornerRadius: min(width, height) / 2)
            path = path.applying(CGAffineTransform(
                a: eye.a, b: eye.b, c: eye.c, d: eye.d,
                tx: anchor.x, ty: anchor.y
            ))
            context.fill(path, with: .color(color.opacity(eye.alpha)))
        }
    }

    private func drawOrbit(in context: inout GraphicsContext, center: CGPoint,
                           side: CGFloat, angle: Double, color: Color) {
        let radius = side * 0.445
        var back = Path()
        back.addArc(center: center, radius: radius,
                    startAngle: .radians(angle), endAngle: .radians(angle + 2.15),
                    clockwise: false)
        context.stroke(back, with: .color(color.opacity(0.35)),
                       style: StrokeStyle(lineWidth: max(0.8, side * 0.055), lineCap: .round))

        var front = Path()
        front.addArc(center: center, radius: radius,
                     startAngle: .radians(angle + .pi), endAngle: .radians(angle + .pi + 1.25),
                     clockwise: false)
        context.stroke(front, with: .color(color.opacity(0.9)),
                       style: StrokeStyle(lineWidth: max(0.9, side * 0.065), lineCap: .round))
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
