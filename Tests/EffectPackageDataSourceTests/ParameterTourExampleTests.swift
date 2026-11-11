import Domain
import EffectPackageDataSource
import Foundation
import Testing

/// Parameter Tour is the example with one parameter of every kind, so it is held to the parameter contract
/// (`docs/hackathon/mvp-cd/specs/parameters.md`) as well as to the format every example meets
/// (`ExamplePackagesTests`).
@Suite("Parameter Tour example", .timeLimit(.minutes(1)))
struct ParameterTourExampleTests {
    @Test(
        "a ready Parameter Tour is named Parameter Tour, its author and description are not empty, and it has no thumbnail"
    )
    func parameterTourIsReady() async throws {
        let package = try await loadedExample("ParameterTour")
        #expect(package.manifest.name == "Parameter Tour")
        #expect(package.manifest.formatVersion == EffectManifestDecoding.supportedFormatVersion)
        #expect(package.manifest.author?.isEmpty == false)
        #expect(package.manifest.description?.isEmpty == false)
        #expect(package.manifest.thumbnail == nil)
        #expect(package.thumbnail == nil)
    }

    @Test(
        "manifest.parameters has the ids strength, reach, inverted, tint, center and mode, of the kinds float, int, bool, color, vector2 and choice, in that order"
    )
    func manifestParametersHaveEveryKindInOrder() async throws {
        let package = try await loadedExample("ParameterTour")
        let parameters = package.manifest.parameters
        #expect(parameters.map(\.id) == ["strength", "reach", "inverted", "tint", "center", "mode"])
        #expect(parameters.map { Self.kindName(of: $0.kind) } == ["float", "int", "bool", "color", "vector2", "choice"])
    }

    @Test("mode is a choice whose options are Linear and Squared, and whose default index is 0")
    func modeIsALinearOrSquaredChoiceDefaultingToLinear() async throws {
        let package = try await loadedExample("ParameterTour")
        let mode = package.manifest.parameters.first { $0.id == "mode" }
        #expect(mode?.kind == EffectParameterKind.choice(options: ["Linear", "Squared"], defaultIndex: 0))
    }

    @Test("center is a vector2 whose min is (0, 0), whose max is (1, 1) and whose default is (0.5, 0.5)")
    func centerIsAVector2OfTheUnitSquare() async throws {
        let package = try await loadedExample("ParameterTour")
        let center = package.manifest.parameters.first { $0.id == "center" }
        #expect(
            center?.kind
                == EffectParameterKind.vector2(
                    min: SIMD2<Float>(0, 0), max: SIMD2<Float>(1, 1), defaultValue: SIMD2<Float>(0.5, 0.5)))
    }

    @Test("source.parameters equals manifest.parameters")
    func sourceParametersEqualManifestParameters() async throws {
        let package = try await loadedExample("ParameterTour")
        #expect(package.source.parameters == package.manifest.parameters)
    }

    @Test(
        "EffectParameterLayout(manifest.parameters) puts strength at 0 as float, reach at 4 as int, inverted at 8 as uint, tint at 16 as float4, center at 32 as float2 and mode at 40 as uint, with stride 48"
    )
    func layoutOfTheParameters() async throws {
        let package = try await loadedExample("ParameterTour")
        let layout = EffectParameterLayout(package.manifest.parameters)
        #expect(layout.stride == 48)
        #expect(layout.fields.map(\.id) == ["strength", "reach", "inverted", "tint", "center", "mode"])
        #expect(layout.fields.map(\.type) == [.float, .int, .uint, .float4, .float2, .uint])
        #expect(layout.fields.map(\.offset) == [0, 4, 8, 16, 32, 40])
    }

    @Test(
        "source defines `kernel void effect(` exactly once, reads params.<id> for each of the six parameters, and contains neither `struct Parameters`, `struct Uniforms` nor `#include`"
    )
    func sourceDefinesTheKernelOnceAndDeclaresNoPrelude() async throws {
        let package = try await loadedExample("ParameterTour")
        let source = package.source.source
        #expect(source.components(separatedBy: "kernel void effect(").count == 2)
        for id in ["strength", "reach", "inverted", "tint", "center", "mode"] {
            #expect(source.contains("params.\(id)"), "the kernel does not read params.\(id)")
        }
        #expect(!source.contains("struct Parameters"))
        #expect(!source.contains("struct Uniforms"))
        #expect(!source.contains("#include"))
    }

    /// The kind of a parameter, by the name `docs/hackathon/mvp-cd/specs/parameters.md` gives its type.
    private static func kindName(of kind: EffectParameterKind) -> String {
        switch kind {
        case .float: return "float"
        case .int: return "int"
        case .bool: return "bool"
        case .color: return "color"
        case .vector2: return "vector2"
        case .choice: return "choice"
        }
    }
}
