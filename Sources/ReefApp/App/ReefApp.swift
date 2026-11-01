import AppKit
import ReefCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var state: AppState!
    private var notchController: NotchWindowController!
    private var mouseMonitor: MouseMonitor!
    private var settingsController: SettingsWindowController!
    private var hookWatcher: HookWatcher!
    private var hotkeys: GlobalHotkeys!
    private var animation: AnimationSettings!

    private var termSource: DispatchSourceSignal?

    func applicationDidFinishLaunching(_ notification: Notification) {
        Paths.ensureDirectories()
        signal(SIGTERM, SIG_IGN)
        termSource = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
        termSource?.setEventHandler { NSApp.terminate(nil) }
        termSource?.resume()
        state = AppState()
        notchController = NotchWindowController(state: state)
        mouseMonitor = MouseMonitor(state: state, controller: notchController)
        settingsController = SettingsWindowController(state: state)
        state.onStateChanged = { [weak self] in self?.notchController.refresh() }
        state.onSettingsChanged = { [weak self] in self?.notchController.relayout() }
        state.onOpenSettings = { [weak self] in self?.settingsController.show() }
        hookWatcher = HookWatcher(installedSources: { [weak self] in self?.state.installedHookSources ?? [] },
                                  onHealed: { [weak self] source in
                                      self?.state.showNotice("Restored \(source == .claude ? "Claude Code" : "Codex") hooks that had been removed.")
                                  })
        // Shortcuts only fire while the pointer is over the expanded panel: keystrokes aimed at another app
        // (esc in vim, ⌃A in a shell) must never become approvals.
        hotkeys = GlobalHotkeys(isActive: { [weak self] in
                                    guard let controller = self?.notchController, controller.isExpanded else { return false }
                                    return controller.panelScreenRect.contains(NSEvent.mouseLocation)
                                },
                                perform: { [weak self] shortcut in self?.state.perform(shortcut) })
        animation = AnimationSettings()
        animation.onChange = { [weak self] value in self?.state.reduceMotion = value }
        state.reduceMotion = animation.reduceMotion
        installMenu()
        let scenario = ProcessInfo.processInfo.arguments
            .first(where: { $0.hasPrefix("--reef-scenario=") })?
            .split(separator: "=", maxSplits: 1).last.map(String.init)
        state.start(backgroundServices: scenario == nil)
        if let scenario {
            state.loadHarnessScenario(scenario)
        }
        notchController.show()
        state.loadBarkCredential()
        if let scenario,
           let path = ProcessInfo.processInfo.arguments
            .first(where: { $0.hasPrefix("--reef-snapshot-path=") })?
            .split(separator: "=", maxSplits: 1).last.map(String.init),
           let data = state.harnessSnapshotData(scenario: scenario) {
            try? data.write(to: URL(fileURLWithPath: path), options: .atomic)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { NSApp.terminate(nil) }
        }
        // Deterministic smoke-test entry point. It exercises the real Settings controller after
        // launch without requiring Accessibility permission for synthetic clicks or keystrokes.
        if ProcessInfo.processInfo.arguments.contains("--open-display-settings") {
            DispatchQueue.main.async { [weak self] in self?.settingsController.show(tab: .display) }
        } else if ProcessInfo.processInfo.arguments.contains("--open-settings") {
            DispatchQueue.main.async { [weak self] in self?.settingsController.show() }
        }
        mouseMonitor.start()
        if scenario == nil {
            hookWatcher.start()
            hotkeys.start()
        }
        // Accessibility can be granted while running; pick the tap up when it is.
        Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.hotkeys.start() }
        }
        Log.info("app", "launched", ["version": Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev"])
    }

    /// A minimal main menu so ⌘, and ⌘Q work while a Reef window is key.
    private func installMenu() {
        let main = NSMenu()
        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit Reef", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        main.addItem(appItem)
        let editItem = NSMenuItem()
        let edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = edit
        main.addItem(editItem)
        NSApp.mainMenu = main
    }

    @MainActor @objc private func openSettings() { settingsController.show() }

    func applicationWillTerminate(_ notification: Notification) {
        state.stop()
        Log.info("app", "terminated")
    }
}
