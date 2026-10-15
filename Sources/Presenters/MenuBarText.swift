import Domain

/// The words and flags of the effects menu, as pure functions of the catalog's state, so
/// that `MenuBarPresenter` only moves them into its `@Published` values.
enum MenuBarText {
    /// One row per catalog entry, in the catalog's order. A package that failed to load is
    /// disabled and says why; a package that loaded shows its author, if its manifest names one.
    static func items(of state: EffectCatalogState) -> [EffectMenuItem] {
        state.entries.map { entry in
            EffectMenuItem(
                id: entry.id,
                title: entry.displayName,
                detail: detail(of: entry),
                isSelected: entry.id == state.selection,
                isEnabled: entry.availability == .ready)
        }
    }

    /// `"<name>: <why>"` when the last attempt to run the chosen effect did not succeed,
    /// `nil` when it did or nothing was attempted. The name is the chosen entry's, its key
    /// when the catalog no longer lists it.
    static func status(of state: EffectCatalogState) -> String? {
        guard let outcome = state.outcome else { return nil }
        let name = state.entries.first { $0.id == state.selection }?.displayName ?? state.selection.key
        switch outcome {
        case .prepared:
            return nil
        case .failed(let failure):
            return "\(name): \(reason(failure))"
        case .unavailable(let problem?):
            return "\(name): \(reason(problem))"
        case .unavailable(nil):
            return "\(name): no longer available"
        }
    }

    static func reason(_ problem: EffectPackageProblem) -> String {
        switch problem {
        case .manifestMissing: "manifest.json is missing"
        case .manifestInvalid(let message): "manifest.json is invalid: \(message)"
        case .unsupportedFormatVersion(let version): "unsupported formatVersion \(version)"
        case .sourceMissing: "effect.metal is missing"
        case .unreadable(let message): "cannot be read: \(message)"
        }
    }

    static func reason(_ failure: EffectFailure) -> String {
        switch failure {
        case .compileFailed: "compile failed"
        case .timeout: "timed out"
        case .pageFault: "GPU page fault"
        case .accessRevoked: "GPU access revoked"
        case .outOfMemory: "out of memory"
        case .invalidResource: "invalid GPU resource"
        case .internalError: "internal error"
        case .unknown(let code): "unknown error (\(code))"
        }
    }

    private static func detail(of entry: EffectCatalogEntry) -> String? {
        switch entry.availability {
        case .ready: entry.author
        case .broken(let problem): reason(problem)
        }
    }
}
