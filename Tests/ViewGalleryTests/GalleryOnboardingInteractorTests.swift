import Combine
import Domain
import TestSupport
import Testing

@testable import ViewGallery

@Suite("GalleryOnboardingInteractor")
struct GalleryOnboardingInteractorTests {
    private func installs(of interactor: GalleryOnboardingInteractor) -> [InstallStatus] {
        let received = Collector<InstallStatus>()
        let subscription = interactor.install.sink { received.append($0) }
        withExtendedLifetime(subscription) {}
        return received.values
    }

    @Test("every subscription gets the install status it was made with, at once")
    func publishesTheInstallStatus() {
        let interactor = GalleryOnboardingInteractor(install: .needsApproval)

        #expect(installs(of: interactor) == [.needsApproval])
        #expect(installs(of: interactor) == [.needsApproval])
    }

    @Test("start and stop change nothing: a subscription after them gets the same status")
    func startAndStopChangeNothing() {
        let interactor = GalleryOnboardingInteractor(install: .installed)

        interactor.start()
        interactor.stop()

        #expect(installs(of: interactor) == [.installed])
    }

    @Test("openApprovalSettings answers true")
    func openApprovalSettingsAnswersTrue() async {
        let interactor = GalleryOnboardingInteractor(install: .needsApproval)

        let opened = await interactor.openApprovalSettings(.privacyAndSecurity)

        #expect(opened)
    }

    @Test("exportSupportLog saves nothing and answers the fixed saved outcome")
    func exportSupportLogAnswersSaved() async {
        let interactor = GalleryOnboardingInteractor(install: .notInstalled)

        let outcome = await interactor.exportSupportLog(SupportReportContext(install: .notInstalled))

        #expect(
            outcome
                == .saved(
                    path: "/Users/example/Library/Application Support/Diagnostics/support-log.txt",
                    lineCount: 120,
                    logError: nil
                ))
    }

    @Test("GalleryHostEnvironment reports app version 1.0.0, build 1 and the given macOS major with minor and patch 0")
    func hostEnvironmentInfoIsFixed() {
        let info = GalleryHostEnvironment(systemMajor: 14).info

        #expect(info.appVersion == "1.0.0")
        #expect(info.buildNumber == "1")
        #expect(info.systemVersion == SystemVersion(major: 14, minor: 0, patch: 0))
    }
}
