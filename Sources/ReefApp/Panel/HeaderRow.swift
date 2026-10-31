import ReefCore
import SwiftUI

/// The panel's top band. Left: the account's rate-limit windows. Right: the model the focused
/// agent is running and the limit that model draws on. Then mute and settings.
/// Typography and spacing from LAYOUT-SPEC §2.
struct HeaderRow: View {
    let namespace: Namespace.ID
    @Environment(AppState.self) private var app
    @State private var hoveringUsage = false

    var body: some View {
        HStack(spacing: 0) {
            if let usage = app.usage {
                usageBlock(usage)
            } else {
                Text(fallbackTitle)
                    .font(Theme.body.weight(.semibold))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 12)

            if let usage = app.usage, let model = modelLabel(usage) {
                modelBlock(model, usage: usage)
                    .padding(.trailing, Metrics.headerModelGap - Metrics.headerMuteSize / 2)
            }

            Button { app.muted.toggle() } label: {
                Image(systemName: app.muted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                    .font(.system(size: Metrics.headerMuteSize, weight: .semibold))
                    .foregroundStyle(app.muted ? Theme.waiting : Theme.textPrimary)
                    .frame(width: Metrics.headerControlGap, height: Metrics.headerHeight)
            }
            .buttonStyle(.plain)
            .help(app.muted ? "Unmute sounds" : "Mute sounds")

            Button { app.openSettings() } label: {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: Metrics.headerGearSize, weight: .semibold))
                    .foregroundStyle(Theme.textBody)
                    .frame(width: Metrics.headerGearSize + 10, height: Metrics.headerHeight)
            }
            .buttonStyle(.plain)
            .help("Settings")
        }
    }

    // MARK: - Left block

    @ViewBuilder
    private func usageBlock(_ usage: UsageSnapshot) -> some View {
        let stale = usage.isStale()
        HStack(spacing: Metrics.headerIconGap) {
            RoundedRectangle(cornerRadius: Metrics.headerIconSize * 0.42, style: .continuous)
                .fill(stale ? Theme.textTertiary : Theme.waiting)
                .frame(width: Metrics.headerIconSize, height: Metrics.headerIconSize)
                .overlay(
                    Image(systemName: "sparkle")
                        .font(.system(size: Metrics.headerIconSize * 0.62, weight: .bold))
                        .foregroundStyle(.white)
                )
            if let five = usage.fiveHour { window("5h", five, stale: stale) }
            if usage.fiveHour != nil, usage.sevenDay != nil {
                Rectangle()
                    .fill(Theme.divider)
                    .frame(width: 1, height: Metrics.headerHighlightHeight - 4)
                    .padding(.horizontal, Metrics.headerDividerGap)
            }
            if let seven = usage.sevenDay { window("7d", seven, stale: stale) }
        }
        .padding(.horizontal, Metrics.headerHighlightPadding)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: Metrics.headerHighlightRadius, style: .continuous)
                .fill(hoveringUsage ? Theme.headerHighlight : .clear)
        )
        .onHover { hoveringUsage = $0 }
        .help(stale ? "Usage last read \(Format.elapsed(since: usage.capturedAt)) ago"
                    : "Claude Code rate limits for this account")
    }

    @ViewBuilder
    private func window(_ label: String, _ value: UsageWindow, stale: Bool) -> some View {
        HStack(spacing: Metrics.headerWordGap) {
            Text(label)
                .font(Theme.headerMono)
                .foregroundStyle(stale ? Theme.textTertiary : Theme.textPrimary)
            Text("\(value.usedPercent)%")
                .font(Theme.headerMono)
                .foregroundStyle(stale ? Theme.textTertiary : Theme.done)
            if let remaining = value.remaining() {
                Text(remaining)
                    .font(Theme.headerMonoRegular)
                    .foregroundStyle(Theme.textTertiary)
            }
        }
    }

    // MARK: - Right block

    /// The model the focused agent is running. Falls back to the newest session's model id when
    /// the status-line cache has not reported one.
    private func modelLabel(_ usage: UsageSnapshot) -> String? {
        if let name = usage.modelName { return name }
        guard let session = app.visibleSessions.last, let model = session.model else { return nil }
        return Self.shortModelName(model)
    }

    /// "claude-opus-5-5" reads badly in a 90 pt block; "Opus" does.
    static func shortModelName(_ id: String) -> String {
        let known = ["fable", "opus", "sonnet", "haiku", "gpt", "codex"]
        let parts = id.split(whereSeparator: { $0 == "-" || $0 == "." || $0 == "/" })
        if let match = parts.first(where: { known.contains($0.lowercased()) }) {
            return match.capitalized
        }
        return parts.first.map(String.init)?.capitalized ?? id
    }

    @ViewBuilder
    private func modelBlock(_ model: String, usage: UsageSnapshot) -> some View {
        let stale = usage.isStale()
        HStack(spacing: Metrics.headerWordGap) {
            Text(model)
                .font(Theme.headerMono)
                .foregroundStyle(stale ? Theme.textTertiary : Theme.textPrimary)
                .lineLimit(1)
            if let window = usage.modelWindow {
                Text("\(window.usedPercent)%")
                    .font(Theme.headerMono)
                    .foregroundStyle(stale ? Theme.textTertiary : Theme.done)
                if let remaining = window.remaining() {
                    Text(remaining)
                        .font(Theme.headerMonoRegular)
                        .foregroundStyle(Theme.textTertiary)
                }
            }
        }
        .help(usage.spendLimit != nil
              ? "\(model) · spend limit for this account"
              : "\(model) · the weekly window this model draws on")
    }

    private var fallbackTitle: String {
        let sessions = app.visibleSessions
        if sessions.isEmpty { return "No agent sessions" }
        if sessions.count == 1, let project = sessions[0].project { return project }
        return "\(sessions.count) sessions"
    }
}
