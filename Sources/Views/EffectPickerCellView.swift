import Domain
import SwiftUI

/// One cell of the effect picker: the artwork (the thumbnail, or a tile), the name, the second line,
/// an accent border on the chosen effect, and the cell's `help` when the pointer rests on it. The
/// whole cell is the button, so a click on the artwork, the words or the space between them
/// chooses the effect; a disabled cell is dimmed and takes no click.
struct EffectPickerCellView: View {
    let cell: EffectPickerCell
    let width: Double
    let decode: (EffectThumbnail) -> CGImage?
    let choose: () -> Void

    var body: some View {
        Button(action: choose) {
            VStack(alignment: .leading, spacing: 4) {
                EffectArtworkView(artwork: cell.artwork, decode: decode)
                    .frame(width: width, height: width)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .overlay {
                        RoundedRectangle(cornerRadius: 10)
                            .strokeBorder(cell.isSelected ? Color.accentColor : Color.clear, lineWidth: 3)
                    }
                Text(cell.title)
                    .font(.headline)
                    .lineLimit(1)
                Text(cell.detail ?? " ")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(width: width, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!cell.isEnabled)
        .opacity(cell.isEnabled ? 1 : 0.5)
        .help(cell.help)
    }
}
