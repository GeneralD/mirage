import Domain

// The parameter values of one effect as the panel edits them and the frame path reads them
// (`docs/hackathon/mvp-cd/specs/parameters.md`, pure policy). A value type: every change returns a new model. The layout
// is built once from the specs, so `block` only packs the current values.

/// The values of one effect's parameters, in declaration order, each normalized to its kind.
struct ParameterModel: Equatable, Sendable {
    /// The declarations, in manifest order.
    let specs: [EffectParameterSpec]
    /// One value per declared id, each of its kind's own case and within the kind's range.
    let values: [String: EffectParameterValue]
    /// Where each field sits in the `Parameters` struct, built once from `specs`.
    private let layout: EffectParameterLayout

    /// The model of `specs` started from `stored` values, reconciled as `ParameterReconciliation` does: an id no spec
    /// declares is dropped, a missing or mismatched value takes its kind's default, and the rest are clamped.
    init(specs: [EffectParameterSpec], restoring stored: [String: EffectParameterValue]) {
        self.init(
            specs: specs,
            values: ParameterReconciliation.reconcile(stored: stored, specs: specs),
            layout: EffectParameterLayout(specs))
    }

    private init(specs: [EffectParameterSpec], values: [String: EffectParameterValue], layout: EffectParameterLayout) {
        self.specs = specs
        self.values = values
        self.layout = layout
    }

    /// One state per declared parameter, in declaration order.
    var states: [EffectParameterState] {
        specs.map { spec in EffectParameterState(spec: spec, value: values[spec.id] ?? spec.kind.defaultValue) }
    }

    /// The bytes of the `Parameters` block for the current values.
    var block: EffectParameterBlock {
        ParameterPacker.pack(values: values, specs: specs, layout: layout)
    }

    /// The model with `id` set to `value`, or nil when no spec declares `id` or `value` is not of that parameter's case.
    /// The stored value is `value` normalized to its kind, so a float beyond its range is clamped. The model is returned
    /// even when the value does not change: the caller compares with `==` to tell whether anything moved.
    func setting(_ id: String, to value: EffectParameterValue) -> ParameterModel? {
        guard let spec = specs.first(where: { $0.id == id }), spec.kind.accepts(value) else { return nil }
        return with(values.merging([id: spec.kind.normalized(value)]) { _, new in new })
    }

    /// The model with every value back at its kind's default.
    func resetting() -> ParameterModel {
        with(ParameterReconciliation.reconcile(stored: [:], specs: specs))
    }

    /// The model under `specs` with the current values carried over, as a manifest reload needs
    /// (`ParameterReconciliation`): the layout is rebuilt for the new specs.
    func respecified(_ specs: [EffectParameterSpec]) -> ParameterModel {
        ParameterModel(specs: specs, restoring: values)
    }

    /// The same specs and layout with `values` in place of the current ones.
    private func with(_ values: [String: EffectParameterValue]) -> ParameterModel {
        ParameterModel(specs: specs, values: values, layout: layout)
    }
}
