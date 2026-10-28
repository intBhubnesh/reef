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
        return NotchGeometry(notchRect: notch, pillRect: pill, panelRect: panel)
    }
}
