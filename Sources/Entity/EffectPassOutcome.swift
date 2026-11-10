/// How one effect pass ended, for the health judgement: its timing, or why it failed, stamped with
/// the fingerprint of the effect that was admitted. The stamp is taken at admission, never when
/// the outcome is read, so a late failure of effect A is never charged to effect B that the user
/// picked in the meantime.
public struct EffectPassOutcome: Sendable, Hashable {
    public let fingerprint: EffectFingerprint
    public let result: Result<GPUTiming, EffectFailure>

    public init(fingerprint: EffectFingerprint, result: Result<GPUTiming, EffectFailure>) {
        self.fingerprint = fingerprint
        self.result = result
    }
}
