import Domain
import TestSupport

/// `WorkspaceGateway` that opens nothing: `opened` records the paths it was asked to
/// open, in order, so "Open Effects Folder…" is asserted without a Finder window.
public final class FakeWorkspaceGateway: WorkspaceGateway, Sendable {
    public let opened = Collector<String>()

    public init() {}

    public func open(_ path: String) {
        opened.append(path)
    }
}
