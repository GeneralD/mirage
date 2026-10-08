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

    /// Never returns: the extension lives until the system kills it.
    public func run() -> Never {
        let relay = relay
        let errorLog = errorLog
        let developerLog = developerLog
        Task {
            developerLog.record(.app, "relay starting")
            do {
                try await relay.run(descriptor: .hd720, frameRate: .standard)
                developerLog.record(.app, "relay ended")
            } catch {
                errorLog.record(.app, "relay failed: \(error)")
            }
        }
        CFRunLoopRun()
        exit(0)
    }
}

/// Named by `NSExtensionPrincipalClass` in the generated Info.plist. The CMIO
/// extension point requires the key; the provider itself is started from
/// `run()` through the stream-output gateway.
@objc(ExtensionPrincipal)
public final class ExtensionPrincipal: NSObject {}
