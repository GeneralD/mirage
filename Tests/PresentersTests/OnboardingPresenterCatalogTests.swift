import Combine
import Domain
import TestDoubles
import TestSupport
import Testing

@testable import Presenters

/// The chosen effect's status line and the compiler's message on the onboarding window (#226), read from the
/// catalog. The install status is covered by `OnboardingPresenterTests`.
@MainActor
@Suite("OnboardingPresenterCatalog", .timeLimit(.minutes(1)))
struct OnboardingPresenterCatalogTests {
    private let ripple = EffectCatalogEntry.fixture(.bundled("Ripple"))

    /// A catalog that has chosen `Ripple`, with `outcome` and `compilerMessage` as given.
    private func catalog(_ outcome: EffectSelectionOutcome?, compilerMessage: String? = nil) -> EffectCatalogState {
        .fixture([ripple], outcome: outcome, compilerMessage: compilerMessage)
    }

    // MARK: - Status and message

    @Test("before start the status and the message are nil, and the window has no message block")
    func quietBeforeStart() {
        let rig = OnboardingPresenterRig(catalog: catalog(.failed(.compileFailed), compilerMessage: "error: unknown type"))

        #expect(rig.presenter.effectStatus == nil)
        #expect(rig.presenter.compilerMessage == nil)
        #expect(rig.presenter.geometry.messageHeight == 0)
    }

    @Test("a failed attempt shows the chosen effect's status line and the compiler's message, trimmed")
    func failureShowsStatusAndMessage() async {
        let rig = OnboardingPresenterRig(catalog: catalog(.failed(.compileFailed), compilerMessage: "  error: unknown type 'half3x4'\n"))

        await rig.start()
        await settle(rig.presenter.$effectStatus) { $0 != nil }

        #expect(rig.presenter.effectStatus == "Ripple: compile failed")
        #expect(rig.presenter.compilerMessage == "error: unknown type 'half3x4'")
    }

    @Test("a failed attempt with no compiler message shows the status line and no message")
    func failureWithoutMessageShowsStatusOnly() async {
        let rig = OnboardingPresenterRig(catalog: catalog(.failed(.compileFailed)))

        await rig.start()
        await settle(rig.presenter.$effectStatus) { $0 != nil }

        #expect(rig.presenter.effectStatus == "Ripple: compile failed")
        #expect(rig.presenter.compilerMessage == nil)
    }

    @Test("the next attempt that succeeds clears both the status line and the message")
    func successClearsBoth() async {
        let rig = OnboardingPresenterRig(catalog: catalog(.failed(.compileFailed), compilerMessage: "error: x"))
        await rig.start()
        await settle(rig.presenter.$effectStatus) { $0 != nil }

        rig.effects.publish(catalog(.prepared))
        await settle(rig.presenter.$effectStatus) { $0 == nil }

        #expect(rig.presenter.compilerMessage == nil)
    }

    @Test("a compiler message longer than 2000 scalars is cut with an ellipsis, and a blank one is no message")
    func longAndBlankMessages() async {
        let rig = OnboardingPresenterRig(catalog: catalog(.failed(.compileFailed), compilerMessage: String(repeating: "a", count: 2500)))
        await rig.start()
        await settle(rig.presenter.$compilerMessage) { $0 != nil }

        #expect(rig.presenter.compilerMessage == String(repeating: "a", count: 2000) + "…")

        rig.effects.publish(catalog(.failed(.compileFailed), compilerMessage: " \n\t "))
        await settle(rig.presenter.$compilerMessage) { $0 == nil }

        #expect(rig.presenter.compilerMessage == nil)
    }

