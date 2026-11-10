import Dependencies

/// Writes the support report: the environment and the system log read through the repository, the
/// report text made from them and the context, and the file it is saved as. A failure to save is a
/// value (`.failed`), never a throw, so the caller can show the reason.
public protocol SupportLogUseCase: Sendable {
    /// Builds the report from `context` and saves it, reporting how that ended.
    func export(_ context: SupportReportContext) async -> SupportLogExportOutcome
}

public enum SupportLogUseCaseKey: TestDependencyKey {
    public static let testValue: any SupportLogUseCase = UnimplementedSupportLogUseCase()
}

extension DependencyValues {
    public var supportLogUseCase: any SupportLogUseCase {
        get { self[SupportLogUseCaseKey.self] }
        set { self[SupportLogUseCaseKey.self] = newValue }
    }
}

private struct UnimplementedSupportLogUseCase: SupportLogUseCase {
    func export(_ context: SupportReportContext) async -> SupportLogExportOutcome {
        reportIssue("SupportLogUseCase.export not implemented")
        return .failed(description: "unimplemented")
    }
}
