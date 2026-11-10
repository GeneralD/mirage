import Domain
import Foundation

// The rows of the effect's parameter panel, as a pure function of the parameter states, so that the
// panel's Presenter only moves them into its `@Published` value. A row that cannot be drawn is left out
// and the rest keep their order. A value outside its range is drawn at the nearest end of it; snapping
// to a step is not done here, it is the UseCase's packer's work.

/// The rows for `states`, in their order. A state whose value does not match its kind, or whose range
/// is empty or not finite, has no row.
func parameterPanelRows(of states: [EffectParameterState]) -> [ParameterPanelRow] {
    states.compactMap { state in
        panelControl(of: state).map { ParameterPanelRow(id: state.spec.id, label: state.spec.label, control: $0) }
    }
}

/// The control for one state, or `nil` when it cannot be drawn.
private func panelControl(of state: EffectParameterState) -> ParameterPanelControl? {
    let label = state.spec.label
    switch state.spec.kind {
    case .float(let lower, let upper, let step, _):
        guard case .float(let value) = state.value, let clamped = panelClamped(value, lower, upper) else { return nil }
        return .slider(panelSlider(title: label, caption: nil, value: clamped.value, range: clamped.range, step: panelStep(step)))
    case .int(let lower, let upper, _):
        guard case .int(let value) = state.value, lower <= upper else { return nil }
        let range = Int(lower)...Int(upper)
        let clamped = min(max(Int(value), range.lowerBound), range.upperBound)
        return .stepper(value: clamped, range: range, text: String(clamped))
    case .bool:
        guard case .bool(let isOn) = state.value else { return nil }
        return .toggle(isOn: isOn)
    case .color:
        guard case .color(let value) = state.value, (0..<4).allSatisfy({ value[$0].isFinite }) else { return nil }
        let parts = (0..<4).map { panelWithin(Double(value[$0]), 0...1) }
        return .color(red: parts[0], green: parts[1], blue: parts[2], opacity: parts[3])
    case .vector2(let lower, let upper, _):
        guard case .vector2(let value) = state.value,
            let x = panelClamped(value.x, lower.x, upper.x),
            let y = panelClamped(value.y, lower.y, upper.y)
        else { return nil }
        return .vector(
            x: panelSlider(title: "\(label) X", caption: "X", value: x.value, range: x.range, step: nil),
            y: panelSlider(title: "\(label) Y", caption: "Y", value: y.value, range: y.range, step: nil))
    case .choice(let options, let defaultIndex):
        guard case .choice(let index) = state.value,
            let selection = [index, defaultIndex].first(where: { options.indices.contains($0) })
        else { return nil }
        return .picker(selection: selection, options: options)
    }
}

/// `value` clamped into `lower...upper`, with that range, or `nil` when the value or an end is not
/// finite or `lower` is not below `upper`: a range that cannot be drawn.
private func panelClamped(_ value: Float, _ lower: Float, _ upper: Float) -> (value: Double, range: ClosedRange<Double>)? {
    guard value.isFinite, lower.isFinite, upper.isFinite, lower < upper else { return nil }
    let range = Double(lower)...Double(upper)
    return (panelWithin(Double(value), range), range)
}

/// `value` moved to the nearest end of `range` when it lies outside it.
private func panelWithin(_ value: Double, _ range: ClosedRange<Double>) -> Double {
    min(max(value, range.lowerBound), range.upperBound)
}

/// The grid a slider snaps its drag to: the step as a `Double` when it is a finite number above zero,
/// and `nil` (a free drag) otherwise.
private func panelStep(_ step: Float?) -> Double? {
    guard let step, step.isFinite, step > 0 else { return nil }
    return Double(step)
}

private func panelSlider(
    title: String, caption: String?, value: Double, range: ClosedRange<Double>, step: Double?
) -> ParameterPanelSlider {
    ParameterPanelSlider(
        title: title, caption: caption, value: value, range: range, step: step,
        text: String(format: "%.\(panelDigits(of: step))f", value))
}

/// The decimals a value is written with: as many as the step has, found as the fewest from none to
/// four that make the step a whole number of units. Two without a step, and four for a step too fine
/// to name. The tolerance of `1e-6` (not `==`) lets a `Float` step such as `0.01` through, since
/// `Double(Float(0.01))` is `0.00999999977...`.
private func panelDigits(of step: Double?) -> Int {
    guard let step else { return 2 }
    return (0...4).first(where: { digits in
        let scaled = step * pow(10.0, Double(digits))
        return scaled.rounded() >= 1 && abs(scaled - scaled.rounded()) < 1e-6
    }) ?? 4
}
