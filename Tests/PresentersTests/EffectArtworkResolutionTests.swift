import Domain
import Presenters
import TestDoubles
import TestSupport
import Testing

/// What a picker cell draws once a decoder has had a look at its artwork (#12): the decision that
/// a thumbnail which does not decode is the effect's tile, never an empty cell, made without a
/// view or an image framework, over stub decoders.
@Suite("resolveArtwork", .timeLimit(.minutes(1)))
struct EffectArtworkResolutionTests {
    /// Stands for the decoded picture, which the view lane makes of a `CGImage`.
    private struct StubImage: Equatable {
        let tag: Int
    }

    private let tile = EffectPlaceholder(monogram: "GL", hue: 0.25)

    @Test(
        "a thumbnail the decoder turns into a picture is drawn as that picture, in either format, and the decoder is handed the thumbnail",
        arguments: EffectThumbnailFormat.allCases)
    func decodedThumbnailIsDrawn(format: EffectThumbnailFormat) {
        let thumbnail = EffectThumbnail.fixture(3, format: format)
        let asked = Collector<EffectThumbnail>()

        let resolution = resolveArtwork(.image(thumbnail, fallback: tile)) { thumbnail in
            asked.append(thumbnail)
            return StubImage(tag: 9)
        }

        #expect(resolution == .image(StubImage(tag: 9)))
        #expect(asked.values == [thumbnail])
    }

    @Test(
        "a thumbnail the decoder cannot decode is drawn as the tile the artwork carries, never as an empty cell",
        arguments: EffectThumbnailFormat.allCases)
    func undecodableThumbnailFallsBackToTheTile(format: EffectThumbnailFormat) {
        let asked = Collector<EffectThumbnail>()

        let resolution: EffectArtworkResolution<StubImage> = resolveArtwork(.image(.fixture(3, format: format), fallback: tile)) { thumbnail in
            asked.append(thumbnail)
            return nil
        }

        #expect(resolution == .placeholder(tile))
        #expect(asked.values.count == 1, "the decoder was tried")
    }

    @Test("a placeholder is drawn as itself, and nothing is decoded for it")
    func placeholderIsNeverDecoded() {
        let asked = Collector<EffectThumbnail>()

        let resolution: EffectArtworkResolution<StubImage> = resolveArtwork(.placeholder(tile)) { thumbnail in
            asked.append(thumbnail)
            return StubImage(tag: 1)
        }

        #expect(resolution == .placeholder(tile))
        #expect(asked.values.isEmpty)
    }

    @Test("every resolution asks the decoder afresh, so a picture that decodes later is drawn then")
    func nothingIsRemembered() {
        let artwork = EffectArtwork.image(.fixture(5), fallback: tile)
        let answers = Collector<Bool>()

        let first: EffectArtworkResolution<StubImage> = resolveArtwork(artwork) { _ in
            answers.append(false)
            return nil
        }
        let second: EffectArtworkResolution<StubImage> = resolveArtwork(artwork) { _ in
            answers.append(true)
            return StubImage(tag: 2)
        }

        #expect(first == .placeholder(tile))
        #expect(second == .image(StubImage(tag: 2)))
        #expect(answers.values == [false, true])
    }
}
