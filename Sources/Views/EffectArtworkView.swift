import Domain
import SwiftUI

/// What a picker cell draws above its name. A placeholder is a gradient of its hue with the
/// effect's initials on it; a thumbnail becomes a case of `EffectArtwork`, and an arm here, once
/// the catalog carries one (#12).
struct EffectArtworkView: View {
    let artwork: EffectArtwork

    var body: some View {
        switch artwork {
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
