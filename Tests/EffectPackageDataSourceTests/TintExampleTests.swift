import Domain
import EffectPackageDataSource
import Foundation
import Testing

/// Tint is the example that carries knobs, so it is held to the parameter contract
/// (`docs/hackathon/mvp-cd/specs/parameters.md`) as well as to the format every example meets
/// (`ExamplePackagesTests`).
@Suite("Tint example", .timeLimit(.minutes(1)))
struct TintExampleTests {
    @Test(
        "Tint is ready, its manifest name is Tint, its formatVersion is EffectManifestDecoding.supportedFormatVersion, its author and description are not empty, and it has no thumbnail"
    )
    func tintIsReady() async throws {
        let package = try await loadedExample("Tint")
        #expect(package.manifest.name == "Tint")
        #expect(package.manifest.formatVersion == EffectManifestDecoding.supportedFormatVersion)
        #expect(package.manifest.author?.isEmpty == false)
        #expect(package.manifest.description?.isEmpty == false)
        #expect(package.manifest.thumbnail == nil)
        #expect(package.thumbnail == nil)
    }

    @Test(
        "manifest.parameters is exactly [EffectParameterSpec(id: \"tint\", label: \"Tint\", kind: .color(defaultValue: SIMD4<Float>(1, 0.8, 0.6, 1))), EffectParameterSpec(id: \"amount\", label: \"Amount\", kind: .float(min: 0, max: 1, step: 0.05, defaultValue: 0.5))]"
    )
    func manifestParametersAreTintAndAmount() async throws {
        let package = try await loadedExample("Tint")
        #expect(
            package.manifest.parameters == [
                EffectParameterSpec(id: "tint", label: "Tint", kind: .color(defaultValue: SIMD4<Float>(1, 0.8, 0.6, 1))),
                EffectParameterSpec(id: "amount", label: "Amount", kind: .float(min: 0, max: 1, step: 0.05, defaultValue: 0.5)),
            ])
    }

    @Test("source.parameters equals manifest.parameters")
    func sourceParametersEqualManifestParameters() async throws {
        let package = try await loadedExample("Tint")
        #expect(package.source.parameters == package.manifest.parameters)
    }

    @Test("EffectParameterLayout(manifest.parameters) has stride 32, with field tint at offset 0 as float4 and amount at offset 16 as float")
    func layoutOfTheParameters() async throws {
        let package = try await loadedExample("Tint")
        let layout = EffectParameterLayout(package.manifest.parameters)
        #expect(layout.stride == 32)
        #expect(layout.fields.map(\.id) == ["tint", "amount"])
        #expect(layout.fields.map(\.type) == [.float4, .float])
        #expect(layout.fields.map(\.offset) == [0, 16])
    }

    @Test(
        "source defines `kernel void effect(` exactly once, reads params.tint and params.amount, and contains neither `struct Parameters`, `struct Uniforms` nor `#include`"
    )
    func sourceDefinesTheKernelOnceAndDeclaresNoPrelude() async throws {
        let package = try await loadedExample("Tint")
        let source = package.source.source
        #expect(source.components(separatedBy: "kernel void effect(").count == 2)
        #expect(source.contains("params.tint"))
        #expect(source.contains("params.amount"))
        #expect(!source.contains("struct Parameters"))
        #expect(!source.contains("struct Uniforms"))
        #expect(!source.contains("#include"))
    }
}
