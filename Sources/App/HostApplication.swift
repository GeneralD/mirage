import AppKit
import Dependencies
import Domain
import HostDependencyInjection

/// The host process entry point behind `Apps/Host/main.swift`: an accessory
/// (menu-bar) application whose whole M0 job is to run the launch sequence
/// and expose a way to quit. The menu-bar UI proper arrives with MVP-A.
public struct HostApplication {
    public init() {}

    /// Runs the AppKit main loop; returns when the application terminates.
    @MainActor
    public func run() {
        let application = NSApplication.shared
        let delegate = HostAppDelegate()
        application.delegate = delegate
        application.setActivationPolicy(.accessory)
        application.run()
        withExtendedLifetime(delegate) {}
    }
}
