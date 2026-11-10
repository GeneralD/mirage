import Domain
import Foundation
import Testing

@testable import HostEnvironment

@Suite("HostEnvironmentProviderImpl")
struct HostEnvironmentProviderImplTests {
    private let provider = HostEnvironmentProviderImpl()

    @Test("systemVersion matches the three components of ProcessInfo.processInfo.operatingSystemVersion")
    func systemVersionMatchesProcessInfo() {
        let version = ProcessInfo.processInfo.operatingSystemVersion

        #expect(
            provider.info.systemVersion
                == SystemVersion(major: version.majorVersion, minor: version.minorVersion, patch: version.patchVersion)
        )
    }

    @Test("systemVersion.major is 14 or more, the lowest macOS the package supports")
    func systemVersionMajorIsAtLeastPackageMinimum() {
        #expect(provider.info.systemVersion.major >= 14)
    }

    @Test("appVersion and buildNumber are the CFBundleShortVersionString and CFBundleVersion of Bundle.main, or nil when absent")
    func appVersionAndBuildNumberAreBundleValues() {
        #expect(provider.info.appVersion == Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String)
        #expect(provider.info.buildNumber == Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String)
    }
}
