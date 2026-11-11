import Domain

/// The words and flags of the effects menu, as pure functions of the catalog's state, so
/// that `MenuBarPresenter` only moves them into its `@Published` values.
enum MenuBarText {
    /// One row per catalog entry, in the catalog's order. A package that failed to load is
    /// disabled and says why; an effect that health has switched off is disabled, says why and
    /// offers to be re-enabled; any other package shows its author, if its manifest names one.
    static func items(of state: EffectCatalogState) -> [EffectMenuItem] {
        state.entries.map { entry in
            let disabled = state.disabled[entry.id]
            return EffectMenuItem(
                id: entry.id,
                title: entry.displayName,
                detail: detail(of: entry, in: state),
                isSelected: entry.id == state.selection,
                isEnabled: entry.availability == .ready && disabled == nil,
                reenableTitle: disabled.map { _ in "Re-enable \(entry.displayName)" })
        }
    }

    /// The line about the chosen effect, in this order: `GPU unavailable` when no effect can move
    /// frames; `"<name>: disabled, <why>"` when health has switched the chosen effect off;
    /// otherwise `"<name>: <why>"` when the last attempt to run it did not succeed, and `nil` when
    /// it did or nothing was attempted. The name is the chosen entry's, its key when the catalog
    /// no longer lists it.
    static func status(of state: EffectCatalogState) -> String? {
        if state.isGPUUnavailable { return "GPU unavailable: frames pass through unchanged" }
        let name = state.entries.first { $0.id == state.selection }?.displayName ?? state.selection.key
        if let disabled = state.disabled[state.selection] { return "\(name): disabled, \(reason(disabled))" }
        guard let outcome = state.outcome else { return nil }
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

    /// Why health switched an effect off, in the words `reason(_:)` uses for the same failure: the
    /// failure kinds a record keeps have no raw code, so `unknown` has none either.
    static func reason(_ reason: EffectDisableReason) -> String {
        switch reason {
        case .failure(.timeout): "timed out"
        case .failure(.pageFault): "GPU page fault"
        case .failure(.accessRevoked): "GPU access revoked"
        case .failure(.outOfMemory): "out of memory"
        case .failure(.unknown): "unknown error"
        case .overBudget: "over the GPU time budget"
        }
    }

    /// A row's second line. A broken package says why it cannot be chosen, first, because its
    /// manifest is not trusted for an author either. A switched-off effect says `Disabled:` and the
    /// reason. Any other package shows its author. The picker's cells say the same under their names.
    static func detail(of entry: EffectCatalogEntry, in state: EffectCatalogState) -> String? {
        if case .broken(let problem) = entry.availability { return reason(problem) }
        if let disabled = state.disabled[entry.id] { return "Disabled: \(reason(disabled))" }
        return entry.author
    }

    /// The title of *Adjust Effect…*, the one item that opens the parameter panel.
    static let adjustEffectTitle = "Adjust Effect…"

    /// Whether *Adjust Effect…* can be chosen: the chosen effect declares parameters. Only the parameters are
    /// read, so the outcome of the chosen effect does not decide it.
    static func canAdjustEffect(of state: EffectCatalogState) -> Bool {
        !state.parameters.isEmpty
    }
}
