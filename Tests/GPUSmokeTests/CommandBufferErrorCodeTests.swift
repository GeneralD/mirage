import Domain
import GPURenderDataSource
import Metal
import Testing

/// `GPUCompletionMapping` interprets `RawGPUError` by domain string and code
/// number, because nothing above the Gateway may import Metal. This pins both to
/// the SDK, so an SDK that renumbers `MTLCommandBufferError.Code` or renames its
/// domain fails here instead of silently turning a page fault into `unknown`.
/// No command buffer runs: the values are SDK constants, read from the same
/// process that links Metal, wrapped exactly as the live gateway wraps them.
@Suite("Command-buffer error codes", .serialized, .enabled(if: MetalDeviceProbe.isAvailable), .timeLimit(.minutes(1)))
struct CommandBufferErrorCodeTests {
    @Test("the mapped domain is the SDK's command-buffer error domain")
    func domain() {
        #expect(GPUCompletionMapping.commandBufferErrorDomain == MTLCommandBufferErrorDomain)
        #expect((MTLCommandBufferError(.timeout) as NSError).domain == GPUCompletionMapping.commandBufferErrorDomain)
    }

    @Test("each code the mapping names is the SDK's number for that cause")
    func codes() {
        let causes: [(MTLCommandBufferError.Code, EffectFailure)] = [
            (.timeout, .timeout), (.pageFault, .pageFault), (.accessRevoked, .accessRevoked),
            (.outOfMemory, .outOfMemory), (.invalidResource, .invalidResource),
        ]
        for (code, expected) in causes {
            #expect(GPUCompletionMapping.failure(for: raw(code)) == expected, "\(code)")
        }
    }

    @Test("the SDK's other codes stay unknown")
    func otherCodes() {
        let others: [MTLCommandBufferError.Code] = [.none, .internal, .notPermitted, .memoryless, .deviceRemoved, .stackOverflow]
        for code in others {
            #expect(GPUCompletionMapping.failure(for: raw(code)) == .unknown(code: Int(code.rawValue)), "\(code)")
        }
    }

    /// The SDK's error for `code`, wrapped the way `MetalGateway` wraps a command-buffer error (`NSError` domain and code).
    private func raw(_ code: MTLCommandBufferError.Code) -> RawGPUError {
        let error = MTLCommandBufferError(code) as NSError
        return RawGPUError(domain: error.domain, code: error.code)
    }
}
