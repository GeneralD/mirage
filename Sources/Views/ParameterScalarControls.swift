import Domain
import Presenters
import SwiftUI

/// The four controls a parameter panel row draws for a scalar value (#115): a slider, a stepper, a switch
/// and a menu picker. Each takes the value the Presenter decided and a `set` that hands the user's choice
/// back to it. The View keeps no value of its own, so what it draws is always what the Presenter last sent.
/// Rounding, clamping and wording are not here: the value is already in range and `text` is already the
/// value as the row shows it (#111, #113).
///
/// Every control hides its own label with `labelsHidden()` and keeps the title only as the name VoiceOver
/// reads. The row's label column is the row view's (#117).

/// A slider, with an optional caption before it and the value as text after it.
struct ParameterSliderControl: View {
    let slider: ParameterPanelSlider
    let set: @MainActor (Double) -> Void

    var body: some View {
        let (value, set) = (slider.value, set)
        let binding = Binding(get: { value }, set: { newValue in MainActor.assumeIsolated { set(newValue) } })
        HStack {
            if let caption = slider.caption {
                Text(caption)
                    .foregroundStyle(.secondary)
            }
            if let step = slider.step {
                Slider(value: binding, in: slider.range, step: step) { Text(slider.title) }
                    .labelsHidden()
            } else {
                Slider(value: binding, in: slider.range) { Text(slider.title) }
                    .labelsHidden()
            }
            Text(slider.text)
                .monospacedDigit()
                .frame(width: ParameterPanelGeometry.valueWidth, alignment: .trailing)
        }
    }
}

/// A stepper, with the value as text before it.
struct ParameterStepperControl: View {
    let title: String
    let value: Int
    let range: ClosedRange<Int>
    let text: String
    let set: @MainActor (Int) -> Void

    var body: some View {
        let (value, set) = (value, set)
        let binding = Binding(get: { value }, set: { newValue in MainActor.assumeIsolated { set(newValue) } })
        HStack {
            Text(text)
                .monospacedDigit()
                .frame(width: ParameterPanelGeometry.valueWidth, alignment: .trailing)
            Stepper(value: binding, in: range) { Text(title) }
                .labelsHidden()
        }
    }
}

/// A switch: on or off, as the Presenter says.
struct ParameterToggleControl: View {
    let title: String
    let isOn: Bool
    let set: @MainActor (Bool) -> Void

    var body: some View {
        let (isOn, set) = (isOn, set)
        let binding = Binding(get: { isOn }, set: { newValue in MainActor.assumeIsolated { set(newValue) } })
        Toggle(isOn: binding) { Text(title) }
            .labelsHidden()
            .toggleStyle(.switch)
    }
}

/// A menu picker over the Presenter's options; `selection` is the index of the chosen one.
struct ParameterPickerControl: View {
    let title: String
    let selection: Int
    let options: [String]
    let set: @MainActor (Int) -> Void

    var body: some View {
        let (selection, set) = (selection, set)
        let binding = Binding(get: { selection }, set: { newValue in MainActor.assumeIsolated { set(newValue) } })
        Picker(selection: binding) {
            ForEach(options.indices, id: \.self) { Text(options[$0]).tag($0) }
        } label: {
            Text(title)
        }
        .labelsHidden()
        .pickerStyle(.menu)
    }
}
