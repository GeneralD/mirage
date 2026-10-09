/// Value-to-Metal mappings the draw half needs; no decisions, one call each.
/// OS API: `MTLSize`, `NSError` fields of a command-buffer error.
/// Mirrors `MetalGateway`'s, which are internal to that module.
import Domain
import Foundation
import MetalKit

extension GridSize {
    func metalSize() -> MTLSize {
        MTLSize(width: width, height: height, depth: 1)
    }
}

extension RawGPUError {
    /// Domain and code only; interpreting them is `PreviewDataSource`'s.
    init(wrapping error: any Error) {
        self.init(domain: (error as NSError).domain, code: (error as NSError).code)
    }
}
