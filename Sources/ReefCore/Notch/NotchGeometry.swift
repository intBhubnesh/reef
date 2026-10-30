import CoreGraphics
import Foundation

/// Island frames in top-left-origin screen points, derived from the display's notch (or a synthetic one).
public struct NotchGeometry: Equatable {
    public static let syntheticNotch = CGSize(width: 185, height: 33)
    public static let minimumHeight: CGFloat = 33
    public static let screenMargin: CGFloat = 16

    public let notchRect: CGRect
    public let pillRect: CGRect
    public let panelRect: CGRect
    /// Needed to keep the overshoot headroom on screen.
    public let screenSize: CGSize

    public static func compute(screen: CGRect, safeTop: CGFloat, auxLeft: CGRect?, auxRight: CGRect?,
                               panelMax: CGSize = CGSize(width: 648, height: 580), sidePadding: CGFloat = 32) -> NotchGeometry {
        let notch: CGRect
        if safeTop > 0, let auxLeft, let auxRight, auxRight.minX > auxLeft.maxX {
            notch = CGRect(x: auxLeft.maxX - screen.minX, y: 0, width: auxRight.minX - auxLeft.maxX, height: safeTop)
        } else {
            notch = CGRect(x: (screen.width - syntheticNotch.width) / 2, y: 0,
                           width: syntheticNotch.width, height: syntheticNotch.height)
        }
        let pill = CGRect(x: notch.minX - sidePadding, y: 0, width: notch.width + sidePadding * 2,
                          height: max(notch.height, minimumHeight))
        let panelWidth = min(panelMax.width, screen.width - screenMargin * 2)
        let panelHeight = min(panelMax.height, screen.height - screenMargin)
        let panel = CGRect(x: notch.midX - panelWidth / 2, y: 0, width: panelWidth, height: panelHeight)
        return NotchGeometry(notchRect: notch, pillRect: pill, panelRect: panel, screenSize: screen.size)
    }

    /// The window the panel is drawn into. The expansion overshoots by about 1.3 %, so the
    /// window carries slack on the sides and bottom; without it the bounce would be clipped.
    /// Always kept inside the screen.
    public func windowRect(expanded: Bool) -> CGRect {
        guard expanded else { return pillRect }
        let slack = Motion.overshootHeadroom
        var rect = CGRect(x: panelRect.minX - slack, y: panelRect.minY,
                          width: panelRect.width + slack * 2, height: panelRect.height + slack)
        if rect.minX < 0 { rect.origin.x = 0 }
        if rect.maxX > screenSize.width { rect.origin.x = max(0, screenSize.width - rect.width) }
        rect.size.width = min(rect.width, screenSize.width)
        rect.size.height = min(rect.height, screenSize.height - rect.minY)
        return rect
    }
}
