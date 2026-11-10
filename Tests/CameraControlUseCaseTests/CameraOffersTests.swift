import Domain
import Testing

@testable import CameraControlUseCase

@Suite("CameraOffers", .timeLimit(.minutes(1)))
struct CameraOffersTests {
    private func format(_ index: Int, _ width: Int, _ height: Int, fps: ClosedRange<Int> = 1...60) -> CameraFormat {
        CameraFormat(
            index: index,
            width: width,
            height: height,
            minFramesPerSecond: fps.lowerBound,
            maxFramesPerSecond: fps.upperBound)
    }

    private func resolution(_ width: Int, _ height: Int) -> CameraResolution {
        CameraResolution(width: width, height: height)
    }

    @Test("only 16:9 resolutions from 1280 to 1920 pixels wide are offered; the others are not")
    func offersOnly16x9WidthsFrom1280To1920() {
        let offers = CameraOffers(formats: [
            format(0, 640, 480),
            format(1, 1152, 648),  // 16:9, but narrower than 1280
            format(2, 1280, 1024),  // not 16:9
            format(3, 1440, 1080),  // not 16:9, inside the width range
            format(4, 1366, 768),  // close to 16:9, but not exactly
            format(5, 1280, 720),
            format(6, 1920, 1080),
            format(7, 2560, 1440),  // 16:9, but wider than 1920
            format(8, 3840, 2160),
        ])
        #expect(offers.resolutions == [resolution(1280, 720), resolution(1920, 1080)])
    }

    @Test("formats of one resolution are offered as one resolution, and the resolutions come in ascending width")
    func dedupesAndSortsByWidth() {
        let offers = CameraOffers(formats: [
            format(0, 1920, 1080),
            format(1, 1280, 720),
            format(2, 1920, 1080),
            format(3, 1280, 720),
        ])
        #expect(offers.resolutions == [resolution(1280, 720), resolution(1920, 1080)])
    }

    @Test("only the frame rates 15, 24 and 30 are offered, so 60 is not offered even when a format supports it")
    func frameRatesAreOnly15_24_30() {
        let all = CameraOffers(formats: [format(0, 1280, 720, fps: 1...60)])
        #expect(all.frameRates(at: resolution(1280, 720)) == [15, 24, 30])

        let some = CameraOffers(formats: [format(0, 1280, 720, fps: 20...29)])
        #expect(some.frameRates(at: resolution(1280, 720)) == [24])
    }

    @Test("a frame rate is offered when some format of the resolution supports it, even if another format does not")
    func frameRateOfAnotherFormatCounts() {
        let offers = CameraOffers(formats: [
            format(0, 1280, 720, fps: 15...24),
            format(1, 1280, 720, fps: 30...30),
        ])
        #expect(offers.frameRates(at: resolution(1280, 720)) == [15, 24, 30])
    }

    @Test("a resolution whose formats support none of 15, 24 and 30 is not offered")
    func resolutionWithoutOfferedRateIsNotOffered() {
        let offers = CameraOffers(formats: [format(0, 1280, 720, fps: 60...60)])
        #expect(offers.resolutions.isEmpty)
        #expect(offers.frameRates(at: resolution(1280, 720)).isEmpty)
    }

    @Test("choice is the supporting format with the lowest index, not the first one in the list")
    func choiceIsLowestIndexSupportingRate() {
        let offers = CameraOffers(formats: [
            format(5, 1280, 720, fps: 1...30),
            format(4, 1280, 720, fps: 15...24),  // lower index, but it does not support 30
            format(2, 1280, 720, fps: 20...30),
            format(7, 1280, 720, fps: 1...30),
            format(0, 1920, 1080, fps: 1...30),  // another resolution
        ])
        #expect(
            offers.choice(at: resolution(1280, 720), framesPerSecond: 30)
                == CameraFormatChoice(index: 2, framesPerSecond: 30))
        #expect(
            offers.choice(at: resolution(1280, 720), framesPerSecond: 15)
                == CameraFormatChoice(index: 4, framesPerSecond: 15))
    }

    @Test("choice is nil when no format of the resolution supports the frame rate")
    func choiceIsNilWithoutSupportingFormat() {
        let offers = CameraOffers(formats: [
            format(0, 1280, 720, fps: 1...15),
            format(1, 1920, 1080, fps: 1...30),
        ])
        #expect(offers.choice(at: resolution(1280, 720), framesPerSecond: 30) == nil)
    }

    @Test("with no formats, no resolutions and no frame rates are offered")
    func emptyFormatsOfferNothing() {
        let offers = CameraOffers(formats: [])
        #expect(offers.resolutions.isEmpty)
        #expect(offers.frameRates(at: resolution(1280, 720)).isEmpty)
    }
}
