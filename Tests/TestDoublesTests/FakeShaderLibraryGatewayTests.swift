import Domain
import Foundation
import TestDoubles
import TestSupport
import Testing

@Suite("FakeShaderLibraryGateway", .timeLimit(.minutes(1)))
struct FakeShaderLibraryGatewayTests {
    private let gateway = FakeShaderLibraryGateway()
    private let context = FakeGPUContextHandle()

    @Test("every source compiles to its own handle, and the call is recorded off the main thread")
    func compilesOffMain() throws {
        let options = ShaderCompileOptions(entryPoint: "main0", precise: false)
        let first = try gateway.compile(source: "a", options: options, on: context).get()
        let second = try gateway.compile(source: "a", options: options, on: context).get()

        let handle = try #require(first as? FakeLibraryHandle)
        #expect(handle.source == "a")
        #expect(handle.options == options)
        #expect(ObjectIdentifier(first) != ObjectIdentifier(second), "a fresh handle per compile; caching is the repository's")
        #expect(gateway.calls.values.map(\.onMainThread) == [false, false])
    }

    @Test("scripted diagnostics come back for that source only, until unscripted")
    func scriptedDiagnostics() throws {
        let diagnostics = ShaderDiagnostics(message: "program_source:3: error", code: 3)
        gateway.failCompile(of: "bad", with: diagnostics)

        #expect(gateway.compile(source: "bad", options: ShaderCompileOptions(), on: context).failure == diagnostics)
        _ = try gateway.compile(source: "good", options: ShaderCompileOptions(), on: context).get()

        gateway.failCompile(of: "bad", with: nil)
        _ = try gateway.compile(source: "bad", options: ShaderCompileOptions(), on: context).get()
    }

    @Test("a compile on the main thread is a recorded issue")
    func mainThreadIsAnIssue() async {
        await withKnownIssue {
            await MainActor.run { _ = gateway.compile(source: "a", options: ShaderCompileOptions(), on: context) }
        }
        #expect(gateway.calls.values.map(\.onMainThread) == [true])
    }

    @Test("a foreign context is GPUError.foreignHandle wrapped as the live gateway wraps it")
    func foreignContext() {
        let result = gateway.compile(source: "a", options: ShaderCompileOptions(), on: ForeignContextHandle())
        let expected = GPUError.foreignHandle as NSError
        #expect(result.failure == ShaderDiagnostics(message: expected.localizedDescription, code: expected.code))
    }
}
