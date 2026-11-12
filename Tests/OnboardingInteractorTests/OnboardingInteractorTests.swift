import Combine
import Dependencies
import Domain
import OnboardingInteractor
import TestDoubles
import TestSupport
import Testing

@Suite("OnboardingInteractorImpl", .timeLimit(.minutes(1)))
struct OnboardingInteractorTests {
    @Test("install publishes nothing before start, and the UseCase's updates is not asked for")
    func nothingBeforeStart() {
        let rig = InteractorRig(status: .installing)
        let seen = Collector<InstallStatus>()
        let subscription = rig.subject.install.sink { seen.append($0) }

        #expect(seen.count == 0)
        #expect(rig.useCase.updateRequests.count == 0, "nothing observes the UseCase until start")
        withExtendedLifetime(subscription) {}
    }

    @Test("start publishes the current status first, then each later transition in order")
    func startPublishesCurrentThenTransitions() async {
        let rig = InteractorRig(status: .installing)
        let seen = Collector<InstallStatus>()
        let subscription = rig.subject.install.sink { seen.append($0) }

        rig.subject.start()
        await seen.waitForCount(1)  // the first status arrives only once the observation is registered
        rig.useCase.publish(.needsApproval)
        await seen.waitForCount(2)
        rig.useCase.publish(.installed)
        await seen.waitForCount(3)

        #expect(seen.values == [.installing, .needsApproval, .installed])
        withExtendedLifetime(subscription) {}
    }

    @Test("observation goes on after a terminal status, and the next transition still arrives")
    func observationContinuesAfterTerminalStatus() async {
        let rig = InteractorRig(status: .installing)
        let seen = Collector<InstallStatus>()
        let subscription = rig.subject.install.sink { seen.append($0) }

        rig.subject.start()
        await seen.waitForCount(1)
        rig.useCase.publish(.failed(.denied))
        await seen.waitForCount(2)
        rig.useCase.publish(.installed)
        await seen.waitForCount(3)

        #expect(seen.values == [.installing, .failed(.denied), .installed])
        #expect(rig.useCase.updateTerminations.count == 0, "the terminal status did not end the observation")
        withExtendedLifetime(subscription) {}
    }

    @Test("a second start ends the first observation before the next begins, so exactly one stays alive")
    func restartKeepsOneObservation() async {
        let rig = InteractorRig(status: .installing)
        let seen = Collector<InstallStatus>()
        let subscription = rig.subject.install.sink { seen.append($0) }

        rig.subject.start()
        await seen.waitForCount(1)
        rig.subject.start()
        await rig.useCase.updateRequests.waitForCount(2)
        await rig.useCase.updateTerminations.waitForCount(1)
        await seen.waitForCount(2)  // the second observation's first status: it is registered
        rig.useCase.publish(.needsApproval)
        await seen.waitForCount(3)

        #expect(rig.useCase.updateRequests.count == 2)
        #expect(rig.useCase.updateTerminations.count == 1, "the first observation ended")
        #expect(seen.values == [.installing, .installing, .needsApproval], "one observation forwards the change, not two")
        withExtendedLifetime(subscription) {}
    }

    @Test("after stop, a transition the UseCase makes does not reach install")
    func transitionAfterStopIsNotForwarded() async {
        let rig = InteractorRig(status: .installing)
        let seen = Collector<InstallStatus>()
        let subscription = rig.subject.install.sink { seen.append($0) }

        rig.subject.start()
        await seen.waitForCount(1)
        rig.subject.stop()
        await rig.useCase.updateTerminations.waitForCount(1)
        rig.useCase.publish(.installed)

        #expect(seen.values == [.installing], "the observation was gone before the transition, so nothing forwarded it")
        withExtendedLifetime(subscription) {}
    }

