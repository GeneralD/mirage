import AppRouter
import Dependencies
import Domain

extension GalleryScreen {
    /// The onboarding window while the extension waits for approval: the status asks for it, and both approval panes are offered.
    static var onboardingApproval: GalleryScreen {
        GalleryScreen(name: "onboarding-approval", summary: "Onboarding window while the extension waits for approval") {
            openOnboarding(install: .needsApproval, catalog: onboardingApprovalCatalog, systemMajor: 15)
        }
    }

    /// The onboarding window after the chosen effect failed to compile: the extension is ready, and the compiler's message says why.
    static var onboardingCompileFailed: GalleryScreen {
        GalleryScreen(name: "onboarding-compile-failed", summary: "Onboarding window after the selected effect failed to compile") {
            openOnboarding(install: .installed, catalog: onboardingCompileFailedCatalog, systemMajor: 15)
        }
    }
}

/// Builds an `OnboardingRouter` whose Presenter reads the install status `install`, the catalog `catalog` and the macOS major version
/// `systemMajor`, opens its window and answers the Router, which keeps the window alive. The Router is made inside `withDependencies`
/// because its Presenter captures the dependencies of the scope it is built in. `makeWindow` is the seam a test uses to open no real
/// window.
@MainActor
func openOnboarding(
    install: InstallStatus,
    catalog: EffectCatalogState,
    systemMajor: Int,
    makeWindow: @escaping OnboardingRouter.WindowFactory = OnboardingRouter.window(over:onClose:)
) -> OnboardingRouter {
    let router = withDependencies {
        $0.onboardingInteractor = GalleryOnboardingInteractor(install: install)
        $0.effectInteractor = GalleryEffectInteractor(catalog: catalog)
        $0.hostEnvironment = GalleryHostEnvironment(systemMajor: systemMajor)
    } operation: {
        OnboardingRouter(makeWindow: makeWindow)
    }
    router.openOnboarding()
    return router
}

private let chromaticGrain = EffectID(origin: .bundled, key: "Chromatic Grain")
private let ripple = EffectID(origin: .package, key: "ripple")

/// The bundled effect, then `Ripple`, both ready, in the catalog's order.
private var onboardingEntries: [EffectCatalogEntry] {
    [
        EffectCatalogEntry(id: chromaticGrain, displayName: "Chromatic Grain", origin: .bundled, availability: .ready),
        EffectCatalogEntry(id: ripple, displayName: "Ripple", origin: .package, availability: .ready),
    ]
}

/// The bundled effect chosen, nothing attempted yet.
var onboardingApprovalCatalog: EffectCatalogState {
    EffectCatalogState(entries: onboardingEntries, selection: chromaticGrain)
}

/// `Ripple` chosen and its compile failed, with the compiler's four-line message.
var onboardingCompileFailedCatalog: EffectCatalogState {
    EffectCatalogState(
        entries: onboardingEntries, selection: ripple, outcome: .failed(.compileFailed),
        compilerMessage: [
            "effect.metal:12:15: error: use of undeclared identifier 'swayy'",
            "    float offset = swayy * amplitude;",
            "                 ^",
            "effect.metal:12:15: note: did you mean 'sway'?",
        ].joined(separator: "\n"))
}
