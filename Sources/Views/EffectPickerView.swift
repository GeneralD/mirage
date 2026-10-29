import Domain
import Presenters
import SwiftUI

/// The effect picker (#12), drawn from an `EffectPickerPresenter`: a search field, the menu's line
/// about the chosen effect when it failed to run, and a grid of cells. It maps the Presenter's
/// values to pixels and decides nothing: which cells there are, their order, the chosen one, the
/// disabled ones, their words and their tiles are the Presenter's, and the grid's columns are
/// `EffectPickerGeometry`'s for the width the window gives it.
///
/// The live camera preview #12 places above the grid is not here: the host app has no preview
/// path to draw it from (`docs/ARCHITECTURE.md` → *Effect picker*).
public struct EffectPickerView: View {
    @ObservedObject private var presenter: EffectPickerPresenter

    public init(presenter: EffectPickerPresenter) {
        self.presenter = presenter
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            TextField("Search Effects", text: $presenter.query)
                .textFieldStyle(.roundedBorder)
                .padding(EffectPickerGeometry.inset)
            if let status = presenter.status {
                Label(status, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.secondary)
                    .padding([.horizontal, .bottom], EffectPickerGeometry.inset)
            }
            Divider()
            GeometryReader { proxy in
                grid(EffectPickerGeometry(width: proxy.size.width))
            }
        }
        .frame(minWidth: 320, minHeight: 280)
    }

    private func grid(_ geometry: EffectPickerGeometry) -> some View {
        let columns = Array(
            repeating: GridItem(.fixed(geometry.cellWidth), spacing: EffectPickerGeometry.spacing),
            count: geometry.columns)
        return ScrollView {
            LazyVGrid(columns: columns, alignment: .leading, spacing: EffectPickerGeometry.spacing) {
                ForEach(presenter.cells) { cell in
                    EffectPickerCellView(cell: cell, width: geometry.cellWidth) { presenter.select(cell.id) }
                }
            }
            .padding(EffectPickerGeometry.inset)
        }
        .overlay {
            if let message = presenter.emptyMessage {
                Text(message).foregroundStyle(.secondary)
            }
        }
    }
}
