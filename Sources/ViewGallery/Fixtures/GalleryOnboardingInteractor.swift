import Combine
import Domain

/// The `OnboardingInteractor` the gallery's onboarding window draws from: `install` publishes the status it was made with, at
/// once and to every subscriber, and its commands do nothing. The two one-shot actions answer fixed results, the approval request
/// is accepted and the support log is saved at a fixed path, so a screen shows each outcome without the Camera Extension or the
/// file system. It is not a test double (`Sources` may not use `TestDoubles`), and no shipped product links this module.
struct GalleryOnboardingInteractor {
    /// The status `install` publishes. It cannot be called `install`, the name the protocol gives the publisher.
    let installStatus: InstallStatus

    init(install: InstallStatus) {
        installStatus = install
    }
}

extension GalleryOnboardingInteractor: OnboardingInteractor {
    var install: AnyPublisher<InstallStatus, Never> {
        Just(installStatus).eraseToAnyPublisher()
    }

    func start() {}

    func stop() {}

    func openApprovalSettings(_ pane: SystemSettingsPane) async -> Bool {
        true
    }

    func exportSupportLog(_ context: SupportReportContext) async -> SupportLogExportOutcome {
        .saved(path: "/Users/example/Library/Application Support/Diagnostics/support-log.txt", lineCount: 120, logError: nil)
    }
}

/// The `HostEnvironmentProvider` the gallery's onboarding window draws from: the given macOS major version with minor and patch 0,
/// app version `1.0.0` and build `1`, so no `ProcessInfo` or `Bundle` is read.
struct GalleryHostEnvironment: HostEnvironmentProvider {
    let systemMajor: Int

    var info: HostEnvironmentInfo {
        HostEnvironmentInfo(
            appVersion: "1.0.0",
            buildNumber: "1",
            systemVersion: SystemVersion(major: systemMajor, minor: 0, patch: 0)
        )
    }
}
