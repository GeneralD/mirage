import Dependencies
import Domain
import Foundation
import TestSupport

/// A compiled effect as `FakeShaderLibraryGateway` mints it: remembers what it
/// was compiled from so a test can tell two kernels apart. Identity is the object.
public final class FakeLibraryHandle: LibraryHandle, Sendable {
    public let source: String
    public let options: ShaderCompileOptions

    public init(source: String, options: ShaderCompileOptions = ShaderCompileOptions()) {
        self.source = source
        self.options = options
    }

    public var backing: AnyObject { self }
}

/// `ShaderLibraryGateway` as the test scripts it: every source compiles to a
/// fresh `FakeLibraryHandle` unless `failCompile(of:with:)` scripted the
/// compiler's diagnostics for that exact source. Each call is recorded with the
/// thread it ran on, and a call from the main thread is reported as a test
/// issue: the DataSource's "never compile on main" contract, enforced at the
/// one place that would break it.
public final class FakeShaderLibraryGateway: ShaderLibraryGateway, Sendable {
    public struct Call: Sendable {
        public let source: String
        public let options: ShaderCompileOptions
        public let onMainThread: Bool
    }

    private let scripted = Locked<[String: ShaderDiagnostics]>([:])
    public let calls = Collector<Call>()

    public init() {}

    /// Scripts the compiler's answer for `source`; `nil` lets it compile again.
    public func failCompile(of source: String, with diagnostics: ShaderDiagnostics?) {
        scripted.withLock { $0[source] = diagnostics }
    }

    public func compile(
        source: String, options: ShaderCompileOptions, on context: any GPUContextHandle
    ) -> Result<any LibraryHandle, ShaderDiagnostics> {
        let onMainThread = Thread.isMainThread
        calls.append(Call(source: source, options: options, onMainThread: onMainThread))
        if onMainThread { reportIssue("ShaderLibraryGateway.compile called on the main thread") }
        guard context is FakeGPUContextHandle else { return .failure(ShaderDiagnostics(message: "foreign context", code: -1)) }
        if let diagnostics = scripted.current[source] { return .failure(diagnostics) }
        return .success(FakeLibraryHandle(source: source, options: options))
    }
}
