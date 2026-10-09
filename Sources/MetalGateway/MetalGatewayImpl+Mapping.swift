/// Value-to-Metal mappings the dispatch half needs; no decisions, one call each.
/// OS API: `MTLSize`, `NSError` fields of a command-buffer error.
import Domain
import Foundation
import Metal

extension GridSize {
    func metalSize() -> MTLSize {
        MTLSize(width: width, height: height, depth: 1)
    }
}

extension RawGPUError {
    /// Domain and code only; interpreting them is `GPURenderDataSource`'s.
    init(wrapping error: any Error) {
        self.init(domain: (error as NSError).domain, code: (error as NSError).code)
    }
}
