import Presenters
import SwiftUI

/// The live preview pane above the effect picker's grid (#68), drawn from a `PreviewPresenter`: a black
/// rounded rectangle the size `PreviewGeometry` gives, the preview view over it and, when the pipeline
/// refused that view, the words that say why, centered in white. It maps the Presenter's values to pixels
/// and decides nothing: whether the view is attached is the Presenter's, and the frames are drawn into the
/// view's `MTKView` by the pipeline's sink.
struct PreviewPaneView: View {
    @ObservedObject private var preview: PreviewPresenter
    private let geometry: PreviewGeometry

    init(preview: PreviewPresenter, geometry: PreviewGeometry) {
        self.preview = preview
        self.geometry = geometry
    }

    var body: some View {
        ZStack {
            Color.black
                .frame(width: geometry.width, height: geometry.height)
                .clipShape(RoundedRectangle(cornerRadius: PreviewGeometry.cornerRadius))
            PreviewView(onTarget: { target in Task { @MainActor in preview.receive(target) } })
                .frame(width: geometry.width, height: geometry.height)
                .clipShape(RoundedRectangle(cornerRadius: PreviewGeometry.cornerRadius))
            if let message = preview.unavailableMessage {
                Text(message)
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .padding(EffectPickerGeometry.inset)
            }
        }
        .frame(width: geometry.width, height: geometry.height)
        .accessibilityLabel(preview.accessibilityLabel)
        .frame(maxWidth: .infinity)
        .padding(.bottom, EffectPickerGeometry.inset)
    }
}
