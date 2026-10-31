import ReefCore
import SwiftUI

/// The island outline: flush with the top edge, rounded only at the bottom corners, with small
/// outward "ears" at the top so it visually merges with the physical notch.
struct NotchShape: Shape {
    var bottomRadius: CGFloat
    var topRadius: CGFloat = 6

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(bottomRadius, topRadius) }
        set { bottomRadius = newValue.first; topRadius = newValue.second }
    }

    func path(in rect: CGRect) -> Path {
        var p = Path()
        let r = min(bottomRadius, rect.height / 2, rect.width / 2)
        let t = min(topRadius, r)
        p.move(to: CGPoint(x: rect.minX - t, y: rect.minY))
        p.addQuadCurve(to: CGPoint(x: rect.minX, y: rect.minY + t), control: CGPoint(x: rect.minX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY - r))
        p.addQuadCurve(to: CGPoint(x: rect.minX + r, y: rect.maxY), control: CGPoint(x: rect.minX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.maxX - r, y: rect.maxY))
        p.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.maxY - r), control: CGPoint(x: rect.maxX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + t))
        p.addQuadCurve(to: CGPoint(x: rect.maxX + t, y: rect.minY), control: CGPoint(x: rect.maxX, y: rect.minY))
        p.closeSubpath()
        return p
    }
}

/// The island silhouette at a point between pill and panel, used as the mask that gives the
/// expansion its shape. `openness` is the animatable value: a shape's `animatableData` is
/// interpolated frame by frame, which an animated frame inside a mask is not, so this is what
/// makes the spring visible at all. Past 1 is the spring's overshoot.
struct IslandMask: Shape {
    var openness: Double
    var pill: CGSize
    var rest: CGSize
    var topRadius: CGFloat = 6

    var animatableData: Double {
        get { openness }
        set { openness = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let width = pill.width + (rest.width - pill.width) * openness
        let height = pill.height + (rest.height - pill.height) * openness
        let radius = Metrics.pillBottomRadius + (Metrics.panelBottomRadius - Metrics.pillBottomRadius) * openness
        // Centred on the notch and flush with the top edge: the island only ever grows downward.
        let box = CGRect(x: rect.midX - width / 2, y: rect.minY, width: width, height: height)
        return NotchShape(bottomRadius: radius, topRadius: topRadius).path(in: box)
    }
}
