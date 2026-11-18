import Dependencies

/// The app and macOS versions the host runs on. Only the live `HostEnvironmentProviderImpl` reads
/// `ProcessInfo` and `Bundle`; everything else asks this port, so a test hands its subject a fixed value.
public protocol HostEnvironmentProvider: Sendable {
    var info: HostEnvironmentInfo { get }
}

public enum HostEnvironmentProviderKey: TestDependencyKey {
    public static let testValue: any HostEnvironmentProvider = UnimplementedHostEnvironmentProvider()
}

extension DependencyValues {
    public var hostEnvironment: any HostEnvironmentProvider {
        get { self[HostEnvironmentProviderKey.self] }
        set { self[HostEnvironmentProviderKey.self] = newValue }
    }
}

private struct UnimplementedHostEnvironmentProvider: HostEnvironmentProvider {
    var info: HostEnvironmentInfo {
        reportIssue("HostEnvironmentProvider.info not implemented")
        return HostEnvironmentInfo(appVersion: nil, buildNumber: nil, systemVersion: SystemVersion(major: 0, minor: 0, patch: 0))
    }
}
