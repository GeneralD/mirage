import AppKit
import AppRouter
import Dependencies
import Domain

/// Lifecycle glue, untested by design: when AppKit is ready, start the menu's Router and
/// launch the camera interactor; on termination, stop both. The Router is built with the
/// delegate, so the scene (`HostApplication`) can draw the menu from its Presenter before
/// anything starts; the entry lane starts and stops the Router and nothing below it (the
/// Presenter owns the effect Interactor's lifecycle).
@MainActor
final class HostAppDelegate: NSObject, NSApplicationDelegate {
    @Dependency(\.cameraInteractor) private var cameraInteractor
    @Dependency(\.developerLog) private var developerLog

    let router = AppRouter()
    private let launch = LaunchHandle()

    func applicationDidFinishLaunching(_ notification: Notification) {
        router.start()
        launch.start { [cameraInteractor, developerLog] in
            let report = await cameraInteractor.launch(descriptor: .hd720, frameRate: .standard)
            developerLog.record(.app, "launch finished: \(report)")
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        launch.cancel()
        router.stop()
        cameraInteractor.shutDown()
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
