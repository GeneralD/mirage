import Dependencies
import Domain
import Foundation
import HostDependencyInjection
import ImageIOGateway
import TestDoubles
import TestSupport
import Testing

@testable import LensTool

/// The `lens` command line over the live stack, with no camera. The authoring use case, the effect runtime, the Metal,
/// IOSurface and ImageIO gateways and the file system are the host's live registrations; the console is the only fake.
/// Every pixel is compared with the Swift reference the GPU suites already use, within `GPUSmokeSupport.tolerance`.
///
/// **The seed.** The runtime draws a session's noise seed from `RandomSource` (#512), and `render` starts a session at
/// frame 0, so the live draw would change the grain on every run. `lens` pins that draw to 0, the seed the Chromatic
/// Grain reference is computed for; the other keys are the live values.
@Suite("Lens tool over the real stack", .serialized, .enabled(if: MetalDeviceProbe.isAvailable), .timeLimit(.minutes(1)))
struct LensToolRenderSmokeTests {
    private static let width = 18
    private static let height = 10

    // MARK: - Helpers

    /// The `lens` command over the live stack, its console recording: the exit code and both streams.
    private func lens(_ arguments: [String]) async -> (code: Int32, out: [String], err: [String]) {
        let console = RecordingConsole()
        let tool = withDependencies {
            $0.context = .live
            $0.consoleWriter = console
            $0.randomSource = ZeroRandomSource()
        } operation: {
            LensToolMain()
        }
        let code = await tool.run(arguments)
        return (code, console.lines.values, console.errorLines.values)
    }

    /// A new folder under the temporary directory, named by a UUID. The test removes it when it ends.
    private static func scratch() throws -> String {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder.path
    }

    /// The 18 x 10 input of every check: `ChromaticGrainReference.input`, row by row, encoded as a PNG at `path`.
    private static func writeInput(at path: String) throws {
        let bgra = (0..<height).flatMap { y in (0..<width).flatMap { x in ChromaticGrainReference.input(x, y) } }
        let png = try ImageIOGatewayImpl().encodePNG(StillImage(width: width, height: height, bgra: bgra))
        try png.write(to: URL(fileURLWithPath: path))
    }

    /// The image at `path`, decoded by ImageIO: `[B, G, R, A]` pixels with the rows packed.
    private static func decode(at path: String) throws -> StillImage {
        try ImageIOGatewayImpl().decode(Data(contentsOf: URL(fileURLWithPath: path)))
    }

    /// The `[B, G, R, A]` pixel of `image` at `(x, y)`.
    private static func pixel(of image: StillImage, x: Int, y: Int) -> [UInt8] {
        let start = (y * image.width + x) * 4
        return Array(image.bgra[start..<start + 4])
    }

    /// The largest channel difference between `image` and `expected`, over every pixel of the 18 x 10 image.
    private static func worstDifference(in image: StillImage, from expected: (Int, Int) -> [UInt8]) -> Int {
        (0..<height).flatMap { y in
            (0..<width).map { x in GPUSmokeSupport.distance(pixel(of: image, x: x, y: y), expected(x, y)) }
        }.max() ?? 0
    }

    // MARK: - Rendering

    @Test("rendering the bundled Chromatic Grain exits 0, names the output, and matches its reference in every pixel")
    func rendersTheBundledChromaticGrain() async throws {
        let folder = try Self.scratch()
        defer { try? FileManager.default.removeItem(atPath: folder) }
        let input = folder + "/in.png"
        let output = folder + "/out.png"
        try Self.writeInput(at: input)

        let result = await lens(["render", "Chromatic Grain", "--input", input, "--output", output])

        #expect(result.code == 0)
        #expect(result.out == ["Wrote \(output) (18x10) with Chromatic Grain"])
        #expect(result.err.isEmpty)
        let image = try Self.decode(at: output)
        #expect(image.width == Self.width && image.height == Self.height)
        let uniforms = EffectUniforms(time: 0, frameIndex: 0, resolution: SIMD2(18, 10), seed: 0)
        let worst = Self.worstDifference(in: image) { x, y in
            ChromaticGrainReference.pixel(
                x: x, y: y, uniforms: uniforms, width: Self.width, height: Self.height, input: ChromaticGrainReference.input)
        }
        #expect(worst <= GPUSmokeSupport.tolerance, "worst channel difference \(worst)")
    }

