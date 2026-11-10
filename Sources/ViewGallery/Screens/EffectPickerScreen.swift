import AppRouter
import Dependencies
import Domain
import Foundation

extension GalleryScreen {
    /// The picker over a catalog of every kind of cell: the chosen bundled effect, ready packages (one whose thumbnail does not
    /// decode, one with a name too long for its cell), and a package that failed to load.
    static var effectPicker: GalleryScreen {
        GalleryScreen(name: "effect-picker", summary: "Effect picker: ready, long-named and broken packages, the bundled effect chosen") {
            openEffectPicker(showing: effectPickerCatalog)
        }
    }

    /// The same catalog with the chosen package failed to compile: the picker's status line shows why.
    static var effectPickerFailed: GalleryScreen {
        GalleryScreen(name: "effect-picker-failed", summary: "Effect picker: the chosen package failed to compile") {
            openEffectPicker(showing: effectPickerFailedCatalog)
        }
    }
}

/// Builds an `AppRouter` whose Presenters read `catalog`, opens its picker and answers the Router, which keeps the window alive.
/// The Router is made inside `withDependencies` because its Presenters capture the dependencies of the scope they are built in.
/// `makePickerWindow` is the seam a test uses to open no real window.
@MainActor
func openEffectPicker(
    showing catalog: EffectCatalogState,
    makePickerWindow: @escaping AppRouter.PickerWindowFactory = AppRouter.pickerWindow(over:onClose:)
) -> AppRouter {
    let router = withDependencies {
        $0.effectInteractor = GalleryEffectInteractor(catalog: catalog)
    } operation: {
        AppRouter(makePickerWindow: makePickerWindow)
    }
    router.openEffectPicker()
    return router
}

private let chromaticGrain = EffectID(origin: .bundled, key: "Chromatic Grain")
private let ripple = EffectID(origin: .package, key: "ripple")

/// Six entries in the catalog's order: the bundled effect, then the packages.
private var effectPickerEntries: [EffectCatalogEntry] {
    [
        EffectCatalogEntry(id: chromaticGrain, displayName: "Chromatic Grain", origin: .bundled, availability: .ready),
        EffectCatalogEntry(
            id: ripple, displayName: "Ripple", origin: .package, availability: .ready, author: "Example Author",
            description: "Swaying stripes that follow the picture"),
        EffectCatalogEntry(
            id: EffectID(origin: .package, key: "glitch"), displayName: "Glitch", origin: .package, availability: .ready, author: "Jane Doe",
            thumbnail: EffectThumbnail(data: Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x01]), format: .png)),
        EffectCatalogEntry(
            id: EffectID(origin: .package, key: "long-name"), displayName: "An Extremely Long Effect Name That Cannot Fit On One Line",
            origin: .package, availability: .ready, author: "A Person With A Very Long Author Name"),
        EffectCatalogEntry(
            id: EffectID(origin: .package, key: "neon"), displayName: "Neon Outline", origin: .package, availability: .ready,
            author: "A. Sample"),
        EffectCatalogEntry(
            id: EffectID(origin: .package, key: "wip-blur"), displayName: "wip-blur", origin: .package, availability: .broken(.sourceMissing)),
    ]
}

/// The bundled effect chosen, nothing attempted yet.
var effectPickerCatalog: EffectCatalogState {
    EffectCatalogState(entries: effectPickerEntries, selection: chromaticGrain)
}

/// `Ripple` chosen and its compile failed.
var effectPickerFailedCatalog: EffectCatalogState {
    EffectCatalogState(entries: effectPickerEntries, selection: ripple, outcome: .failed(.compileFailed))
}
