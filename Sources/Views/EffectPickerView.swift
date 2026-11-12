import Domain
import Presenters
import SwiftUI

/// The effect picker (#12), drawn from an `EffectPickerPresenter`: a search field, the menu's line
/// about the chosen effect when it failed to run, and a grid of cells. It maps the Presenter's
/// values to pixels and decides nothing: which cells there are, their order, the chosen one, the
/// disabled ones, their words and their artwork are the Presenter's, and the grid's columns are
/// `EffectPickerGeometry`'s for the width the window gives it. `decode` turns a thumbnail's bytes
/// into a picture, or `nil` when they are not one, and the cell then draws its tile.
///
/// When the window gives a `PreviewPresenter`, the live preview pane (#68) sits above the grid, below
/// the status line; without one the picker is the grid alone. `PreviewPaneView` maps the preview's
/// values to pixels, and the frames are drawn into its `MTKView` by the pipeline's sink, not here
/// (`docs/ARCHITECTURE.md` → *Effect picker*).
public struct EffectPickerView: View {
    @ObservedObject private var presenter: EffectPickerPresenter
    private let preview: PreviewPresenter?
    private let decode: (EffectThumbnail) -> CGImage?

    public init(
        presenter: EffectPickerPresenter, preview: PreviewPresenter? = nil,
        decode: @escaping (EffectThumbnail) -> CGImage?
    ) {
        self.presenter = presenter
        self.preview = preview
        self.decode = decode
    }

    public var body: some View {
        GeometryReader { proxy in
            VStack(alignment: .leading, spacing: 0) {
                TextField("Search Effects", text: $presenter.query)
                    .textFieldStyle(.roundedBorder)
                    .padding(EffectPickerGeometry.inset)
                if let status = presenter.status {
                    Label(status, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.secondary)
                        .padding([.horizontal, .bottom], EffectPickerGeometry.inset)
                }
                if let preview {
                    PreviewPaneView(preview: preview, geometry: PreviewGeometry(containerWidth: proxy.size.width))
                }
                Divider()
                GeometryReader { gridProxy in
                    grid(EffectPickerGeometry(width: gridProxy.size.width))
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .top)
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
                    EffectPickerCellView(cell: cell, width: geometry.cellWidth, decode: decode) { presenter.select(cell.id) }
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
