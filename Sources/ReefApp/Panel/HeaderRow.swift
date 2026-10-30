import ReefCore
import SwiftUI

/// The panel's top band: usage on the left when Reef can see it, otherwise what is running;
/// mute and settings on the right. Typography from LAYOUT-SPEC §2.
struct HeaderRow: View {
    let namespace: Namespace.ID
    @Environment(AppState.self) private var app

    var body: some View {
        HStack(spacing: 10) {
            if let usage = app.usage {
                usageBlock(usage)
            } else {
                Text(fallbackTitle)
                    .font(Theme.body.weight(.semibold))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
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
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)
            .help("Settings")
        }
    }

    /// Stale numbers are shown grey, so an old reading never reads as live.
    @ViewBuilder
    private func usageBlock(_ usage: UsageSnapshot) -> some View {
        let stale = usage.isStale()
        HStack(spacing: 6) {
            Image(systemName: "asterisk")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(stale ? Theme.textTertiary : Theme.waiting)
            if let five = usage.fiveHour { window("5h", five, stale: stale) }
            if usage.fiveHour != nil, usage.sevenDay != nil {
                Text("|").font(Theme.headerMono).foregroundStyle(Theme.divider)
            }
            if let seven = usage.sevenDay { window("7d", seven, stale: stale) }
        }
        .help(stale ? "Usage last read \(Format.elapsed(since: usage.capturedAt)) ago" : "Claude Code usage limits")
    }

    @ViewBuilder
    private func window(_ label: String, _ value: UsageWindow, stale: Bool) -> some View {
        HStack(spacing: 4) {
            Text(label)
                .font(Theme.headerMono)
                .foregroundStyle(stale ? Theme.textTertiary : Theme.textPrimary)
            Text("\(value.usedPercent)%")
                .font(Theme.headerMono)
                .foregroundStyle(stale ? Theme.textTertiary : Theme.done)
            if let remaining = value.remaining() {
                Text(remaining)
                    .font(Theme.headerMono)
                    .foregroundStyle(Theme.textTertiary)
            }
        }
    }

    private var fallbackTitle: String {
        let sessions = app.visibleSessions
        if sessions.isEmpty { return "No agent sessions" }
        if sessions.count == 1, let project = sessions[0].project { return project }
        return "\(sessions.count) sessions"
    }
}
