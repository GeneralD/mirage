import AppRouter
import Dependencies
import Domain
import Foundation

extension GalleryScreen {
    /// The picker over a catalog in which health has switched two effects off: the chosen `Glitch` (it timed out) and `Ripple`
    /// (it ran over the GPU time budget). The status line names the chosen one and its reason.
    static var effectPickerDisabled: GalleryScreen {
        GalleryScreen(
            name: "effect-picker-disabled",
            summary: "Effect picker: a chosen effect and another that the health policy disabled, with the reason"
        ) {
            openEffectPicker(showing: effectPickerDisabledCatalog)
        }
    }
}

/// The bundled effect, then three packages. `Glitch` is chosen and disabled, `Ripple` is disabled too, and `Neon Outline` can be chosen.
/// Neither disabled package carries a thumbnail or a description, so each of their cells draws its own tile.
var effectPickerDisabledCatalog: EffectCatalogState {
    let chromaticGrain = EffectID(origin: .bundled, key: "Chromatic Grain")
    let glitch = EffectID(origin: .package, key: "glitch")
    let ripple = EffectID(origin: .package, key: "ripple")
    let neon = EffectID(origin: .package, key: "neon")
    return EffectCatalogState(
        entries: [
            EffectCatalogEntry(id: chromaticGrain, displayName: "Chromatic Grain", origin: .bundled, availability: .ready),
            EffectCatalogEntry(id: glitch, displayName: "Glitch", origin: .package, availability: .ready, author: "Jane Doe"),
            EffectCatalogEntry(id: ripple, displayName: "Ripple", origin: .package, availability: .ready, author: "Example Author"),
            EffectCatalogEntry(id: neon, displayName: "Neon Outline", origin: .package, availability: .ready, author: "A. Sample"),
        ],
        selection: glitch,
        disabled: [glitch: .failure(.timeout), ripple: .overBudget]
    )
}
