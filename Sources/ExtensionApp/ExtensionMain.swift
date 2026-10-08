import Dependencies
import Domain
import ExtensionDependencyInjection
import Foundation

/// The Camera Extension entry point behind `Apps/CameraExtension/main.swift`:
/// starts the relay (which declares the CMIO stream and begins receiving host
/// frames) and parks the main thread in the run loop the CMIO provider needs.
public struct ExtensionMain {
    @Dependency(\.extensionRelayUseCase) private var relay
    @Dependency(\.errorLog) private var errorLog
    @Dependency(\.developerLog) private var developerLog

    public init() {}

    /// Never returns on its own: the extension lives until the system kills it,
    /// or until the relay ends, which is not something this process can recover
    /// from. A process parked in the run loop without a relay would answer the
    /// system's launch of the camera with no frames, forever; exiting lets the
    /// system start a fresh instance the next time a client opens the camera.
    public func run() -> Never {
        let relay = relay
        let errorLog = errorLog
        let developerLog = developerLog
        Task {
            developerLog.record(.app, "relay starting")
            do {
                try await relay.run(descriptor: .hd720, frameRate: .standard)
                errorLog.record(.app, "relay ended; exiting so the system can relaunch the extension")
            } catch {
                errorLog.record(.app, "relay failed: \(error); exiting so the system can relaunch the extension")
            }
            exit(EXIT_FAILURE)
        }
        CFRunLoopRun()
        exit(EXIT_SUCCESS)
    }
}

/// Named by `NSExtensionPrincipalClass` in the generated Info.plist. The CMIO
/// extension point requires the key; the provider itself is started from
/// `run()` through the stream-output gateway.
@objc(ExtensionPrincipal)
public final class ExtensionPrincipal: NSObject {}
