import Testing

@testable import PreviewDataSource

/// The kernel texts and their options, checked as strings: the GPU pixels are
/// pinned in `PreviewSmokeTests`, and these hold without a device.
@Suite("PreviewKernel")
struct PreviewKernelTests {
    /// The four lines that decide the aspect-fit, without their indentation.
    private static let fitLines = [
        "float2 target = float2(drawable.get_width(), drawable.get_height());",
        "float2 source = float2(frame.get_width(), frame.get_height());",
        "float2 fitted = source * min(target.x / source.x, target.y / source.y);",
        "float2 uv = (float2(gid) + 0.5 - (target - fitted) * 0.5) / fitted;",
    ]

    /// The lines of `text`, each without its leading spaces.
    private static func trimmedLines(_ text: String) -> [String] {
        text.split(separator: "\n", omittingEmptySubsequences: false).map { line in String(line.drop(while: { $0 == " " })) }
    }

    /// Whether `block` appears as consecutive lines of `lines`.
    private static func contains(_ block: [String], in lines: [String]) -> Bool {
        lines.indices.contains { lines[$0...].starts(with: block) }
    }

    @Test("the split is its own source: previewSplit with the original at texture 2, which the blit's source does not carry")
    func splitSourceIsItsOwn() {
        #expect(PreviewKernel.splitSource.contains("kernel void previewSplit"))
        #expect(PreviewKernel.splitSource.contains("[[texture(2)]]"))
        #expect(!PreviewKernel.source.contains("kernel void previewSplit"))
        #expect(!PreviewKernel.source.contains("[[texture(2)]]"))
    }

    @Test("the split compiles under the previewSplit entry point with fast math off")
    func splitOptionsNameTheSplit() {
        #expect(PreviewKernel.splitOptions.entryPoint == "previewSplit")
        #expect(PreviewKernel.splitOptions.precise == false)
    }

    @Test("the blit keeps its previewBlit entry point and its options as they were")
    func blitOptionsAreUnchanged() {
        #expect(PreviewKernel.options == ShaderCompileOptions(entryPoint: "previewBlit", precise: false))
    }

    @Test("the blit and the split carry the same aspect-fit lines, so both kernels fit the frame alike")
    func bothKernelsCarryTheSameFit() {
        #expect(Self.contains(Self.fitLines, in: Self.trimmedLines(PreviewKernel.source)))
        #expect(Self.contains(Self.fitLines, in: Self.trimmedLines(PreviewKernel.splitSource)))
    }
}
