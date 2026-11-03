import ReefCore
import SwiftUI

/// Convenience wrapper so call sites can pass a `Session` and get a correctly sized,
/// correctly phased character.
struct SessionSprite: View {
    @Environment(AppState.self) private var app
    let session: Session
    var cell: CGFloat

    var body: some View {
        CharacterSprite(status: session.status,
                        seed: session.animationSeed,
                        phaseStart: session.animationPhaseStart,
                        cell: cell,
                        reduceMotion: app.reduceMotion,
                        emotion: AvatarStatusSlot.emotion(
                            for: session.status,
                            mapping: app.settings.avatarEmotionByStatus
                        ),
                        design: AvatarDesign.resolve(app.settings.avatarDesignID))
    }
}
