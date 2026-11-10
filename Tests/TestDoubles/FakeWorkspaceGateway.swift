import Domain
import TestSupport

/// `WorkspaceGateway` that opens nothing: `opened` records the paths it was asked to
/// open, in order, so "Open Effects Folder…" is asserted without a Finder window.
/// `openedURLs` records the URL strings passed to `openURL(_:)`, which answers
/// `opensURLs`, so the accepted and the refused case are both asserted.
public final class FakeWorkspaceGateway: WorkspaceGateway, Sendable {
    public let opened = Collector<String>()
    public let openedURLs = Collector<String>()
    private let opensURLs: Bool

    public init(opensURLs: Bool = true) {
        self.opensURLs = opensURLs
    }

    public func open(_ path: String) {
        opened.append(path)
    }

    public func openURL(_ url: String) -> Bool {
        openedURLs.append(url)
        return opensURLs
    }
}
