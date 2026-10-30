import AppKit
import Domain

/// Turns a package's thumbnail into the picture a picker cell draws (#12), or says it cannot. The
/// catalog hands over bytes that passed a size and signature check only, so this is where a
/// thumbnail meets a real decoder. It lives with the Router, not in `Views`, which is
/// coverage-ignored and holds declarations only; `EffectPickerWindow` gives it to the view, and
/// `resolveArtwork` (`Presenters`) turns an answer of `nil` into the effect's tile.
enum EffectThumbnailDecoding {
    /// The most pixels a thumbnail may have to be drawn: 2048 × 2048. A cell is a few hundred
    /// points wide, so a picture beyond this adds nothing a viewer sees, while a PNG within the
    /// catalog's 1 MiB can claim sides of tens of thousands of pixels, which draws into hundreds of
    /// megabytes; a thumbnail over the limit is not decoded and the cell draws its tile.
    static let maxPixels = 2048 * 2048

    /// The thumbnail as an image, or `nil` when it has no pixels to draw: its bytes are not a
    /// complete picture header, they decode to nothing, or it is over `maxPixels`. Not
    /// `NSImage(data:)`, which answers an image with no size for bytes that carry only a
    /// signature, and that would draw an empty cell.
    static func image(of thumbnail: EffectThumbnail) -> CGImage? {
        guard let bitmap = NSBitmapImageRep(data: thumbnail.data), bitmap.pixelsWide * bitmap.pixelsHigh <= maxPixels else { return nil }
        return bitmap.cgImage
    }
}
