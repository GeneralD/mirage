import Domain
import Foundation
import Metal
import MetalGateway
import ShaderCompilationDataSource
import TestSupport
import Testing

/// `LibraryErrorMapping` interprets the compiler's raw code as a number, because
/// nothing above the Gateway may import Metal. This pins that number to the SDK, so an
/// SDK that renumbers `MTLLibraryError.Code` fails here instead of silently turning a
/// transient compiler fault into a final `.compileFailed` (or a broken source into a
/// retry on every frame). The first two tests run no compile: the values are SDK
/// constants, read from the process that links Metal. The third runs the real
/// compiler on a broken source, the one error the live suite can provoke safely.
@Suite("Library error codes", .serialized, .enabled(if: MetalDeviceProbe.isAvailable), .timeLimit(.minutes(1)))
struct LibraryErrorCodeTests {
    @Test("the code the mapping calls internal is the SDK's MTLLibraryError.internal")
    func internalCode() {
        let error = MTLLibraryError(.internal) as NSError
        #expect(LibraryErrorMapping.internalErrorCode == Int(MTLLibraryError.Code.internal.rawValue))
        #expect(error.code == LibraryErrorMapping.internalErrorCode)
        #expect(error.domain == MTLLibraryErrorDomain)
        #expect(LibraryErrorMapping.cause(forCode: error.code) == .environment)
    }

    @Test("every other code the SDK declares is the source's")
    func otherCodes() {
        let others: [MTLLibraryError.Code] = [.unsupported, .compileFailure, .compileWarning, .functionNotFound, .fileNotFound]
        for code in others {
            let raw = (MTLLibraryError(code) as NSError).code
            #expect(raw != LibraryErrorMapping.internalErrorCode, "\(code)")
            #expect(LibraryErrorMapping.cause(forCode: raw) == .source, "\(code)")
        }
    }

    @Test("the real compiler rejecting a source reports compileFailure, and a missing entry point reports 0: both the source's")
    func liveCompilerFailures() throws {
        let gateway = MetalGatewayImpl()
        let context = try gateway.makeContext()

        let syntax = gateway.compile(source: ShaderSourceAssembly.assemble("kernel void effect( {"), options: ShaderCompileOptions(), on: context)
        let rejected = try #require(syntax.failure)
        #expect(rejected.code == Int(MTLLibraryError.Code.compileFailure.rawValue))
        #expect(LibraryErrorMapping.classified(rejected).cause == .source)

        let noEntry = gateway.compile(
            source: ShaderSourceAssembly.assemble("kernel void other() {}"), options: ShaderCompileOptions(), on: context)
        let missing = try #require(noEntry.failure)
        #expect(missing.code == 0)
        #expect(LibraryErrorMapping.classified(missing).cause == .source)
    }
}
