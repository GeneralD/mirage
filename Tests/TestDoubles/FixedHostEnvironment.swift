import Domain

/// `HostEnvironmentProvider` with the info the test gives, so no `ProcessInfo` or `Bundle` is ever read.
public struct FixedHostEnvironment: HostEnvironmentProvider, Sendable {
    public let info: HostEnvironmentInfo

    public init(info: HostEnvironmentInfo) {
        self.info = info
    }

    /// The given macOS major version, with minor and patch 0, app version `1.0.0` and build `1`.
    public init(systemMajor: Int) {
        info = HostEnvironmentInfo(
            appVersion: "1.0.0",
            buildNumber: "1",
            systemVersion: SystemVersion(major: systemMajor, minor: 0, patch: 0)
        )
    }
}
