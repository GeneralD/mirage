import Domain
import Presenters
import SwiftUI

/// The two compound controls a parameter panel row draws (#116): a color well for a color parameter and
/// two sliders for a point. Like the scalar controls (#115), each takes the values the Presenter decided
/// and a `set` that hands the user's choice back to it. The View keeps no value of its own, so what it draws
/// is always what the Presenter last sent. Rounding, clamping and wording are not here (#111, #113).
///
/// The row's label column is the row view's (#117).

/// A color well with opacity. The components are sRGB, not linear, in `0...1`, as the Presenter sends them.
struct ParameterColorControl: View {
    let title: String
    let red: Double
    let green: Double
    let blue: Double
    let opacity: Double
    let set: @MainActor (Double, Double, Double, Double) -> Void

    var body: some View {
        let (red, green, blue, opacity, set) = (red, green, blue, opacity, set)
        let binding = Binding<Color>(
            get: { Color(.sRGB, red: red, green: green, blue: blue, opacity: opacity) },
            set: { newColor in
                let resolved = newColor.resolve(in: EnvironmentValues())
                MainActor.assumeIsolated {
                    set(Double(resolved.red), Double(resolved.green), Double(resolved.blue), Double(resolved.opacity))
                }
            })
        ColorPicker(selection: binding, supportsOpacity: true) { Text(title) }
            .labelsHidden()
    }
}

/// A point: an X slider above a Y slider, each with its axis caption. Moving one passes the other's value on unchanged.
struct ParameterVectorControl: View {
    let x: ParameterPanelSlider
    let y: ParameterPanelSlider
    let set: @MainActor (Double, Double) -> Void

    var body: some View {
        let (x, y, set) = (x, y, set)
        VStack(spacing: ParameterPanelGeometry.axisSpacing) {
            ParameterSliderControl(slider: x) { newX in set(newX, y.value) }
            ParameterSliderControl(slider: y) { newY in set(x.value, newY) }
        }
    }
}
