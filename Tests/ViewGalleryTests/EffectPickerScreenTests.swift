import AppRouter
import Dependencies
import Domain
import Presenters
import TestSupport
import Testing

@testable import ViewGallery

/// A picker window that is never on screen: it only counts what the Router asks of it.
@MainActor
private final class FakePickerWindow {
    private(set) var shows = 0
    private(set) var closes = 0
}

extension FakePickerWindow: PickerWindow {
    func show() {
        shows += 1
    }

    func close() {
        closes += 1
    }
}

@MainActor
@Suite("Effect picker screens", .timeLimit(.minutes(1)))
struct EffectPickerScreenTests {
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

    @Test("the two picker screens come first in the registry, under their names, in this order")
    func registered() {
        #expect(Array(galleryScreens.map(\.name).prefix(2)) == ["effect-picker", "effect-picker-failed"])
    }

    @Test("effect-picker lists six cells in the catalog's order with the bundled effect chosen")
    func cellsInOrder() async {
        let presenter = await startedPresenter(showing: effectPickerCatalog)

        #expect(
            presenter.cells.map(\.title) == [
                "Chromatic Grain", "Ripple", "Glitch", "An Extremely Long Effect Name That Cannot Fit On One Line", "Neon Outline", "wip-blur",
            ])
        #expect(presenter.cells.map(\.isSelected) == [true, false, false, false, false, false])
        #expect(presenter.status == nil)
    }

    @Test("the last cell is a broken package: disabled, with its reason as the second line")
    func brokenCell() async throws {
        let presenter = await startedPresenter(showing: effectPickerCatalog)

        let broken = try #require(presenter.cells.last)
        #expect(broken.isEnabled == false)
        #expect(broken.detail == "effect.metal is missing")
        #expect(presenter.cells.map(\.isEnabled) == [true, true, true, true, true, false])
    }

    @Test("Glitch carries a thumbnail that cannot decode, so its cell has a tile to fall back on")
    func undecodableThumbnail() async throws {
        let presenter = await startedPresenter(showing: effectPickerCatalog)

        let glitch = try #require(presenter.cells.first { $0.title == "Glitch" })
        guard case .image(_, let fallback) = glitch.artwork else {
            Issue.record("expected an image artwork with a fallback tile, got \(glitch.artwork)")
            return
        }
        #expect(fallback.monogram == "G")
    }

    @Test("effect-picker-failed chooses Ripple and the status line says its compile failed")
    func failedStatus() async {
        let presenter = await startedPresenter(showing: effectPickerFailedCatalog)

        #expect(presenter.cells.map(\.isSelected) == [false, true, false, false, false, false])
        #expect(presenter.status == "Ripple: compile failed")
    }

    @Test("opening a screen makes one window over the Router's picker Presenter, shows it once and starts the Presenter")
    func opensOneWindow() async throws {
        let windows = Collector<FakePickerWindow>()

        let router = openEffectPicker(showing: effectPickerCatalog) { _, _ in
            let window = FakePickerWindow()
            windows.append(window)
            return window
        }

        let window = try #require(windows.values.first)
        #expect(windows.count == 1)
        #expect(window.shows == 1)
        #expect(window.closes == 0)
        await settle(router.effectPickerPresenter.$cells) { !$0.isEmpty }
        #expect(router.effectPickerPresenter.cells.count == 6)
    }
}
