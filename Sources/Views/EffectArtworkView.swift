import Domain
import Presenters
import SwiftUI

/// What a picker cell draws above its name: a thumbnail filling the square, or a placeholder, which
/// is a gradient of its hue with the effect's initials on it. Which of the two is not decided here:
/// `resolveArtwork` hands the thumbnail to `decode` and answers the tile when it does not decode,
/// and this view maps its answer to pixels. `decode` is the host's (`AppRouter`), since the call
/// that makes a picture of bytes is not a declaration, and `Views` holds declarations only.
struct EffectArtworkView: View {
    let artwork: EffectArtwork
    let decode: (EffectThumbnail) -> CGImage?

    var body: some View {
        switch resolveArtwork(artwork, decode: decode) {
        case .image(let image):
            Image(decorative: image, scale: 1)
                .resizable()
                .scaledToFill()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
        case .placeholder(let placeholder):
            ZStack {
                LinearGradient(
                    colors: [
                        Color(hue: placeholder.hue, saturation: 0.45, brightness: 0.9),
                        Color(hue: placeholder.hue, saturation: 0.7, brightness: 0.55),
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing)
                Text(placeholder.monogram)
                    .font(.system(size: 36, weight: .semibold, design: .rounded))
                    .minimumScaleFactor(0.5)
                    .foregroundStyle(.white.opacity(0.9))
            }
        }
    }
}
