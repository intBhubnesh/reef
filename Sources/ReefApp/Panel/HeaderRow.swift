import SwiftUI

struct HeaderRow: View {
    @Environment(AppState.self) private var app

    var body: some View {
        HStack(spacing: 10) {
            Text(title)
                .font(Theme.body.weight(.semibold))
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(1)
            Spacer()
            Button { app.muted.toggle() } label: {
                Image(systemName: app.muted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(app.muted ? Theme.waiting : Theme.textPrimary)
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)
            .help(app.muted ? "Unmute sounds" : "Mute sounds")
            Button { app.openSettings() } label: {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)
            .help("Settings")
        }
    }

    private var title: String {
        let sessions = app.visibleSessions
        if sessions.isEmpty { return "No agent sessions" }
        if sessions.count == 1, let project = sessions[0].project { return project }
        return "\(sessions.count) sessions"
    }
}
