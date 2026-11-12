import Presenters
import SwiftUI

/// The effect parameter panel (#117), drawn from a `ParameterPanelPresenter`: the chosen effect's name, a row for each of its
/// parameters, and the `Reset` button. It maps the Presenter's values to pixels and decides nothing: the heading, the rows, the
/// words and whether the list is empty are the Presenter's, and the column widths and spacing are `ParameterPanelGeometry`'s for
/// the width the window gives it.
public struct ParameterPanelView: View {
    @ObservedObject private var presenter: ParameterPanelPresenter

    public init(presenter: ParameterPanelPresenter) {
        self.presenter = presenter
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(presenter.heading)
                .font(.headline)
                .padding(ParameterPanelGeometry.inset)
            Divider()
            GeometryReader { proxy in
                rows(ParameterPanelGeometry(width: proxy.size.width))
            }
            Divider()
            HStack {
                Spacer()
                Button(presenter.resetTitle) { presenter.reset() }
                    .disabled(presenter.rows.isEmpty)
            }
            .padding(ParameterPanelGeometry.inset)
        }
        .frame(minWidth: ParameterPanelGeometry.minimumWidth, minHeight: ParameterPanelGeometry.minimumHeight)
    }

    private func rows(_ geometry: ParameterPanelGeometry) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: ParameterPanelGeometry.spacing) {
                ForEach(presenter.rows) { row in
                    ParameterRowView(row: row, geometry: geometry, presenter: presenter)
                        .accessibilityElement(children: .contain)
                }
            }
            .padding(ParameterPanelGeometry.inset)
        }
        .overlay {
            if let message = presenter.emptyMessage {
                Text(message).foregroundStyle(.secondary)
            }
        }
    }
}
