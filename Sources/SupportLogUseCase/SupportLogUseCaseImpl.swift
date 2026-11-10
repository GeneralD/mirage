import Dependencies
import Domain
import Foundation

/// Builds the support report from the repository's snapshot and saves it. The report text is the pure
/// `supportReportText`; this type only moves the snapshot in and the outcome out, and logs both ends.
public struct SupportLogUseCaseImpl: Sendable {
    @Dependency(\.supportLogRepository) private var repository
    @Dependency(\.errorLog) private var errorLog
    @Dependency(\.developerLog) private var developerLog

    public init() {}
}

extension SupportLogUseCaseImpl: SupportLogUseCase {
    public func export(_ context: SupportReportContext) async -> SupportLogExportOutcome {
        let snapshot = repository.snapshot()
        let text = supportReportText(snapshot, context: context, appName: ProductIdentity.displayName)
        do {
            let path = try repository.save(text)
            developerLog.record(.app, "support log saved: \(snapshot.entries.count) lines")
            return .saved(path: path, lineCount: snapshot.entries.count, logError: snapshot.logError)
        } catch {
            errorLog.record(.app, "support log could not be saved: \(error)")
            return .failed(description: error.localizedDescription)
        }
    }
}