    @Test("start after stop resumes from the current status, not from the last one forwarded")
    func restartAfterStopResumesFromCurrentStatus() async {
        let rig = InteractorRig(status: .installing)
        let seen = Collector<InstallStatus>()
        let subscription = rig.subject.install.sink { seen.append($0) }

        rig.subject.start()
        await seen.waitForCount(1)
        rig.subject.stop()
        await rig.useCase.updateTerminations.waitForCount(1)
        rig.useCase.publish(.installed)
        rig.subject.start()
        await seen.waitForCount(2)

        #expect(seen.values == [.installing, .installed])
        withExtendedLifetime(subscription) {}
    }

    @Test("an Interactor that is let go ends the observation it owned")
    func releaseEndsTheObservation() async {
        let useCase = FakeExtensionInstallUseCase()
        var subject: OnboardingInteractorImpl? = InteractorRig.make(useCase: useCase)

        subject?.start()
        await useCase.updateRequests.waitForCount(1)
        subject = nil

        await useCase.updateTerminations.waitForCount(1)
    }

    @Test("openApprovalSettings hands the pane to the UseCase and returns its true or false answer")
    func openApprovalSettingsReturnsUseCaseAnswer() async {
        let accepting = InteractorRig(opensSettings: true)
        let refusing = InteractorRig(opensSettings: false)

        #expect(await accepting.subject.openApprovalSettings(.privacyAndSecurity) == true)
        #expect(await refusing.subject.openApprovalSettings(.loginItemsAndExtensions) == false)
        #expect(accepting.useCase.openedPanes.values == [.privacyAndSecurity])
        #expect(refusing.useCase.openedPanes.values == [.loginItemsAndExtensions])
    }

    @Test("exportSupportLog hands the context to the UseCase and returns its saved or failed answer")
    func exportSupportLogReturnsUseCaseAnswer() async {
        let context = SupportReportContext(install: .installed, effectStatus: "compile failed", compilerMessage: "error: unknown type")
        let saved = SupportLogExportOutcome.saved(path: "/fake/support-log.txt", lineCount: 3, logError: nil)
        let failed = SupportLogExportOutcome.failed(description: "disk full")
        let savingRig = InteractorRig(exportOutcome: saved)
        let failingRig = InteractorRig(exportOutcome: failed)

        #expect(await savingRig.subject.exportSupportLog(context) == saved)
        #expect(await failingRig.subject.exportSupportLog(context) == failed)
        #expect(savingRig.supportLog.contexts.values == [context])
        #expect(failingRig.supportLog.contexts.values == [context])
    }

    @Test("openApprovalSettings and exportSupportLog work without start, and begin no observation")
    func actionsWorkWithoutStart() async {
        let rig = InteractorRig()

        #expect(await rig.subject.openApprovalSettings(.privacyAndSecurity) == true)
        #expect(
            await rig.subject.exportSupportLog(SupportReportContext(install: .notInstalled))
                == .saved(path: "/fake/support-log.txt", lineCount: 0, logError: nil))
        #expect(rig.useCase.updateRequests.count == 0, "neither action asks the UseCase for updates")
    }
}

/// An Interactor over a `FakeExtensionInstallUseCase` and a `FakeSupportLogUseCase`, built inside
/// `withDependencies` (the subject captures the dependencies of the scope it is made in).
private struct InteractorRig {
    let useCase: FakeExtensionInstallUseCase
    let supportLog: FakeSupportLogUseCase
    let subject: OnboardingInteractorImpl

    init(
        status: InstallStatus = .notInstalled,
        opensSettings: Bool = true,
        exportOutcome: SupportLogExportOutcome = .saved(path: "/fake/support-log.txt", lineCount: 0, logError: nil)
    ) {
        useCase = FakeExtensionInstallUseCase(status: status, opensSettings: opensSettings)
        supportLog = FakeSupportLogUseCase(outcome: exportOutcome)
        subject = Self.make(useCase: useCase, supportLog: supportLog)
    }

    static func make(useCase: FakeExtensionInstallUseCase, supportLog: FakeSupportLogUseCase = FakeSupportLogUseCase()) -> OnboardingInteractorImpl {
        withDependencies {
            $0.extensionInstallUseCase = useCase
            $0.supportLogUseCase = supportLog
        } operation: {
            OnboardingInteractorImpl()
        }
    }
}
