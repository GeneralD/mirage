/// Live `WorkspaceGateway`: hands a path to `NSWorkspace`, which shows a folder in Finder.
/// Wraps AppKit. Thin by rule and coverage-ignored: opening Finder is a side effect CI
/// cannot observe, so there is no smoke; whether the folder exists is decided above.
import AppKit
import Domain

public struct WorkspaceGatewayImpl: WorkspaceGateway {
    public init() {}

    public func open(_ path: String) {
        NSWorkspace.shared.open(URL(fileURLWithPath: path))
    }
}
