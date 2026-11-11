import Dependencies
import Domain
import Presenters
import TestDoubles
import TestSupport
import Testing

@MainActor @Suite("ParameterPanelSetting", .timeLimit(.minutes(1)))
struct ParameterPanelSettingTests {
    @Test("setFloat records one float set for the parameter it names, with the value as a Float")
    func setFloatRecordsAFloatSet() {
        let rig = SettingRig()

        rig.presenter.setFloat("strength", to: 0.25)

        #expect(rig.interactor.parameterCalls.values == [Call.set("strength", .float(0.25))])
    }

    @Test("setInt records one int set, and clamps Int.max to Int32.max and Int.min to Int32.min")
    func setIntClampsToTheInt32Range() {
        let rig = SettingRig()

        rig.presenter.setInt("rings", to: 3)
        rig.presenter.setInt("rings", to: Int.max)
        rig.presenter.setInt("rings", to: Int.min)

        #expect(
            rig.interactor.parameterCalls.values == [
                Call.set("rings", .int(3)),
                Call.set("rings", .int(Int32.max)),
                Call.set("rings", .int(Int32.min)),
            ])
    }

    @Test("setBool records one bool set for the parameter it names")
    func setBoolRecordsABoolSet() {
        let rig = SettingRig()

        rig.presenter.setBool("inverted", to: true)

        #expect(rig.interactor.parameterCalls.values == [Call.set("inverted", .bool(true))])
    }

    @Test("setColor records one color set made of the four components as Floats")
    func setColorRecordsAColorSet() {
        let rig = SettingRig()

        rig.presenter.setColor("tint", red: 0.25, green: 0.5, blue: 0.75, opacity: 1)

        #expect(rig.interactor.parameterCalls.values == [Call.set("tint", .color(SIMD4<Float>(0.25, 0.5, 0.75, 1)))])
    }

    @Test("setVector records one vector2 set made of the two components as Floats")
    func setVectorRecordsAVectorSet() {
        let rig = SettingRig()

        rig.presenter.setVector("offset", x: 0.25, y: -0.5)

        #expect(rig.interactor.parameterCalls.values == [Call.set("offset", .vector2(SIMD2<Float>(0.25, -0.5)))])
    }

    @Test("setChoice records one choice set with the index passed through unchanged")
    func setChoiceRecordsAChoiceSet() {
        let rig = SettingRig()

        rig.presenter.setChoice("mode", to: 2)

        #expect(rig.interactor.parameterCalls.values == [Call.set("mode", .choice(2))])
    }

    @Test("reset records one reset call and sends no value")
    func resetRecordsOneResetAndNoValue() {
        let rig = SettingRig()

        rig.presenter.reset()

        #expect(rig.interactor.parameterCalls.values == [Call.reset])
    }

    @Test("the setters and reset record their calls in the order they were made, one entry each")
    func callsKeepTheirOrder() {
        let rig = SettingRig()

        rig.presenter.setFloat("strength", to: 0.5)
        rig.presenter.setBool("inverted", to: false)
        rig.presenter.reset()
        rig.presenter.setChoice("mode", to: 1)

        #expect(
            rig.interactor.parameterCalls.values == [
                Call.set("strength", .float(0.5)),
                Call.set("inverted", .bool(false)),
                Call.reset,
                Call.set("mode", .choice(1)),
            ])
    }

    @Test("a Double that is not finite as a Float is not sent, and the finite value after it is")
    func nonFiniteValuesAreNotSent() {
        let rig = SettingRig()

        rig.presenter.setFloat("strength", to: .nan)
        rig.presenter.setFloat("strength", to: .infinity)
        rig.presenter.setFloat("strength", to: 1e300)
        #expect(rig.interactor.parameterCalls.values.isEmpty, "1e300 is infinite as a Float, so it is not sent either")

        rig.presenter.setColor("tint", red: .nan, green: 0, blue: 0, opacity: 1)
        rig.presenter.setColor("tint", red: 0, green: 0, blue: 0, opacity: 1e300)
        #expect(rig.interactor.parameterCalls.values.isEmpty, "a color with one non-finite component is not sent")

        rig.presenter.setVector("offset", x: .infinity, y: 0)
        rig.presenter.setVector("offset", x: 0, y: 1e300)
        #expect(rig.interactor.parameterCalls.values.isEmpty, "a vector with one non-finite component is not sent")

        rig.presenter.setFloat("strength", to: 0.5)
        #expect(rig.interactor.parameterCalls.values == [Call.set("strength", .float(0.5))], "the finite value after them is recorded")
    }

    @Test("the setters and reset reach the Interactor without the Presenter being started")
    func settersWorkBeforeStart() {
        let rig = SettingRig()

        rig.presenter.setBool("inverted", to: true)
        rig.presenter.reset()

        #expect(!rig.presenter.isObserving)
        #expect(rig.interactor.starts.count == 0, "the setters did not start the Interactor")
        #expect(rig.interactor.parameterCalls.values == [Call.set("inverted", .bool(true)), Call.reset])
    }
}

private typealias Call = FakeEffectCatalogUseCase.ParameterCall

/// A panel Presenter over a spy Interactor, built inside `withDependencies` so that it captures the spy.
/// Its state is never published: the setters do not read it.
@MainActor
private struct SettingRig {
    let interactor: SpyEffectInteractor
    let presenter: ParameterPanelPresenter

    init() {
        let interactor = SpyEffectInteractor(FakeEffectInteractor(state: .fixture([EffectCatalogEntry.fixture(.package("ripple"))])))
        self.interactor = interactor
        presenter = withDependencies {
            $0.effectInteractor = interactor
        } operation: {
            ParameterPanelPresenter()
        }
    }
}
