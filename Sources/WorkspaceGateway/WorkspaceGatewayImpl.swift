/// Live `WorkspaceGateway`: hands a path or a URL string to `NSWorkspace`, which shows a
/// folder in Finder or opens a URL in the app registered for it.
/// Wraps AppKit. Thin by rule and coverage-ignored: opening Finder or System Settings is a
/// side effect CI cannot observe, so there is no smoke; which URL is opened is decided above.
import AppKit
import Domain

public struct WorkspaceGatewayImpl: WorkspaceGateway {
    public init() {}

    public func open(_ path: String) {
        NSWorkspace.shared.open(URL(fileURLWithPath: path))
    }

    public func openURL(_ url: String) -> Bool {
        URL(string: url).map { NSWorkspace.shared.open($0) } ?? false
    }
}
