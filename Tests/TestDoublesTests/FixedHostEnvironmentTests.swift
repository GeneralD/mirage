import Domain
import TestDoubles
import Testing

@Suite("FixedHostEnvironment")
struct FixedHostEnvironmentTests {
    @Test("FixedHostEnvironment(info:) returns the info it was given")
    func infoIsTheOneGiven() {
        let info = HostEnvironmentInfo(appVersion: "2.3.4", buildNumber: "99", systemVersion: SystemVersion(major: 13, minor: 2, patch: 1))
        #expect(FixedHostEnvironment(info: info).info == info)
    }

    @Test("FixedHostEnvironment(systemMajor: 15) returns macOS 15.0.0")
    func systemMajorReturnsZeroMinorAndPatch() {
        #expect(FixedHostEnvironment(systemMajor: 15).info.systemVersion == SystemVersion(major: 15, minor: 0, patch: 0))
    }
}
