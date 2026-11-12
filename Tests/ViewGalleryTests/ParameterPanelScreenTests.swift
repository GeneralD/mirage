import AppRouter
import Dependencies
import Domain
import Presenters
import TestSupport
import Testing

@testable import ViewGallery

/// A parameter panel window that is never on screen: it only counts what the Router asks of it.
@MainActor
private final class FakeParameterWindow {
    private(set) var shows = 0
    private(set) var closes = 0
}

extension FakeParameterWindow: ParameterWindow {
    func show() {
        shows += 1
    }

    func close() {
        closes += 1
    }
}

@MainActor
@Suite("Parameter panel screens", .timeLimit(.minutes(1)))
struct ParameterPanelScreenTests {
    @Test("the two parameter-panel screens are registered in the gallery under their names")
    func registered() {
        let names = galleryScreens.map(\.name)
        #expect(names.contains("parameter-panel"))
        #expect(names.contains("parameter-panel-empty"))
    }

    @Test("opening parameter-panel makes one window over the Router's panel Presenter, shows it once and never closes it")
    func opensOneWindow() async throws {
        let windows = Collector<FakeParameterWindow>()

        let router = openParameterPanel(showing: parameterPanelCatalog) { _, _ in
            let window = FakeParameterWindow()
            windows.append(window)
            return window
        }

        let window = try #require(windows.values.first)
        #expect(windows.count == 1)
        #expect(window.shows == 1)
        #expect(window.closes == 0)
        await settle(router.parameterPanelPresenter.$rows) { !$0.isEmpty }
        #expect(router.parameterPanelPresenter.rows.map(\.id) == ["strength", "rings", "inverted", "tint", "center", "mode"])
        #expect(router.parameterPanelPresenter.heading == "Ripple")
        #expect(router.parameterPanelPresenter.emptyMessage == nil)
    }

    @Test("parameter-panel draws strength as a slider reading 0.50, rings as a stepper at 4 and inverted as an off toggle")
    func leadingRowControls() async throws {
        let router = openParameterPanel(showing: parameterPanelCatalog) { _, _ in FakeParameterWindow() }
        await settle(router.parameterPanelPresenter.$rows) { !$0.isEmpty }
        let controls = Dictionary(uniqueKeysWithValues: router.parameterPanelPresenter.rows.map { ($0.id, $0.control) })

        let strength = try #require(controls["strength"])
        guard case .slider(let slider) = strength else {
            Issue.record("expected a slider for strength, got \(strength)")
            return
        }
        #expect(slider.text == "0.50")
        #expect(controls["rings"] == .stepper(value: 4, range: 1...16, text: "4"))
        #expect(controls["inverted"] == .toggle(isOn: false))
    }

    @Test("parameter-panel draws center as a vector whose two sliders read 0.50 under the captions X and Y, and mode as a picker on Soft")
    func trailingRowControls() async throws {
        let router = openParameterPanel(showing: parameterPanelCatalog) { _, _ in FakeParameterWindow() }
        await settle(router.parameterPanelPresenter.$rows) { !$0.isEmpty }
        let controls = Dictionary(uniqueKeysWithValues: router.parameterPanelPresenter.rows.map { ($0.id, $0.control) })

        let center = try #require(controls["center"])
        guard case .vector(let x, let y) = center else {
            Issue.record("expected a vector for center, got \(center)")
            return
        }
        #expect(x.text == "0.50")
        #expect(y.text == "0.50")
        #expect(x.caption == "X")
        #expect(y.caption == "Y")
        #expect(controls["mode"] == .picker(selection: 0, options: ["Soft", "Hard"]))
    }

    @Test("parameter-panel-empty has no rows, says Chromatic Grain has no parameters and is headed Chromatic Grain")
    func emptyPanel() async {
        let router = openParameterPanel(showing: parameterPanelEmptyCatalog) { _, _ in FakeParameterWindow() }
        await settle(router.parameterPanelPresenter.$heading) { !$0.isEmpty }

        #expect(router.parameterPanelPresenter.rows.isEmpty)
        #expect(router.parameterPanelPresenter.emptyMessage == "Chromatic Grain has no parameters")
        #expect(router.parameterPanelPresenter.heading == "Chromatic Grain")
    }
}
