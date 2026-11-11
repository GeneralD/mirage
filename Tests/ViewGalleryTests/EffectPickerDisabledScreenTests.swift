import Dependencies
import Domain
import Presenters
import TestSupport
import Testing

@testable import ViewGallery

@MainActor
@Suite("Effect picker disabled screen", .timeLimit(.minutes(1)))
struct EffectPickerDisabledScreenTests {
    /// The Presenter the live window would draw, started over the fixture; its dependency is assigned, never resolved.
    private func startedPresenter(showing catalog: EffectCatalogState) async -> EffectPickerPresenter {
        let presenter = withDependencies {
            $0.effectInteractor = GalleryEffectInteractor(catalog: catalog)
        } operation: {
            EffectPickerPresenter()
        }
        presenter.start()
        await settle(presenter.$cells) { !$0.isEmpty }
        return presenter
    }

    @Test("effect-picker-disabled is registered exactly once, under its name")
    func registered() {
        #expect(galleryScreens.map(\.name).filter { $0 == "effect-picker-disabled" }.count == 1)
    }

    @Test("the disabled picker lists four cells in the catalog's order, with Glitch chosen and Glitch and Ripple disabled")
    func cellsInOrder() async {
        let presenter = await startedPresenter(showing: effectPickerDisabledCatalog)

        #expect(presenter.cells.map(\.title) == ["Chromatic Grain", "Glitch", "Ripple", "Neon Outline"])
        #expect(presenter.cells.map(\.isEnabled) == [true, false, false, true])
        #expect(presenter.cells.map(\.isSelected) == [false, true, false, false])
    }

    @Test("a cell that health switched off says so with the reason as its second line, and a package that is enabled shows its author")
    func disabledCellDetails() async throws {
        let presenter = await startedPresenter(showing: effectPickerDisabledCatalog)

        let glitch = try #require(presenter.cells.first { $0.title == "Glitch" })
        let ripple = try #require(presenter.cells.first { $0.title == "Ripple" })
        let neon = try #require(presenter.cells.first { $0.title == "Neon Outline" })
        #expect(glitch.detail == "Disabled: timed out")
        #expect(ripple.detail == "Disabled: over the GPU time budget")
        #expect(neon.detail == "A. Sample")
    }

    @Test("the status line says the chosen effect is disabled and why")
    func disabledStatus() async {
        let presenter = await startedPresenter(showing: effectPickerDisabledCatalog)

        #expect(presenter.status == "Glitch: disabled, timed out")
    }
}
