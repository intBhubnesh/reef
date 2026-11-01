import AppKit
import SwiftUI

enum SettingsTab: String, CaseIterable, Identifiable {
    case general, integrations, notifications, display, shortcuts, about
    var id: String { rawValue }

    var title: String { rawValue.capitalized }
    var symbol: String {
        switch self {
        case .general: return "gearshape.fill"
        case .integrations: return "puzzlepiece.extension.fill"
        case .notifications: return "bell.fill"
        case .display: return "textformat.size"
        case .shortcuts: return "keyboard.fill"
        case .about: return "info.circle.fill"
        }
    }
    var color: Color {
        switch self {
        case .general: return .gray
        case .integrations: return .blue
        case .notifications: return .red
        case .display: return .indigo
        case .shortcuts: return .purple
        case .about: return .cyan
        }
    }
}

@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    private let state: AppState

    init(state: AppState) {
        self.state = state
        super.init()
    }

    var isVisible: Bool { window?.isVisible == true }

    func show(tab: SettingsTab = .general) {
        if window == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 620, height: 680),
                             styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
                             backing: .buffered, defer: false)
            w.title = "Reef Settings"
            w.titlebarAppearsTransparent = true
            w.isReleasedWhenClosed = false
            // Reef is an accessory app with no Dock icon. A normal-level settings window falls
            // behind the user's editor as soon as focus changes and becomes effectively
            // unreachable. Keep this utility above normal app windows without putting it above
            // alerts or system UI.
            w.level = .floating
            w.hidesOnDeactivate = false
            w.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
            w.delegate = self
            w.center()
            w.contentView = NSHostingView(rootView: SettingsRootView(initialTab: tab).environment(state))
            window = w
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
        window?.orderFrontRegardless()
        Log.info("ui", "settings shown", ["level": "floating"])
    }

    func windowWillClose(_ notification: Notification) {
        Log.info("ui", "settings closed")
    }
}

struct SettingsRootView: View {
    @State private var tab: SettingsTab

    init(initialTab: SettingsTab = .general) {
        _tab = State(initialValue: initialTab)
    }

    var body: some View {
        NavigationSplitView {
            List(SettingsTab.allCases, selection: $tab) { item in
                Label {
                    Text(item.title)
                } icon: {
                    Image(systemName: item.symbol)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 22, height: 22)
                        .background(item.color, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                }
                .tag(item)
            }
            .navigationSplitViewColumnWidth(170)
            .listStyle(.sidebar)
        } detail: {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    HStack(spacing: 8) {
                        Image(systemName: tab.symbol).foregroundStyle(.white).font(.system(size: 12, weight: .bold))
                            .frame(width: 24, height: 24).background(tab.color, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                        Text(tab.title).font(.title2.weight(.semibold))
                    }
                    switch tab {
                    case .general: GeneralTab()
                    case .integrations: IntegrationsTab()
                    case .notifications: NotificationsTab()
                    case .display: DisplayTab()
                    case .shortcuts: ShortcutsTab()
                    case .about: AboutTab()
                    }
                }
                .padding(24)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(minWidth: 620, minHeight: 500)
    }
}

/// Grouped rows in the style of macOS System Settings.
struct SettingsGroup<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.headline)
            VStack(spacing: 0) { content }
                .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(Color.primary.opacity(0.08)))
        }
    }
}

struct SettingsRow<Content: View>: View {
    let title: String
    var subtitle: String? = nil
    @ViewBuilder let content: Content

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                if let subtitle { Text(subtitle).font(.caption).foregroundStyle(.secondary) }
            }
            Spacer()
            content
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .overlay(alignment: .bottom) { Divider().padding(.leading, 14) }
    }
}
