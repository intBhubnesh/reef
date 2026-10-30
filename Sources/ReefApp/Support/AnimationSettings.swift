import AppKit
import Combine
import ReefCore
import SwiftUI

/// Watches the system's "reduce motion" preference so stepped animation and springs can be
/// switched off without restarting the app.
@MainActor
final class AnimationSettings {
    private(set) var reduceMotion: Bool
    private var observer: NSObjectProtocol?
    var onChange: ((Bool) -> Void)?

    init() {
        reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            let value = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
            Task { @MainActor in
                guard let self, value != self.reduceMotion else { return }
                self.reduceMotion = value
                self.onChange?(value)
            }
        }
    }
}

extension NotchTransition {
    /// The SwiftUI animation for this transition, or a short fade when the system asks for
    /// reduced motion.
    func animation(reduceMotion: Bool) -> Animation {
        if reduceMotion { return .easeOut(duration: Motion.reducedFade) }
        if self == .snap { return .linear(duration: 0) }
        return .spring(response: response, dampingFraction: damping).delay(delay)
    }

    /// The content fade that follows the frame change.
    func reveal(reduceMotion: Bool, row: Bool) -> Animation {
        if reduceMotion { return .easeOut(duration: Motion.reducedFade) }
        let duration = row ? rowRevealDuration : revealDuration
        let delay = row ? rowRevealDelay : revealDelay
        return .easeOut(duration: duration).delay(self.delay + delay)
    }
}
