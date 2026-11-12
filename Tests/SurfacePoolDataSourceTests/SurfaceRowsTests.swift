import Testing

@testable import SurfacePoolDataSource

@Suite("SurfaceRows")
struct SurfaceRowsTests {
    /// A picture's width and height, and the extra bytes a surface row carries after its pixels.
    struct Geometry: Sendable {
        let width: Int
        let height: Int
        let padding: Int

        var bytesPerRow: Int { width * 4 + padding }

        static let all: [Geometry] = [1, 5, 64, 163].flatMap { width in
            [1, 3].flatMap { height in
                [0, 4, 28].map { padding in Geometry(width: width, height: height, padding: padding) }
            }
        }
    }

    @Test("when bytesPerRow equals width * 4, padded and packed both return their input unchanged")
    func tightStrideIsIdentity() {
        let bytes = (0..<16).map { UInt8($0) }
        #expect(SurfaceRows.padded(bytes, width: 2, height: 2, bytesPerRow: 8) == bytes)
        #expect(SurfaceRows.packed(bytes, width: 2, height: 2, bytesPerRow: 8) == bytes)
    }

    @Test("padded adds four zeros after each 8 byte row of a 2 by 2 image with bytesPerRow 12")
    func paddedAddsZerosAfterEachRow() {
        let bytes: [UInt8] = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16]
        let expected: [UInt8] = [
            1, 2, 3, 4, 5, 6, 7, 8, 0, 0, 0, 0,
            9, 10, 11, 12, 13, 14, 15, 16, 0, 0, 0, 0,
        ]
        #expect(SurfaceRows.padded(bytes, width: 2, height: 2, bytesPerRow: 12) == expected)
    }

    @Test("packed ignores what the padding holds, so 0xFF in the padding still gives back the original 16 bytes")
    func packedIgnoresPaddingContents() {
        let surface: [UInt8] = [
            1, 2, 3, 4, 5, 6, 7, 8, 0xFF, 0xFF, 0xFF, 0xFF,
            9, 10, 11, 12, 13, 14, 15, 16, 0xFF, 0xFF, 0xFF, 0xFF,
        ]
        #expect(SurfaceRows.packed(surface, width: 2, height: 2, bytesPerRow: 12) == (1...16).map { UInt8($0) })
    }

    @Test("a 1 by 1 image with bytesPerRow 16 survives padded and then packed unchanged")
    func singlePixelRoundTrip() throws {
        let pixel: [UInt8] = [10, 20, 30, 40]
        let padded = try #require(SurfaceRows.padded(pixel, width: 1, height: 1, bytesPerRow: 16))
        #expect(padded == pixel + [UInt8](repeating: 0, count: 12))
        #expect(SurfaceRows.packed(padded, width: 1, height: 1, bytesPerRow: 16) == pixel)
    }

    @Test("padded and then packed gives back the original bytes for every width, height and padding", arguments: Geometry.all)
    func roundTripForEveryGeometry(_ geometry: Geometry) throws {
        let original = (0..<(geometry.width * geometry.height * 4)).map { UInt8(truncatingIfNeeded: $0) }
        let padded = try #require(
            SurfaceRows.padded(original, width: geometry.width, height: geometry.height, bytesPerRow: geometry.bytesPerRow))
        #expect(padded.count == geometry.bytesPerRow * geometry.height)
        #expect(
            SurfaceRows.packed(padded, width: geometry.width, height: geometry.height, bytesPerRow: geometry.bytesPerRow) == original)
    }

    @Test("padded answers nil for a byte count that does not match, a stride below width * 4, a zero or negative width and a zero height")
    func paddedRefusesBadInput() {
        #expect(SurfaceRows.padded([UInt8](repeating: 0, count: 15), width: 2, height: 2, bytesPerRow: 8) == nil)
        #expect(SurfaceRows.padded([UInt8](repeating: 0, count: 14), width: 2, height: 2, bytesPerRow: 7) == nil)
        #expect(SurfaceRows.padded([], width: 0, height: 2, bytesPerRow: 0) == nil)
        #expect(SurfaceRows.padded([UInt8](repeating: 0, count: 16), width: -2, height: 2, bytesPerRow: 8) == nil)
        #expect(SurfaceRows.padded([], width: 2, height: 0, bytesPerRow: 8) == nil)
    }

    @Test("packed answers nil for a byte count that does not match, a stride below width * 4, a zero or negative width and a zero height")
    func packedRefusesBadInput() {
        #expect(SurfaceRows.packed([UInt8](repeating: 0, count: 23), width: 2, height: 2, bytesPerRow: 12) == nil)
        #expect(SurfaceRows.packed([UInt8](repeating: 0, count: 14), width: 2, height: 2, bytesPerRow: 7) == nil)
        #expect(SurfaceRows.packed([], width: 0, height: 2, bytesPerRow: 0) == nil)
        #expect(SurfaceRows.packed([UInt8](repeating: 0, count: 16), width: -2, height: 2, bytesPerRow: 8) == nil)
        #expect(SurfaceRows.packed([], width: 2, height: 0, bytesPerRow: 8) == nil)
    }
}
