import Domain
import Presenters
import SwiftUI

/// One row of the parameter panel (#117): the row's label in a column on the left and the control for its kind in a column on
/// the right, both at the widths `ParameterPanelGeometry` gives the panel. The control is the one the Presenter chose for the row,
/// and each control hands the user's choice back through the Presenter's setter for it. The switch names all six kinds and has
/// no `default`, so a new kind is a compile error here rather than a row that is never drawn.
struct ParameterRowView: View {
    let row: ParameterPanelRow
    let geometry: ParameterPanelGeometry
    let presenter: ParameterPanelPresenter

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: ParameterPanelGeometry.spacing) {
            Text(row.label)
                .lineLimit(ParameterPanelGeometry.labelLineLimit)
                .multilineTextAlignment(.trailing)
                .frame(width: geometry.labelWidth, alignment: .trailing)
            control
                .frame(width: geometry.controlWidth, alignment: .leading)
        }
    }

    @ViewBuilder
    private var control: some View {
        switch row.control {
        case .slider(let slider):
            ParameterSliderControl(slider: slider) { presenter.setFloat(row.id, to: $0) }
        case .stepper(let value, let range, let text):
            ParameterStepperControl(title: row.label, value: value, range: range, text: text) { presenter.setInt(row.id, to: $0) }
        case .toggle(let isOn):
            ParameterToggleControl(title: row.label, isOn: isOn) { presenter.setBool(row.id, to: $0) }
        case .color(let red, let green, let blue, let opacity):
            ParameterColorControl(title: row.label, red: red, green: green, blue: blue, opacity: opacity) {
                presenter.setColor(row.id, red: $0, green: $1, blue: $2, opacity: $3)
            }
        case .vector(let x, let y):
            ParameterVectorControl(x: x, y: y) { presenter.setVector(row.id, x: $0, y: $1) }
        case .picker(let selection, let options):
            ParameterPickerControl(title: row.label, selection: selection, options: options) { presenter.setChoice(row.id, to: $0) }
        }
    }
}
