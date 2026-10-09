import Domain
import GPURenderDataSource
import TestSupport
import Testing

@Suite("GPUCompletionMapping")
struct GPUCompletionMappingTests {
    /// Every `MTLCommandBufferError.Code` the SDK declares (0–4, 7–12), the two
    /// numbers it skips (5, 6) and codes outside its range, each with the failure
    /// it must become. `GPUSmokeTests` pins the SDK's numbers to these.
    static let commandBufferCodes: [(code: Int, expected: EffectFailure)] = [
        (0, .unknown(code: 0)),  // none
        (1, .unknown(code: 1)),  // internal
        (2, .timeout),
        (3, .pageFault),
        (4, .accessRevoked),
        (5, .unknown(code: 5)),
        (6, .unknown(code: 6)),
        (7, .unknown(code: 7)),  // notPermitted
        (8, .outOfMemory),
        (9, .invalidResource),
        (10, .unknown(code: 10)),  // memoryless
        (11, .unknown(code: 11)),  // deviceRemoved
        (12, .unknown(code: 12)),  // stackOverflow
        (13, .unknown(code: 13)),
        (-1, .unknown(code: -1)),
        (Int.max, .unknown(code: Int.max)),
    ]

    @Test("each command-buffer code maps to its EffectFailure", arguments: commandBufferCodes)
    func commandBufferCode(code: Int, expected: EffectFailure) {
        let error = RawGPUError(domain: GPUCompletionMapping.commandBufferErrorDomain, code: code)
        #expect(GPUCompletionMapping.failure(for: error) == expected)
    }

    @Test("a code from any other domain is unknown, even one that names a cause in the command-buffer domain", arguments: [2, 3, 4, 8, 9])
    func otherDomain(code: Int) {
        let error = RawGPUError(domain: "NSPOSIXErrorDomain", code: code)
        #expect(GPUCompletionMapping.failure(for: error) == .unknown(code: code))
    }

    @Test("a completion without an error is success carrying the GPU timestamps verbatim")
    func success() {
        let completion = GPUCompletion(gpuStart: 3.25, gpuEnd: 3.5, error: nil)
        #expect(GPUCompletionMapping.result(of: completion) == .success(GPUTiming(gpuStart: 3.25, gpuEnd: 3.5)))
    }

    @Test("a completion with an error is that error's failure, whatever the timestamps")
    func failure() {
        let completion = GPUCompletion(
            gpuStart: 3.25, gpuEnd: 3.5, error: RawGPUError(domain: GPUCompletionMapping.commandBufferErrorDomain, code: 9))
        #expect(GPUCompletionMapping.result(of: completion) == .failure(.invalidResource))
    }
}
