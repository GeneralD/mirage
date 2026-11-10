/// The macOS version the host runs on, as the three numbers `ProcessInfo.operatingSystemVersion` reports.
public struct SystemVersion: Sendable, Hashable {
    public let major: Int
    public let minor: Int
    public let patch: Int

    public init(major: Int, minor: Int, patch: Int) {
        self.major = major
        self.minor = minor
        self.patch = patch
    }
}

/// What the host reports about itself: the app's version and build from its bundle, and the macOS version.
/// `appVersion` and `buildNumber` are `nil` when the bundle does not carry them.
public struct HostEnvironmentInfo: Sendable, Hashable {
    public let appVersion: String?
    public let buildNumber: String?
    public let systemVersion: SystemVersion

    public init(appVersion: String?, buildNumber: String?, systemVersion: SystemVersion) {
        self.appVersion = appVersion
        self.buildNumber = buildNumber
        self.systemVersion = systemVersion
    }
}
