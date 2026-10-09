extension Result {
    /// The error of a `.failure`, `nil` for a `.success` — so a result whose
    /// success value is not `Equatable` (`Result<Void, EffectFailure>`) can
    /// still be asserted on: `#expect(result.failure == .timeout)`,
    /// `#expect(result.failure == nil)`.
    public var failure: Failure? {
        switch self {
        case .success: nil
        case .failure(let error): error
        }
    }
}
