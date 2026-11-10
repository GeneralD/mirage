import Domain
import TestDoubles
import Testing

@Suite("FixedAppDirectories diagnostics")
struct FixedAppDirectoriesDiagnosticsTests {
    @Test("FixedAppDirectories answers the diagnostics directory it was given")
    func diagnosticsDirectoryIsTheOneGiven() {
        let directories = FixedAppDirectories(effectsDirectory: "/support/app/Effects", diagnosticsDirectory: "/support/app/Diagnostics")
        #expect(directories.diagnosticsDirectory == "/support/app/Diagnostics")
    }

    @Test("FixedAppDirectories answers /diagnostics for the diagnostics directory when none is given")
    func diagnosticsDirectoryDefaultsToDiagnostics() {
        #expect(FixedAppDirectories(effectsDirectory: "/support/app/Effects").diagnosticsDirectory == "/diagnostics")
    }
}
