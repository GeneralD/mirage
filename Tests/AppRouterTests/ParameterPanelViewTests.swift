import Dependencies
import Domain
import Presenters
import TestDoubles
import TestSupport
import Testing

@testable import Views

/// The parameter panel's Views (#117). `Views` holds no logic and is not measured for coverage, so these tests only build each
/// body over a real Presenter: the tree is made without a window, and every kind of row the Presenter chose is in it. What the
/// panel looks like is the gallery's `parameter-panel` screen (#121).
@MainActor
@Suite("ParameterPanelView", .timeLimit(.minutes(1)))
struct ParameterPanelViewTests {
    private let chromatic = EffectCatalogEntry.fixture(.bundled("Chromatic Grain"))

    @Test("the panel builds over a started Presenter with one row for each of the six parameter kinds")
    func buildsOverEveryKind() async {
        let presenter = await startedPanel(showing: .fixture([chromatic], parameters: sixParameters))

        #expect(presenter.rows.map(\.id) == ["strength", "rings", "inverted", "tint", "center", "mode"])
        _ = ParameterPanelView(presenter: presenter).body
    }

    @Test("the panel builds for an effect with no parameters, where the Presenter holds the message that stands in for the rows")
    func buildsWithTheEmptyMessage() async {
        let presenter = await startedPanel(showing: .fixture([chromatic]))

        #expect(presenter.rows.isEmpty)
        #expect(presenter.emptyMessage != nil)
        _ = ParameterPanelView(presenter: presenter).body
    }

    @Test("the panel builds before any state arrives, with no rows, no message and the heading still empty")
    func buildsBeforeAnyState() {
        let presenter = withDependencies {
            $0.effectInteractor = FakeEffectInteractor(state: .fixture([chromatic]))
        } operation: {
            ParameterPanelPresenter()
        }

        #expect(presenter.heading.isEmpty)
        _ = ParameterPanelView(presenter: presenter).body
    }

    @Test("ParameterRowView builds a row for each of the six control kinds the Presenter chose, with its label and control")
    func rowBuildsEveryKind() async {
        let presenter = await startedPanel(showing: .fixture([chromatic], parameters: sixParameters))
        let geometry = ParameterPanelGeometry(width: ParameterPanelGeometry.initialWidth)

        #expect(presenter.rows.count == 6)
        for row in presenter.rows {
            _ = ParameterRowView(row: row, geometry: geometry, presenter: presenter).body
        }
    }
}

/// The six parameters of the spec's example manifest, one per kind, each at a value the Presenter can draw.
private let sixParameters: [EffectParameterState] = [
    EffectParameterState(spec: .strength, value: .float(0.25)),
    EffectParameterState(spec: .rings, value: .int(4)),
    EffectParameterState(spec: .inverted, value: .bool(false)),
    EffectParameterState(spec: .tint, value: .color(SIMD4<Float>(1, 0.5, 0.25, 1))),
    EffectParameterState(spec: .center, value: .vector2(SIMD2<Float>(0.5, 0.25))),
    EffectParameterState(spec: .mode, value: .choice(0)),
]

/// A started panel Presenter over a `FakeEffectInteractor` that shows `state`, built inside `withDependencies` so that it never
/// reaches the live Interactor. The heading is the first state to arrive, so the call waits for it.
@MainActor
private func startedPanel(showing state: EffectCatalogState) async -> ParameterPanelPresenter {
    let presenter = withDependencies {
        $0.effectInteractor = FakeEffectInteractor(state: state)
    } operation: {
        ParameterPanelPresenter()
    }
    presenter.start()
    await settle(presenter.$heading) { !$0.isEmpty }
    return presenter
}
