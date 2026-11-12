import Domain
import EffectPackageDataSource
import Foundation
import TestSupport
import Testing

/// The example packages and the authoring page, run on the real compiler and GPU. Every `Examples/` package compiles and renders
/// opaque at its defaults; the two with knobs are held to fixed pixels; the scaffold's template and the tutorial's kernel render as
/// the page says. One pass per case and no sleeps. Without a Metal device the suite is skipped.
@Suite("Example effects smoke", .serialized, .enabled(if: MetalDeviceProbe.isAvailable), .timeLimit(.minutes(1)))
struct ExampleEffectsSmokeTests {
    /// The repository's `Examples/`, found from this file three folders down (`ExamplePackagesTests` finds it the same way).
    static let examples = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appending(path: "Examples", directoryHint: .isDirectory)

    /// The folder names of the packages in `Examples/`, in plain string order.
    static func packageFolders() throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: examples.path).filter { $0.hasSuffix(".lens") }.sorted()
    }

    /// The folder names the parameterised test runs over. When `Examples/` cannot be read the list is empty, and
    /// `examplesAreRippleTintAndParameterTour` fails on the read itself.
    static let exampleFolders = (try? ExampleEffectsSmokeTests.packageFolders()) ?? []

    /// The package in `Examples/<folder>` as the author's source: its manifest decoded, its `effect.metal` read as text.
    static func example(_ folder: String) throws -> EffectSource {
        let package = examples.appending(path: folder, directoryHint: .isDirectory)
        let manifest = try EffectManifestDecoding.decode(
            String(contentsOf: package.appending(path: "manifest.json"), encoding: .utf8)
        ).get()
        let source = try String(contentsOf: package.appending(path: "effect.metal"), encoding: .utf8)
        return EffectSource(name: manifest.name, source: source, parameters: manifest.parameters)
    }

    /// The parameters a manifest text declares.
    static func parameters(decoding text: String) throws -> [EffectParameterSpec] {
        try EffectManifestDecoding.decode(text).get().parameters
    }

    /// The scaffold's template as `lens-tool new <name>` writes it: the kernel the template declares and the manifest's parameters.
    static func template(named name: String) throws -> EffectSource {
        let specs = try parameters(decoding: EffectScaffoldTemplate.manifest(named: name))
        return EffectSource(name: name, source: EffectScaffoldTemplate.effectSource, parameters: specs)
    }

    /// The kernel the tutorial asks the author to write: the `metal` fence marked `result=effect`, over the parameters the scaffold
    /// gives `Swap`.
    static func tutorialKernel() throws -> EffectSource {
        let document = try MarkdownFences.read("docs/authoring/first-effect.md")
        let kernel = try #require(
            MarkdownFences.all(in: document).first { $0.language == "metal" && $0.attributes["result"] == "effect" })
        let specs = try parameters(decoding: EffectScaffoldTemplate.manifest(named: "Swap"))
        return EffectSource(name: "Swap", source: kernel.text, parameters: specs)
    }

    /// Each parameter at the default its kind declares: a choice at its `defaultIndex`.
    static func defaults(of specs: [EffectParameterSpec]) -> [EffectParameterValue] {
        specs.map { defaultValue(of: $0.kind) }
    }

    private static func defaultValue(of kind: EffectParameterKind) -> EffectParameterValue {
        switch kind {
        case .float(_, _, _, let defaultValue): .float(defaultValue)
        case .int(_, _, let defaultValue): .int(defaultValue)
        case .bool(let defaultValue): .bool(defaultValue)
        case .color(let defaultValue): .color(defaultValue)
        case .vector2(_, _, let defaultValue): .vector2(defaultValue)
        case .choice(_, let defaultIndex): .choice(defaultIndex)
        }
    }

    /// Every coordinate of the rig's picture, in row order.
    static let coordinates: [(x: Int, y: Int)] = (0..<EffectSmokeRig.height).flatMap { y in
        (0..<EffectSmokeRig.width).map { (x: $0, y: y) }
    }

    /// The coordinates whose pixel is not `expected` within the GPU tolerance.
    static func mismatches(_ pixels: SurfacePixels, expected: (Int, Int) -> [UInt8]) -> [(x: Int, y: Int)] {
        coordinates.filter { GPUSmokeSupport.distance(pixels.pixel(x: $0.x, y: $0.y), expected($0.x, $0.y)) > GPUSmokeSupport.tolerance }
    }

    /// The pixel at `(x, y)` is `expected` within the GPU tolerance.
    static func expectPixel(_ pixels: SurfacePixels, _ x: Int, _ y: Int, is expected: [UInt8]) {
        let actual = pixels.pixel(x: x, y: y)
        #expect(GPUSmokeSupport.distance(actual, expected) <= GPUSmokeSupport.tolerance, "(\(x), \(y)) is \(actual), not \(expected)")
    }

    /// Every pixel is the input the rig writes, within the GPU tolerance.
    static func expectUnchanged(_ pixels: SurfacePixels) {
        let changed = mismatches(pixels) { EffectSmokeRig.testImage($0, $1) }
        #expect(changed.isEmpty, "\(changed.count) pixels differ from the input")
    }

    @Test("Examples/ holds the three packages Ripple, Tint and ParameterTour, and nothing else")
    func examplesAreRippleTintAndParameterTour() throws {
        let folders = try ExampleEffectsSmokeTests.packageFolders()
        #expect(folders == ["ParameterTour.lens", "Ripple.lens", "Tint.lens"])
    }

    @Test(
        "a package under Examples/ compiles on the real compiler and renders every pixel opaque at its default values",
        arguments: ExampleEffectsSmokeTests.exampleFolders
    )
    func everyExampleCompilesAndRendersOpaque(_ folder: String) async throws {
        let effect = try ExampleEffectsSmokeTests.example(folder)
        let pixels = try await EffectSmokeRig.render(effect, values: ExampleEffectsSmokeTests.defaults(of: effect.parameters))
        let translucent = ExampleEffectsSmokeTests.coordinates.filter { pixels.pixel(x: $0.x, y: $0.y)[3] != 255 }
        #expect(translucent.isEmpty, "\(folder): \(translucent.count) pixels are not opaque")
    }

    @Test("Tint at its defaults keeps (0, 0) black and mixes (159, 95) half way towards the tint, to [94, 43, 209, 255]")
    func tintAtItsDefaultsMixesHalfWay() async throws {
        let effect = try ExampleEffectsSmokeTests.example("Tint.lens")
        let pixels = try await EffectSmokeRig.render(effect, values: ExampleEffectsSmokeTests.defaults(of: effect.parameters))
        ExampleEffectsSmokeTests.expectPixel(pixels, 0, 0, is: [0, 0, 0, 255])
        ExampleEffectsSmokeTests.expectPixel(pixels, 159, 95, is: [94, 43, 209, 255])
    }

    @Test("Tint at amount 1 multiplies the picture by the tint, so (159, 95) becomes [71, 38, 209, 255]")
    func tintAtFullAmountMultipliesByTheTint() async throws {
        let effect = try ExampleEffectsSmokeTests.example("Tint.lens")
        let pixels = try await EffectSmokeRig.render(effect, values: [.color(SIMD4<Float>(1, 0.8, 0.6, 1)), .float(1)])
        ExampleEffectsSmokeTests.expectPixel(pixels, 159, 95, is: [71, 38, 209, 255])
    }

    @Test("Tint at amount 0 leaves every pixel as the input")
    func tintAtZeroAmountLeavesTheInput() async throws {
        let effect = try ExampleEffectsSmokeTests.example("Tint.lens")
        let pixels = try await EffectSmokeRig.render(effect, values: [.color(SIMD4<Float>(1, 0.8, 0.6, 1)), .float(0)])
        ExampleEffectsSmokeTests.expectUnchanged(pixels)
    }

    @Test("Tint in black at amount 1 turns (159, 95) black")
    func blackTintAtFullAmountTurnsThePixelBlack() async throws {
        let effect = try ExampleEffectsSmokeTests.example("Tint.lens")
        let pixels = try await EffectSmokeRig.render(effect, values: [.color(SIMD4<Float>(0, 0, 0, 1)), .float(1)])
        ExampleEffectsSmokeTests.expectPixel(pixels, 159, 95, is: [0, 0, 0, 255])
    }

    @Test("Parameter Tour at its defaults keeps (80, 48) as the input and tints (159, 95) to [101, 45, 209, 255]")
    func parameterTourAtItsDefaults() async throws {
        let effect = try ExampleEffectsSmokeTests.example("ParameterTour.lens")
        let pixels = try await EffectSmokeRig.render(effect, values: ExampleEffectsSmokeTests.defaults(of: effect.parameters))
        ExampleEffectsSmokeTests.expectPixel(pixels, 0, 0, is: [0, 0, 0, 255])
        ExampleEffectsSmokeTests.expectPixel(pixels, 80, 48, is: [192, 160, 112, 255])
        ExampleEffectsSmokeTests.expectPixel(pixels, 159, 95, is: [101, 45, 209, 255])
    }

    @Test("Parameter Tour at full strength with the Squared falloff turns (159, 95) to [95, 43, 209, 255]")
    func parameterTourAtFullStrengthAndSquaredFalloff() async throws {
        let effect = try ExampleEffectsSmokeTests.example("ParameterTour.lens")
        let pixels = try await EffectSmokeRig.render(
            effect,
            values: [
                .float(1), .int(4), .bool(false), .color(SIMD4<Float>(1, 0.8, 0.6, 1)), .vector2(SIMD2<Float>(0.5, 0.5)), .choice(1),
            ])
        ExampleEffectsSmokeTests.expectPixel(pixels, 159, 95, is: [95, 43, 209, 255])
    }

    @Test("Parameter Tour inverted, centred on (0, 0) with reach 8, leaves (80, 48) and (159, 95) as the input")
    func parameterTourInvertedAtTheCorner() async throws {
        let effect = try ExampleEffectsSmokeTests.example("ParameterTour.lens")
        let pixels = try await EffectSmokeRig.render(
            effect,
            values: [
                .float(1), .int(8), .bool(true), .color(SIMD4<Float>(0.2, 0.9, 0.4, 1)), .vector2(SIMD2<Float>(0, 0)), .choice(0),
            ])
        ExampleEffectsSmokeTests.expectPixel(pixels, 80, 48, is: [192, 160, 112, 255])
        ExampleEffectsSmokeTests.expectPixel(pixels, 159, 95, is: [118, 48, 209, 255])
    }

    @Test("Parameter Tour inverted, centred on (1, 1) with the Squared falloff, tints (80, 48) and (159, 95) to two fixed colours")
    func parameterTourInvertedAtTheOppositeCorner() async throws {
        let effect = try ExampleEffectsSmokeTests.example("ParameterTour.lens")
        let pixels = try await EffectSmokeRig.render(
            effect,
            values: [
                .float(0.75), .int(1), .bool(true), .color(SIMD4<Float>(0.2, 0.9, 0.4, 1)), .vector2(SIMD2<Float>(1, 1)), .choice(1),
            ])
        ExampleEffectsSmokeTests.expectPixel(pixels, 80, 48, is: [108, 148, 47, 255])
        ExampleEffectsSmokeTests.expectPixel(pixels, 159, 95, is: [65, 44, 84, 255])
    }

    @Test("Parameter Tour at strength 0 leaves every pixel as the input")
    func parameterTourAtZeroStrengthLeavesTheInput() async throws {
        let effect = try ExampleEffectsSmokeTests.example("ParameterTour.lens")
        let pixels = try await EffectSmokeRig.render(
            effect,
            values: [
                .float(0), .int(4), .bool(false), .color(SIMD4<Float>(1, 0.8, 0.6, 1)), .vector2(SIMD2<Float>(0.5, 0.5)), .choice(0),
            ])
        ExampleEffectsSmokeTests.expectUnchanged(pixels)
    }

    @Test("the scaffold's template at strength 1 inverts the picture: (0, 0) turns white and (159, 95) becomes [137, 207, 46, 255]")
    func scaffoldTemplateInvertsAtFullStrength() async throws {
        let effect = try ExampleEffectsSmokeTests.template(named: "Scaffold")
        let pixels = try await EffectSmokeRig.render(effect, values: [.float(1)])
        ExampleEffectsSmokeTests.expectPixel(pixels, 0, 0, is: [255, 255, 255, 255])
        ExampleEffectsSmokeTests.expectPixel(pixels, 159, 95, is: [137, 207, 46, 255])
        ExampleEffectsSmokeTests.expectPixel(pixels, 80, 48, is: [63, 95, 143, 255])
    }

    @Test("the scaffold's template at strength 0 leaves every pixel as the input")
    func scaffoldTemplateAtZeroStrengthLeavesTheInput() async throws {
        let effect = try ExampleEffectsSmokeTests.template(named: "Scaffold")
        let pixels = try await EffectSmokeRig.render(effect, values: [.float(0)])
        ExampleEffectsSmokeTests.expectUnchanged(pixels)
    }

    @Test("the tutorial's Swap kernel at strength 1 swaps red and blue: (159, 95) becomes [209, 48, 118, 255] and (0, 0) stays black")
    func tutorialSwapKernelSwapsRedAndBlue() async throws {
        let effect = try ExampleEffectsSmokeTests.tutorialKernel()
        let pixels = try await EffectSmokeRig.render(effect, values: [.float(1)])
        ExampleEffectsSmokeTests.expectPixel(pixels, 0, 0, is: [0, 0, 0, 255])
        ExampleEffectsSmokeTests.expectPixel(pixels, 80, 48, is: [112, 160, 192, 255])
        ExampleEffectsSmokeTests.expectPixel(pixels, 159, 95, is: [209, 48, 118, 255])
    }

    @Test("the tutorial's Swap kernel at strength 0 leaves every pixel as the input")
    func tutorialSwapKernelAtZeroStrengthLeavesTheInput() async throws {
        let effect = try ExampleEffectsSmokeTests.tutorialKernel()
        let pixels = try await EffectSmokeRig.render(effect, values: [.float(0)])
        ExampleEffectsSmokeTests.expectUnchanged(pixels)
    }
}

@Suite("Example effects smoke rule", .timeLimit(.minutes(1)))
struct ExampleEffectsSmokeTestsRule {
    @Test("the testing rules name ExampleEffectsSmokeTests among the suites that read Examples/ and docs/authoring/ from disk")
    func testingRulesNameTheSuite() throws {
        let rules = try repositoryText(".claude/rules/testing.md")
        #expect(rules.contains("ExampleEffectsSmokeTests"))
    }
}
