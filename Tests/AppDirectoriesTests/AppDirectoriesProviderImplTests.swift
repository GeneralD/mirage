import Domain
import Foundation
import Testing

@testable import AppDirectories

@Suite("AppDirectoriesProviderImpl")
struct AppDirectoriesProviderImplTests {
    private let provider = AppDirectoriesProviderImpl()

    @Test("the base directory is the user's Application Support folder, and no folder of the app's own")
    func applicationSupportDirectory() throws {
        let applicationSupport = try #require(FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first)
        let path = provider.applicationSupportDirectory

        #expect(path == applicationSupport.path)
        #expect(URL(fileURLWithPath: path).lastPathComponent == "Application Support")
    }

    @Test("the path is a plain path: absolute, no trailing slash, the same on every read")
    func applicationSupportDirectoryIsStable() {
        let path = provider.applicationSupportDirectory

        #expect(path.hasPrefix("/"))
        #expect(!path.hasSuffix("/"))
        #expect(provider.applicationSupportDirectory == path)
    }
}
