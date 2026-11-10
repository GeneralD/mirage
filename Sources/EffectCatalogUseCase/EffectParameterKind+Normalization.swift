import Domain

// The normalization of a parameter value to its kind (`docs/hackathon/mvp-cd/specs/parameters.md`,
// pure policy). Pure and total: any input gives a value of the kind's own case within the kind's range,
// and a value that is already in range comes back unchanged.

extension EffectParameterKind {
    /// The value this kind starts from: what a value that cannot be used falls back to.
    var defaultValue: EffectParameterValue {
        switch self {
        case .float(_, _, _, let defaultValue): .float(defaultValue)
        case .int(_, _, let defaultValue): .int(defaultValue)
        case .bool(let defaultValue): .bool(defaultValue)
        case .color(let defaultValue): .color(defaultValue)
        case .vector2(_, _, let defaultValue): .vector2(defaultValue)
        case .choice(_, let defaultIndex): .choice(defaultIndex)
        }
    }

    /// Whether `value` is of this kind's case. The range and the step are not looked at: `normalized` brings
    /// a value into them.
    func accepts(_ value: EffectParameterValue) -> Bool {
        switch (self, value) {
        case (.float, .float), (.int, .int), (.bool, .bool), (.color, .color), (.vector2, .vector2), (.choice, .choice): true
        default: false
        }
    }

    /// `value` brought into this kind. A value of another case becomes the default. A float is clamped to its
    /// range and, when it has a step, rounded to the nearest multiple of the step counted from the minimum and
    /// clamped again. The clamp comes first, so the rounded value stays in range and a second normalization
    /// changes nothing. NaN falls back to the default, component by component for a color or a vector. A choice
    /// index outside the options becomes the default index, not the nearest option.
    func normalized(_ value: EffectParameterValue) -> EffectParameterValue {
        switch (self, value) {
        case (.float(let lo, let hi, let step, let fallback), .float(let input)):
            .float(snapped(bounded(input, lo, hi, fallback: fallback), to: step, lo, hi))
        case (.int(let lo, let hi, _), .int(let input)):
            .int(clamped(input, lo, hi))
        case (.bool, .bool(let input)):
            .bool(input)
        case (.color(let fallback), .color(let input)):
            .color(
                SIMD4(
                    bounded(input.x, 0, 1, fallback: fallback.x),
                    bounded(input.y, 0, 1, fallback: fallback.y),
                    bounded(input.z, 0, 1, fallback: fallback.z),
                    bounded(input.w, 0, 1, fallback: fallback.w)))
        case (.vector2(let lo, let hi, let fallback), .vector2(let input)):
            .vector2(
                SIMD2(
                    bounded(input.x, lo.x, hi.x, fallback: fallback.x),
                    bounded(input.y, lo.y, hi.y, fallback: fallback.y)))
        case (.choice(let options, let defaultIndex), .choice(let index)):
            .choice(options.indices.contains(index) ? index : defaultIndex)
        default:
            defaultValue
        }
    }
}

/// `input` within `lo...hi`, or `fallback` when `input` is NaN. NaN compares false with everything, so the
/// clamp cannot judge it and it is settled first.
private func bounded(_ input: Float, _ lo: Float, _ hi: Float, fallback: Float) -> Float {
    input.isNaN ? fallback : clamped(input, lo, hi)
}

/// `value` within `lo...hi`, as `min(max(value, lo), hi)`: it does not trap when `lo` is above `hi` (an invalid
/// manifest), and an infinity lands on the end it lies beyond.
private func clamped<T: Comparable>(_ value: T, _ lo: T, _ hi: T) -> T {
    min(max(value, lo), hi)
}

/// `value` (already within `lo...hi`) rounded to the nearest multiple of `step` counted from `lo`, then clamped
/// again. A step that is not above zero, or is infinite, leaves the value as it is: an infinite step would make
/// `0 * step` NaN.
private func snapped(_ value: Float, to step: Float?, _ lo: Float, _ hi: Float) -> Float {
    guard let step, step > 0, step.isFinite else { return value }
    return clamped(lo + ((value - lo) / step).rounded() * step, lo, hi)
}
