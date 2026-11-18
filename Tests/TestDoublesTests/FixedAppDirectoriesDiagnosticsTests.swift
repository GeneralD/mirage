import Domain
import TestDoubles
import Testing

@Suite("FixedAppDirectories diagnostics")
struct FixedAppDirectoriesDiagnosticsTests {
    @Test("the diagnostics folder is Diagnostics in the host bundle id's folder under the base")
    func diagnosticsDirectoryIsUnderTheBase() {
        let directories = FixedAppDirectories(applicationSupportDirectory: "/base")
        #expect(directories.diagnosticsDirectory == "/base/\(ProductIdentity.hostBundleID)/Diagnostics")
    }

    @Test("the diagnostics folder and the effects folder are siblings")
    func diagnosticsDirectoryIsSiblingOfEffects() {
        let directories = FixedAppDirectories()
        #expect(directories.diagnosticsDirectory != directories.effectsDirectory)
        #expect(directories.diagnosticsDirectory.split(separator: "/").dropLast() == directories.effectsDirectory.split(separator: "/").dropLast())
    }
}