    @Test("a package made by new validates, and renders every pixel inverted within one 8-bit step")
    func scaffoldedPackageValidatesAndInverts() async throws {
        let folder = try Self.scratch()
        defer { try? FileManager.default.removeItem(atPath: folder) }
        let input = folder + "/in.png"
        let output = folder + "/out.png"
        let lensPackage = folder + "/Invert.lens"
        try Self.writeInput(at: input)

        let created = await lens(["new", "Invert", "--in", folder])
        #expect(created.code == 0)
        #expect(created.out == ["Created \(lensPackage)"])
        #expect(created.err.isEmpty)

        let validated = await lens(["validate", lensPackage])
        #expect(validated.code == 0)
        #expect(validated.out == ["Invert: OK, 1 parameter"])
        #expect(validated.err.isEmpty)

        let rendered = await lens(["render", lensPackage, "--input", input, "--output", output])
        #expect(rendered.code == 0)
        #expect(rendered.out == ["Wrote \(output) (18x10) with \(lensPackage)"])
        #expect(rendered.err.isEmpty)
        let image = try Self.decode(at: output)
        let worst = Self.worstDifference(in: image) { x, y in
            let source = ChromaticGrainReference.input(x, y)
            return [255 - source[0], 255 - source[1], 255 - source[2], 255]
        }
        #expect(worst <= GPUSmokeSupport.tolerance, "worst channel difference \(worst)")
    }

    // MARK: - Failures

    @Test("a shader that does not compile fails validate with exit 1 and one error line that names the author's line 3")
    func brokenKernelFailsValidation() async throws {
        let folder = try Self.scratch()
        defer { try? FileManager.default.removeItem(atPath: folder) }
        let lensPackage = folder + "/Invert.lens"
        _ = await lens(["new", "Invert", "--in", folder])
        let broken = [
            "kernel void effect(texture2d<float, access::write> out [[texture(0)]],",
            "                   uint2 gid [[thread_position_in_grid]]) {",
            "    float broken = 1.0 +;",
        ].joined(separator: "\n")
        try broken.write(toFile: lensPackage + "/effect.metal", atomically: true, encoding: .utf8)

        let validated = await lens(["validate", lensPackage])

        #expect(validated.code == 1)
        #expect(validated.out.isEmpty)
        #expect(validated.err.count == 1, "\(validated.err)")
        #expect(validated.err.first?.hasPrefix("error: the shader does not compile") == true, "\(validated.err)")
        #expect(validated.err.first?.contains("effect:3:") == true, "\(validated.err)")
    }

    @Test("a missing input exits 1 with the unreadable path on standard error, and writes no output")
    func missingInputWritesNothing() async throws {
        let folder = try Self.scratch()
        defer { try? FileManager.default.removeItem(atPath: folder) }
        let input = folder + "/missing.png"
        let output = folder + "/out.png"

        let result = await lens(["render", "Chromatic Grain", "--input", input, "--output", output])

        #expect(result.code == 1)
        #expect(result.err == ["error: cannot read \(input)"])
        #expect(result.out.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: output))
    }

    @Test("an input that is not an image exits 1 with its path on standard error")
    func textInputIsRefused() async throws {
        let folder = try Self.scratch()
        defer { try? FileManager.default.removeItem(atPath: folder) }
        let input = folder + "/notes.txt"
        try "not a picture".write(toFile: input, atomically: true, encoding: .utf8)

        let result = await lens(["render", "Chromatic Grain", "--input", input, "--output", folder + "/out.png"])

        #expect(result.code == 1)
        #expect(result.err == ["error: \(input) is not an image the tool can read"])
        #expect(result.out.isEmpty)
    }

    @Test("a bundled name the app does not ship exits 1 with the name on standard error, and writes no output")
    func unknownBundledNameWritesNothing() async throws {
        let folder = try Self.scratch()
        defer { try? FileManager.default.removeItem(atPath: folder) }
        let input = folder + "/in.png"
        let output = folder + "/out.png"
        try Self.writeInput(at: input)

        let result = await lens(["render", "Nope", "--input", input, "--output", output])

        #expect(result.code == 1)
        #expect(result.err == ["error: no bundled effect is named \"Nope\""])
        #expect(result.out.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: output))
    }

    @Test("render without an effect exits 2 with the missing argument and the usage on standard error")
    func renderWithoutEffectIsAUsageError() async {
        let result = await lens(["render"])

        #expect(result.code == 2)
        #expect(result.err.first == "error: missing effect")
        #expect(result.err.count == 2, "\(result.err)")
        #expect(result.out.isEmpty)
    }
}
