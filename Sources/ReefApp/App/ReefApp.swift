import AppKit
import ReefCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var state: AppState!
    private var notchController: NotchWindowController!
    private var mouseMonitor: MouseMonitor!

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
        state.onStateChanged = { [weak self] in self?.notchController.refresh() }
        state.start()
        notchController.show()
        mouseMonitor.start()
        Log.info("app", "launched", ["version": Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev"])
    }

    func applicationWillTerminate(_ notification: Notification) {
        state.stop()
        Log.info("app", "terminated")
    }
}
