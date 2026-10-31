import CoreGraphics
import Foundation

/// Every animation timing, measured from screen recordings of the reference app.
/// `M<n>` cites a row of `_reference/vibe-island/motion/MOTION-SPEC.md`.
/// These are the contract: views read them and never hard-code a duration.
public enum Motion {
    // Hover and expansion
    /// M2: expansion starts 150 ms after the pointer enters the pill.
    public static let hoverDwell: TimeInterval = 0.15
    /// M2: ~300 ms to target with ~1.3 % overshoot, settled by ~580 ms.
    public static let expandResponse: TimeInterval = 0.35
    public static let expandDamping: Double = 0.78
    /// M1: the pill itself scales slightly the moment the pointer arrives.
    public static let pillHoverScale: CGFloat = 1.02
    public static let pillHoverDuration: TimeInterval = 0.13

    // Collapse
    /// M7: 93 % done by 300 ms, tail to ~600 ms, no overshoot.
    public static let collapseResponse: TimeInterval = 0.45
    public static let collapseDamping: Double = 1.0
    /// Extra wait before the window shrinks, so the collapse tail is never clipped.
    public static let windowShrinkExtra: TimeInterval = 0.10

    // Automatic reveals
    /// M6: the pill swaps instantly, the panel follows within ~50 ms.
    public static let requestExpandDelay: TimeInterval = 0.05
    /// M8: the completion peek opens ~0.9–1.3 s after the previous collapse began.
    public static let peekDelay: TimeInterval = 1.1
    /// M9: the peek holds exactly 5 s, restarting when the pointer leaves.
    public static let peekHold: TimeInterval = 5.0

    // Staged content reveal
    /// M3: header text fades in place shortly after a hover expansion starts.
    public static let headerFadeDelay: TimeInterval = 0.15
    public static let headerFadeDuration: TimeInterval = 0.12
    /// M4: rows follow, drifting down slightly as they fade.
    public static let rowFadeDelay: TimeInterval = 0.12
    public static let rowFadeDuration: TimeInterval = 0.17
    public static let rowDrift: CGFloat = 5
    /// M3: automatic expansions reveal their content immediately.
    public static let autoRevealFadeDelay: TimeInterval = 0.0
    public static let autoRevealFadeDuration: TimeInterval = 0.05

    // Sprite
    /// M12: a new frame every 150 ms, eight steps to the cycle.
    public static let spriteFramePeriod: TimeInterval = 0.15
    public static let spriteCycleFrames: Int = 8
    /// M14: while waiting, the eyes jump on an irregular schedule around this median.
    public static let waitEyeMedianGap: TimeInterval = 0.20
    public static let waitEyeMinGap: TimeInterval = 0.08
    public static let waitEyeMaxGap: TimeInterval = 0.38
    /// M15: the attention glyph bobs one cell, 300 ms up and 580 ms down.
    public static let bobUp: TimeInterval = 0.30
    public static let bobDown: TimeInterval = 0.58
    /// M16: a 300 ms blink every 2.4 s once the turn is done.
    public static let blinkClosed: TimeInterval = 0.30
    public static let blinkPeriod: TimeInterval = 2.4
    /// M17: the cursor glyph first lights ~750 ms into the peek, then 780 on / 450 off.
    public static let cursorFirstOn: TimeInterval = 0.75
    public static let cursorOn: TimeInterval = 0.78
    public static let cursorOff: TimeInterval = 0.45

    // Accessibility and window sizing
    /// Replaces every spring when the system asks for reduced motion.
    public static let reducedFade: TimeInterval = 0.12
    /// Slack around the panel so the expansion's overshoot is never clipped by the window.
    public static let overshootHeadroom: CGFloat = 24
}

/// Panel and pill measurements in points, from `_reference/vibe-island/motion/LAYOUT-SPEC.md`
/// (`L<n>` cites a section). Radii were re-measured directly from the reference screenshots.
public enum Metrics {
    /// L1: 1296 px ÷ 2, confirmed by measuring `permission/still-request.png`.
    public static let panelWidth: CGFloat = 648
    /// L2: the black band across the top of the panel.
    public static let headerHeight: CGFloat = 36
    /// L1: the column cards occupy inside the panel.
    public static let contentWidth: CGFloat = 640
    /// L1: vertical rhythm between blocks, and the leading used for stacked text.
    public static let blockGap: CGFloat = 16
    public static let textLeading: CGFloat = 18
    /// L1: the panel ends this far below the last card.
    public static let bottomInset: CGFloat = 20

    /// Measured on `permission/still-request.png`: the bottom-left edge moves in 35 px
    /// over the last 16 rows, i.e. ≈17.5 pt. MOTION guessed 24 pt, LAYOUT 40 pt.
    public static let panelBottomRadius: CGFloat = 18
    /// Measured on `screenshots/collapsed.png`: 24 px inset over the last 13 rows, ≈12 pt.
    /// MOTION guessed 11 pt, LAYOUT 22 pt.
    public static let pillBottomRadius: CGFloat = 11
    /// Both shapes flare outwards at the top so they merge with the physical notch.
    public static let topFlare: CGFloat = 6

    // Cards (L3, L5, L6)
    public static let cardRadius: CGFloat = 10
    public static let cardPadding: CGFloat = 12
    public static let bannerWidth: CGFloat = 623.5
    public static let bannerHeight: CGFloat = 61.5
    public static let bannerIconSize: CGFloat = 26
    public static let subagentBoxInset: CGFloat = 8

    // Header (L2)
    /// Gap between the usage icon and the first label.
    public static let headerIconGap: CGFloat = 6
    /// Gap between words inside a usage group ("5h" "21%" "3h9m").
    public static let headerWordGap: CGFloat = 5
    /// Space either side of the `|` divider.
    public static let headerDividerGap: CGFloat = 4
    public static let headerIconSize: CGFloat = 12
    public static let headerMuteSize: CGFloat = 13
    public static let headerGearSize: CGFloat = 14
    /// Centre to centre between the mute and gear glyphs.
    public static let headerControlGap: CGFloat = 30
    /// Gap between the model block and the mute glyph.
    public static let headerModelGap: CGFloat = 22
    /// The hover highlight behind the usage block.
    public static let headerHighlightHeight: CGFloat = 22
    public static let headerHighlightRadius: CGFloat = 5
    public static let headerHighlightPadding: CGFloat = 5

    // Session row (L4)
    public static let chipHeight: CGFloat = 15
    /// Horizontal padding inside a chip.
    public static let chipPadding: CGFloat = 5
    /// Gap between the character and its action glyph.
    public static let spriteGlyphGap: CGFloat = 4
    public static let chipGap: CGFloat = 6.5
    public static let rightInset: CGFloat = 21
    public static let textColumn: CGFloat = 69.5
    public static let rowSpriteWidth: CGFloat = 20
    public static let rowSpriteHeight: CGFloat = 15
    public static let statusDotSize: CGFloat = 7

    // Pill (L8)
    public static let pillSpriteSize: CGFloat = 16
    public static let pillSpriteGap: CGFloat = 5
    public static let pillSideInset: CGFloat = 10.5

    /// The character glyph is drawn on an 8 × 6 cell grid.
    public static let spriteColumns: Int = 8
    public static let spriteRows: Int = 6
}
