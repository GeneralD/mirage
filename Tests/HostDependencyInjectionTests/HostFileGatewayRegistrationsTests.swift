import AppDirectories
import Dependencies
import Domain
import FileSystemGateway
import FileWatchGateway
import Testing
import WorkspaceGateway

/// The host registers the live of each OS-boundary port the effect catalog stands on (epic #42,
/// D10, #44): the file system, the file events, Finder and the effects folder's path. They resolve
/// no port of their own, so what each captures does not depend on which test builds it first.
/// Every resolution happens inside `withDependencies { $0.context = .live }`, and none is overridden.
@Suite("Host registrations of the file gateways", .timeLimit(.minutes(1)))
struct HostFileGatewayRegistrationsTests {
    @Test("each file-side port has the live value of its module")
    func everyPortHasItsLive() {
        withDependencies {
            $0.context = .live
        } operation: {
            @Dependency(\.fileSystemGateway) var fileSystemGateway
            @Dependency(\.fileWatchGateway) var fileWatchGateway
            @Dependency(\.workspaceGateway) var workspaceGateway
            @Dependency(\.appDirectories) var appDirectories

            #expect(fileSystemGateway is FileSystemGatewayImpl)
            #expect(fileWatchGateway is FileWatchGatewayImpl)
            #expect(workspaceGateway is WorkspaceGatewayImpl)
            #expect(appDirectories is AppDirectoriesProviderImpl)
        }
    }
}