    @Test("the message block is 0 high with no message and 61 high for a three-line message")
    func geometryFollowsTheMessage() async {
        let rig = OnboardingPresenterRig(catalog: catalog(.failed(.compileFailed), compilerMessage: "error: a\nerror: b\nerror: c"))
        await rig.start()
        await settle(rig.presenter.$compilerMessage) { $0 != nil }

        // Three lines of 15 points, and 8 points of padding above and below.
        #expect(rig.presenter.geometry.messageHeight == 3 * 15 + 2 * 8)

        rig.effects.publish(catalog(.failed(.compileFailed)))
        await settle(rig.presenter.$compilerMessage) { $0 == nil }

        #expect(rig.presenter.geometry.messageHeight == 0)
    }

    // MARK: - Lifecycle

    @Test("a state that was on its way when stop was called is never applied, and the window keeps what it showed")
    func stopDropsTheStateOnItsWay() async {
        let rig = OnboardingPresenterRig(catalog: catalog(.prepared))
        await rig.start()
        await drainMainActor()

        // The test holds the main actor from the publish to stop(), so the task that applies states has not run:
        // the failure is on its way when stop() lands.
        rig.effects.publish(catalog(.failed(.compileFailed), compilerMessage: "error: x"))
        rig.presenter.stop()
        await drainMainActor()

        #expect(rig.presenter.effectStatus == nil, "the status stayed as it was before stop")
        #expect(rig.presenter.compilerMessage == nil)
    }

    @Test("stop cancels the catalog subscription, so a state sent after it is never applied")
    func stopCancelsTheSubscription() async {
        let rig = OnboardingPresenterRig(catalog: catalog(.prepared))
        await rig.start()
        #expect(rig.effects.cancellations.count == 0)

        rig.presenter.stop()
        #expect(rig.effects.cancellations.count == 1, "the catalog subscription was cancelled")

        rig.effects.publish(catalog(.failed(.compileFailed), compilerMessage: "error: x"))
        await drainMainActor()

        #expect(rig.presenter.effectStatus == nil)
        #expect(rig.presenter.compilerMessage == nil)
    }

    @Test("start and stop neither start nor stop the EffectInteractor, which the menu's Presenter owns")
    func effectInteractorIsOnlyObserved() async {
        let rig = OnboardingPresenterRig()

        await rig.start()
        #expect(rig.effects.starts.count == 0)

        rig.presenter.stop()
        #expect(rig.effects.stops.count == 0)
        #expect(rig.interactor.starts.count == 1)
        #expect(rig.interactor.stops.count == 1)
    }

    @Test("a started Presenter that is let go cancels the catalog subscription and leaves the EffectInteractor alone")
    func letGoWhileStartedCancelsTheSubscription() {
        let effects = SpyEffectInteractor(FakeEffectInteractor(state: catalog(.prepared)))
        var presenter: OnboardingPresenter? = makeOnboardingPresenter(over: FakeOnboardingInteractor(), effects: effects)
        presenter?.start()
        #expect(effects.cancellations.count == 0)

        presenter = nil

        #expect(effects.cancellations.count == 1)
        #expect(effects.stops.count == 0)
    }

    // MARK: - Publishing

    @Test("a state that changes neither the status line nor the message publishes nothing again")
    func unchangedValuesAreNotPublished() async {
        let rig = OnboardingPresenterRig(catalog: catalog(.failed(.compileFailed), compilerMessage: "error: x"))
        await rig.start()
        await settle(rig.presenter.$compilerMessage) { $0 != nil }
        let statuses = Collector<String?>()
        let messages = Collector<String?>()
        let subscriptions = [
            rig.presenter.$effectStatus.dropFirst().sink { statuses.append($0) },
            rig.presenter.$compilerMessage.dropFirst().sink { messages.append($0) },
        ]

        rig.effects.publish(catalog(.failed(.compileFailed), compilerMessage: "error: x"))
        await drainMainActor()
        rig.effects.publish(catalog(.prepared))
        await settle(rig.presenter.$effectStatus) { $0 == nil }

        #expect(statuses.values == [nil], "the repeated failure published nothing; only the clearing did")
        #expect(messages.values == [nil])
        withExtendedLifetime(subscriptions) {}
    }
}
