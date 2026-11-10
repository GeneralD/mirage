import Domain
import Foundation

/// Live `HostEnvironmentProvider`: the macOS version from `ProcessInfo`, and the app's version and build
/// from `Bundle.main`. It reads both on every access, so the value is never stale and nothing is cached.
public struct HostEnvironmentProviderImpl {
    public init() {}
}

extension HostEnvironmentProviderImpl: HostEnvironmentProvider {
    public var info: HostEnvironmentInfo {
        let version = ProcessInfo.processInfo.operatingSystemVersion  // allow-physical: HostEnvironmentProvider
        return HostEnvironmentInfo(
            appVersion: bundleString("CFBundleShortVersionString"),
            buildNumber: bundleString("CFBundleVersion"),
            systemVersion: SystemVersion(major: version.majorVersion, minor: version.minorVersion, patch: version.patchVersion)
        )
    }

    private func bundleString(_ key: String) -> String? {
        Bundle.main.object(forInfoDictionaryKey: key) as? String  // allow-physical: HostEnvironmentProvider
    }
}
