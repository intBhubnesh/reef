import XCTest
@testable import ReefCore

final class JumpPlannerTests: XCTestCase {
    func testKittyPlan() {
        let t = TerminalIdentity(tty: "/dev/ttys003", bundleID: "net.kovidgoyal.kitty", termProgram: "kitty",
                                 kittyWindowID: 7, kittyPID: 99, kittyListenOn: "unix:/tmp/kitty-99", tmuxPane: "%3")
        XCTAssertEqual(JumpPlanner.plan(t, cwd: "/p"), [
            .kittyFocusWindow(id: 7, listenOn: "unix:/tmp/kitty-99"),
            .tmuxSelectPane("%3"),
            .activateApp(bundleID: "net.kovidgoyal.kitty"),
        ])
    }

    func testGhosttyPlanUsesMarker() {
        let t = TerminalIdentity(tty: "/dev/ttys004", bundleID: "com.mitchellh.ghostty", termProgram: "ghostty", ghosttyMarker: "reef:abcdefgh")
        XCTAssertEqual(JumpPlanner.plan(t, cwd: nil), [
            .ghosttyFocusByTitleMarker("reef:abcdefgh"),
            .activateApp(bundleID: "com.mitchellh.ghostty"),
        ])
    }

    func testGhosttyWithoutMarkerFallsBackToActivate() {
        let t = TerminalIdentity(tty: "/dev/ttys004", bundleID: "com.mitchellh.ghostty", termProgram: "ghostty")
        XCTAssertEqual(JumpPlanner.plan(t, cwd: nil), [.activateApp(bundleID: "com.mitchellh.ghostty")])
    }

    func testVSCodePlan() {
        let t = TerminalIdentity(tty: "/dev/ttys005", bundleID: "com.microsoft.VSCode", termProgram: "vscode", vscodePID: 123)
        XCTAssertEqual(JumpPlanner.plan(t, cwd: "/Users/x/proj"), [
            .vscodeOpen(cwd: "/Users/x/proj"),
            .activateApp(bundleID: "com.microsoft.VSCode"),
        ])
    }

    func testHeadlessPlanIsEmpty() {
        XCTAssertEqual(JumpPlanner.plan(TerminalIdentity(), cwd: "/p"), [])
    }

    func testUnknownTerminalActivatesApp() {
        let t = TerminalIdentity(tty: "/dev/ttys006", bundleID: "com.example.term")
        XCTAssertEqual(JumpPlanner.plan(t, cwd: "/p"), [.activateApp(bundleID: "com.example.term")])
    }
}
