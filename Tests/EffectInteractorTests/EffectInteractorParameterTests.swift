import Combine
import Dependencies
import Domain
import EffectInteractor
import TestDoubles
import TestSupport
import Testing

@Suite("EffectInteractorImpl parameters", .timeLimit(.minutes(1)))
struct EffectInteractorParameterTests {
    private let chromatic = EffectCatalogEntry.fixture(.bundled("Chromatic Grain"))
    private let strength = EffectParameterSpec(id: "strength", label: "Strength", kind: .float(min: 0, max: 1, step: 0.01, defaultValue: 0.5))

    @Test("setParameter reaches the UseCase with the id and the value it was given")
    func setParameterReachesUseCase() async {
        let rig = ParameterRig()

        rig.subject.setParameter("strength", to: .float(0.25))
        await rig.catalog.parameterCalls.waitForCount(1)

        #expect(rig.catalog.parameterCalls.values == [.set("strength", .float(0.25))])
    }

    @Test("resetParameters reaches the UseCase")
    func resetParametersReachesUseCase() async {
        let rig = ParameterRig()

        rig.subject.resetParameters()
        await rig.catalog.parameterCalls.waitForCount(1)

        #expect(rig.catalog.parameterCalls.values == [.reset])
    }

    @Test("a hundred setParameter calls reach the UseCase one after another, in the order they were made")
    func hundredSetsKeepTheirOrder() async {
        let rig = ParameterRig()
        let values = (1...100).map { EffectParameterValue.int(Int32($0)) }

        for value in values {
            rig.subject.setParameter("rings", to: value)
        }
        await rig.catalog.parameterCalls.waitForCount(100)

        #expect(rig.catalog.parameterCalls.values == values.map { FakeEffectCatalogUseCase.ParameterCall.set("rings", $0) })
    }

    @Test("set, reset and set queued back to back reach the UseCase in that order")
    func mixedCallsKeepTheirOrder() async {
        let rig = ParameterRig()

        rig.subject.setParameter("strength", to: .float(0.25))
        rig.subject.resetParameters()
        rig.subject.setParameter("rings", to: .int(9))
        await rig.catalog.parameterCalls.waitForCount(3)

        #expect(rig.catalog.parameterCalls.values == [.set("strength", .float(0.25)), .reset, .set("rings", .int(9))])
    }

    @Test("the state the UseCase publishes with its parameters reaches state unchanged")
    func stateCarriesParameters() async {
        let withParameter = EffectCatalogState.fixture(
            [chromatic], parameters: [EffectParameterState(spec: strength, value: .float(0.75))])
        let rig = ParameterRig(state: .fixture([chromatic]))
        let seen = Collector<EffectCatalogState>()
        let subscription = rig.subject.state.sink { seen.append($0) }

        rig.subject.start()
        await seen.waitForCount(1)
        rig.catalog.publish(withParameter)
        await seen.waitForCount(2)

        #expect(seen.last == withParameter)
        withExtendedLifetime(subscription) {}
    }

    @Test("a setParameter made before start reaches the UseCase, which decides what to do with it")
    func setBeforeStartReachesUseCase() async {
        let rig = ParameterRig()

        rig.subject.setParameter("strength", to: .float(0.5))
        await rig.catalog.parameterCalls.waitForCount(1)

        #expect(rig.catalog.parameterCalls.values == [.set("strength", .float(0.5))])
        #expect(rig.catalog.runs.count == 0, "a parameter call does not start the catalog")
    }

    @Test("a setParameter made after stop reaches the UseCase: the parameter queue is not the run queue")
    func setAfterStopReachesUseCase() async {
        let rig = ParameterRig()

        rig.subject.start()
        await rig.catalog.runs.waitForCount(1)
        rig.subject.stop()
        await rig.catalog.runCancellations.waitForCount(1)
        rig.subject.setParameter("strength", to: .float(0.5))
        await rig.catalog.parameterCalls.waitForCount(1)

        #expect(rig.catalog.parameterCalls.values == [.set("strength", .float(0.5))])
    }
}

/// An Interactor over a `FakeEffectCatalogUseCase`, built inside `withDependencies`
/// (the subject captures the dependencies of the scope it is made in). Its shape is the
/// one of `InteractorRig` in `EffectInteractorTests`, which is private to that file.
private struct ParameterRig {
    let catalog: FakeEffectCatalogUseCase
    let errorLog = RecordingLog()
    let developerLog = RecordingLog()
    let subject: EffectInteractorImpl

    init(state: EffectCatalogState? = nil) {
        catalog = FakeEffectCatalogUseCase(state: state)
        subject = Self.make(catalog: catalog, errorLog: errorLog, developerLog: developerLog)
    }

    static func make(catalog: FakeEffectCatalogUseCase, errorLog: RecordingLog, developerLog: RecordingLog) -> EffectInteractorImpl {
        withDependencies {
            $0.effectCatalogUseCase = catalog
            $0.errorLog = errorLog
            $0.developerLog = developerLog
        } operation: {
            EffectInteractorImpl()
        }
    }
}
