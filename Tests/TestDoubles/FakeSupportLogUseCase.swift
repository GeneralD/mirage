import Domain
import TestSupport

/// `SupportLogUseCase` the test drives: `export(_:)` records the context it was given and answers `outcome`.
/// `contexts` holds every context in call order, so a subject that asked for an export is asserted to have
/// asked with the right one, whatever the outcome.
public final class FakeSupportLogUseCase: SupportLogUseCase, Sendable {
    private let outcome: SupportLogExportOutcome
    /// The contexts `export(_:)` was called with, in call order.
    public let contexts = Collector<SupportReportContext>()

    public init(outcome: SupportLogExportOutcome = .saved(path: "/fake/support-log.txt", lineCount: 0, logError: nil)) {
        self.outcome = outcome
    }

    public func export(_ context: SupportReportContext) async -> SupportLogExportOutcome {
        contexts.append(context)
        return outcome
    }
}
