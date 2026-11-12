import AppRouter
import Dependencies
import Domain

extension GalleryScreen {
    /// The parameter panel over `Ripple`, which declares one parameter of each kind: a slider, a stepper, a toggle, a color well,
    /// a vector and a picker.
    static var parameterPanel: GalleryScreen {
        GalleryScreen(name: "parameter-panel", summary: "Parameter panel: one control per kind of parameter") {
            openParameterPanel(showing: parameterPanelCatalog)
        }
    }

    /// The panel over the bundled effect, which declares no parameters: the panel says so in place of the rows.
    static var parameterPanelEmpty: GalleryScreen {
        GalleryScreen(name: "parameter-panel-empty", summary: "Parameter panel: an effect with no parameters") {
            openParameterPanel(showing: parameterPanelEmptyCatalog)
        }
    }
}

/// Builds an `AppRouter` whose Presenters read `catalog`, opens its parameter panel and answers the Router, which keeps the window alive.
/// The Router is made inside `withDependencies` because its Presenters capture the dependencies of the scope they are built in.
/// `makeParameterWindow` is the seam a test uses to open no real window.
@MainActor
func openParameterPanel(
    showing catalog: EffectCatalogState,
    makeParameterWindow: @escaping AppRouter.ParameterWindowFactory = AppRouter.parameterWindow(over:onClose:)
) -> AppRouter {
    let router = withDependencies {
        $0.effectInteractor = GalleryEffectInteractor(catalog: catalog)
    } operation: {
        AppRouter(makeParameterWindow: makeParameterWindow)
    }
    router.openParameterPanel()
    return router
}

private let chromaticGrain = EffectID(origin: .bundled, key: "Chromatic Grain")
private let ripple = EffectID(origin: .package, key: "ripple")

/// The bundled effect, then `Ripple`, in the catalog's order.
private var parameterPanelEntries: [EffectCatalogEntry] {
    [
        EffectCatalogEntry(id: chromaticGrain, displayName: "Chromatic Grain", origin: .bundled, availability: .ready),
        EffectCatalogEntry(
            id: ripple, displayName: "Ripple", origin: .package, availability: .ready, author: "Example Author"),
    ]
}

/// The six parameters of the manifest example in `specs/parameters.md`, in the manifest's order, each at its default.
private var parameterPanelParameters: [EffectParameterState] {
    [
        EffectParameterState(
            spec: EffectParameterSpec(id: "strength", label: "Strength", kind: .float(min: 0, max: 1, step: 0.01, defaultValue: 0.5)),
            value: .float(0.5)),
        EffectParameterState(
            spec: EffectParameterSpec(id: "rings", label: "Rings", kind: .int(min: 1, max: 16, defaultValue: 4)),
            value: .int(4)),
        EffectParameterState(
            spec: EffectParameterSpec(id: "inverted", label: "Inverted", kind: .bool(defaultValue: false)),
            value: .bool(false)),
        EffectParameterState(
            spec: EffectParameterSpec(id: "tint", label: "Tint", kind: .color(defaultValue: SIMD4<Float>(1, 0.8, 0.6, 1))),
            value: .color(SIMD4<Float>(1, 0.8, 0.6, 1))),
        EffectParameterState(
            spec: EffectParameterSpec(
                id: "center", label: "Center",
                kind: .vector2(min: SIMD2<Float>(0, 0), max: SIMD2<Float>(1, 1), defaultValue: SIMD2<Float>(0.5, 0.5))),
            value: .vector2(SIMD2<Float>(0.5, 0.5))),
        EffectParameterState(
            spec: EffectParameterSpec(id: "mode", label: "Mode", kind: .choice(options: ["Soft", "Hard"], defaultIndex: 0)),
            value: .choice(0)),
    ]
}

/// `Ripple` chosen, with the six parameters above and no outcome yet.
var parameterPanelCatalog: EffectCatalogState {
    EffectCatalogState(entries: parameterPanelEntries, selection: ripple, parameters: parameterPanelParameters)
}

/// The bundled effect chosen, which declares no parameters.
var parameterPanelEmptyCatalog: EffectCatalogState {
    EffectCatalogState(entries: parameterPanelEntries, selection: chromaticGrain)
}
