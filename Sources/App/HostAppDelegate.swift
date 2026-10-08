import AppKit
import Dependencies
import Domain

/// Lifecycle glue: launch the camera interactor when AppKit is ready, shut it
/// down on termination. The status item exists only so the user can quit an
/// app that has no window.
final class HostAppDelegate: NSObject, NSApplicationDelegate {
    @Dependency(\.cameraInteractor) private var cameraInteractor
    @Dependency(\.developerLog) private var developerLog

    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let launch = LaunchHandle()

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem.button?.title = "◉"
        statusItem.menu = quitMenu
        launch.start { [cameraInteractor, developerLog] in
            let report = await cameraInteractor.launch(descriptor: .hd720, frameRate: .standard)
            developerLog.record(.app, "launch finished: \(report)")
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        launch.cancel()
        cameraInteractor.shutDown()
    }

    private var quitMenu: NSMenu {
        let menu = NSMenu()
        menu.addItem(withTitle: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        return menu
    }
}

/// Owns the one unstructured task of the host process (the launch sequence)
/// so termination can cancel it. Main-actor confined by its callers.
@MainActor
private final class LaunchHandle {
    private var task: Task<Void, Never>?

    nonisolated init() {}

    func start(_ body: @escaping @Sendable () async -> Void) {
        task?.cancel()
        task = Task(operation: body)
    }

    func cancel() {
        task?.cancel()
        task = nil
    }
}
