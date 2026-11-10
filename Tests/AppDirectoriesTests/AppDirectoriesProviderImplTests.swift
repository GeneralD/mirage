import Domain
import Foundation
import Testing

@testable import AppDirectories

@Suite("AppDirectoriesProviderImpl")
struct AppDirectoriesProviderImplTests {
    private let provider = AppDirectoriesProviderImpl()

    @Test("the effects folder is Effects, in the host bundle id's folder, in Application Support")
    func effectsDirectoryIsUnderApplicationSupport() throws {
        let applicationSupport = try #require(FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first)
        let path = provider.effectsDirectory

        #expect(path == applicationSupport.appendingPathComponent(ProductIdentity.hostBundleID).appendingPathComponent("Effects").path)
        #expect(URL(fileURLWithPath: path).pathComponents.suffix(3) == ["Application Support", ProductIdentity.hostBundleID, "Effects"])
    }

    @Test("the path is a plain path: absolute, no trailing slash, the same on every read")
    func effectsDirectoryIsStable() {
        let path = provider.effectsDirectory

        #expect(path.hasPrefix("/"))
        #expect(!path.hasSuffix("/"))
        #expect(provider.effectsDirectory == path)
    }

    @Test("the diagnostics folder is Diagnostics, in the host bundle id's folder, in Application Support")
    func diagnosticsDirectoryIsUnderApplicationSupport() throws {
        let applicationSupport = try #require(FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first)
        let path = provider.diagnosticsDirectory

        #expect(path == applicationSupport.appendingPathComponent(ProductIdentity.hostBundleID).appendingPathComponent("Diagnostics").path)
        #expect(URL(fileURLWithPath: path).pathComponents.suffix(3) == ["Application Support", ProductIdentity.hostBundleID, "Diagnostics"])
    }

    @Test("the diagnostics folder and the effects folder are different folders under the same parent")
    func diagnosticsDirectoryIsSiblingOfEffectsDirectory() {
        let diagnostics = URL(fileURLWithPath: provider.diagnosticsDirectory)
        let effects = URL(fileURLWithPath: provider.effectsDirectory)

        #expect(diagnostics.deletingLastPathComponent() == effects.deletingLastPathComponent())
        #expect(provider.diagnosticsDirectory != provider.effectsDirectory)
    }

    @Test("the diagnostics path is a plain path: absolute, no trailing slash, the same on every read")
    func diagnosticsDirectoryIsStable() {
        let path = provider.diagnosticsDirectory

        #expect(path.hasPrefix("/"))
        #expect(!path.hasSuffix("/"))
        #expect(provider.diagnosticsDirectory == path)
    }
}
