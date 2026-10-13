import Dependencies
import Domain
import VirtualCameraRepository

// Substitutions for the development harness (`swift run dev-harness`), which runs the
// host's live graph in a process that has no Camera Extension. They sit here, not in the
// harness, because the DI targets are the only importers of implementation modules
// (scripts/check-imports.sh); a substitution is applied with `withDependencies`, and no
// shipped entry point calls one.

extension DependencyValues {
    /// The pipeline's frames go to `DiscardingVirtualCameraSink` (reported as sent, kept
    /// by no one) instead of the Mach transport to the extension (epic #14, D13).
    public mutating func useDiscardingVirtualCameraSink() {
        virtualCameraSink = DiscardingVirtualCameraSink()
    }
}
