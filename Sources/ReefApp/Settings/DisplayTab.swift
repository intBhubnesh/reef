import ReefCore
import SwiftUI

struct DisplayTab: View {
    @Environment(AppState.self) private var app
    @State private var previewStart = Date()

    private let emotionColumns = Array(repeating: GridItem(.flexible(), spacing: 10), count: 4)

    var body: some View {
        @Bindable var app = app
        SettingsGroup(title: "Preview") {
            HStack {
                Spacer()
                PillPreview(phaseStart: previewStart)
                Spacer()
            }
            .padding(.vertical, 16)
            .background(Color(nsColor: .windowBackgroundColor))
        }
        SettingsGroup(title: "All Bloub emotions") {
            LazyVGrid(columns: emotionColumns, spacing: 10) {
                ForEach(AvatarEmotion.allCases) { emotion in
                    emotionTile(emotion)
                }
            }
            .padding(12)
        }
        SettingsGroup(title: "Agent status mapping") {
            VStack(spacing: 0) {
                ForEach(AvatarStatusSlot.allCases) { slot in
                    statusMappingRow(slot)
                }
            }
        }
        SettingsGroup(title: "Panel size") {
            SettingsRow(title: "Display", subtitle: displaySubtitle) {
                Picker("", selection: $app.settings.preferredDisplayID) {
                    ForEach(OverlayDisplayResolver.options(preferredID: app.settings.preferredDisplayID)) { option in
                        Text(option.title).tag(option.id)
                    }
                }
                .labelsHidden()
                .frame(width: 235)
            }
            SettingsRow(title: "Max panel width", subtitle: "\(Int(app.settings.panelMaxWidth)) pt") {
                Slider(value: $app.settings.panelMaxWidth, in: 400...900, step: 8).frame(width: 220)
            }
            SettingsRow(title: "Max panel height", subtitle: "\(Int(app.settings.panelMaxHeight)) pt") {
                Slider(value: $app.settings.panelMaxHeight, in: 300...900, step: 10).frame(width: 220)
            }
        }
        SettingsGroup(title: "Session card") {
            SettingsRow(title: "Show project name") {
                Toggle("", isOn: $app.settings.showProject).labelsHidden().toggleStyle(.switch)
            }
            SettingsRow(title: "Show git branch") {
                Toggle("", isOn: $app.settings.showBranch).labelsHidden().toggleStyle(.switch)
            }
            SettingsRow(title: "Show subagents", subtitle: "List child agents under their session.") {
                Toggle("", isOn: $app.settings.showSubagents).labelsHidden().toggleStyle(.switch)
            }
        }
    }

    private var displaySubtitle: String {
        app.settings.preferredDisplayID == OverlayDisplayOption.automaticID
            ? "Uses the built-in notch when available."
            : "The selection is remembered across disconnects."
    }

    private func statusMappingRow(_ slot: AvatarStatusSlot) -> some View {
        HStack(spacing: 10) {
            CharacterSprite(
                status: slot.sampleStatus,
                seed: UInt64(100 + AvatarStatusSlot.allCases.firstIndex(of: slot)!),
                phaseStart: previewStart,
                cell: 4,
                reduceMotion: app.reduceMotion,
                emotion: app.avatarEmotion(for: slot)
            )
            VStack(alignment: .leading, spacing: 1) {
                Text(slot.title)
                Text(statusColorName(slot.sampleStatus))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Picker("", selection: Binding(
                get: { app.avatarEmotion(for: slot) },
                set: { app.setAvatarEmotion($0, for: slot) }
            )) {
                ForEach(AvatarEmotion.allCases) { emotion in
                    Text(emotion.title).tag(emotion)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .frame(width: 145)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .overlay(alignment: .bottom) { Divider().padding(.leading, 14) }
    }

    private func emotionTile(_ emotion: AvatarEmotion) -> some View {
        VStack(spacing: 6) {
            CharacterSprite(
                status: .idle,
                seed: UInt64(AvatarEmotion.allCases.firstIndex(of: emotion)! + 1),
                phaseStart: previewStart,
                cell: 7,
                reduceMotion: app.reduceMotion,
                emotion: emotion,
                bodyColor: .black,
                eyeColor: .white
            )
            Text(emotion.title)
                .font(.caption)
                .foregroundStyle(.black.opacity(0.72))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, minHeight: 80)
        .padding(.vertical, 7)
        .background(Color.white.opacity(0.94), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
    }

    private func statusColorName(_ status: SessionStatus) -> String {
        switch status {
        case .idle, .done: return "Green"
        case .working, .runningTool, .compacting: return "Orange"
        case .waitingForApproval, .waitingForQuestion, .waitingForPlan: return "Blue"
        case .failed: return "Red"
        }
    }
}

/// A live pill showing the four primary avatar states in the Display tab.
struct PillPreview: View {
    @Environment(AppState.self) private var app
    let phaseStart: Date

    var body: some View {
        HStack(spacing: 0) {
            HStack(spacing: Metrics.pillSpriteGap) {
                previewAvatar(.idle, seed: 1, help: "Idea")
                previewAvatar(.working, seed: 2, help: "Working")
                previewAvatar(.waitingForQuestion, seed: 3, help: "Question")
                previewAvatar(.done, seed: 4, help: "Done")
            }
            .padding(.leading, 12)
            Spacer(minLength: 8)
            HStack(spacing: 6) {
                Circle().fill(Theme.waiting).frame(width: 6, height: 6)
                Text("4").font(.system(size: 13, weight: .semibold).monospacedDigit()).foregroundStyle(.white)
            }
            .padding(.trailing, 12)
        }
        .frame(width: 249, height: 33)
        .background(NotchShape(bottomRadius: Metrics.pillBottomRadius).fill(Theme.panel))
    }

    private func previewAvatar(_ status: SessionStatus, seed: UInt64, help: String) -> some View {
        CharacterSprite(status: status, seed: seed, phaseStart: phaseStart,
                        cell: Metrics.pillSpriteSize / CGFloat(Metrics.spriteColumns),
                        reduceMotion: app.reduceMotion,
                        emotion: AvatarStatusSlot.emotion(
                            for: status,
                            mapping: app.settings.avatarEmotionByStatus
                        ))
            .help(help)
    }
}
