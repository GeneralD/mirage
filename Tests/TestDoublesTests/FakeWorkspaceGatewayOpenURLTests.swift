import Domain
import TestDoubles
import TestSupport
import Testing

@Suite("FakeWorkspaceGateway openURL")
struct FakeWorkspaceGatewayOpenURLTests {
    @Test("openURL records each URL string in order and answers true by default")
    func openURLIsRecordedAndAccepted() {
        let workspace = FakeWorkspaceGateway()
        #expect(workspace.openURL("x-apple.systempreferences:com.apple.preference.security"))
        #expect(workspace.openURL("https://example.com/effects"))
        #expect(workspace.openedURLs.values == ["x-apple.systempreferences:com.apple.preference.security", "https://example.com/effects"])
    }

    @Test("a fake made with opensURLs false records the URL and answers false")
    func refusedURLIsRecordedAndRefused() {
        let workspace = FakeWorkspaceGateway(opensURLs: false)
        #expect(!workspace.openURL("https://example.com/effects"))
        #expect(workspace.openedURLs.values == ["https://example.com/effects"])
    }

    @Test("a URL is not recorded as a path, and a path is not recorded as a URL")
    func urlAndPathRecordsStayApart() {
        let workspace = FakeWorkspaceGateway()
        workspace.open("/effects")
        #expect(workspace.openURL("https://example.com/effects"))
        #expect(workspace.opened.values == ["/effects"])
        #expect(workspace.openedURLs.values == ["https://example.com/effects"])
    }
}
