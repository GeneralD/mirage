import Domain

/// The effects compiled into the app as string constants (epic #14, D1). MVP-A
/// ships one, `ChromaticGrainEffect`, and the runtime applies it until another
/// effect is prepared. `.lens` packages come from their own DataSource
/// (`EffectPackageDataSource`) behind the same `EffectSource`.
public struct BundledEffectDataSourceImpl: BundledEffects, Sendable {
    public init() {}

    public var defaultEffect: EffectSource { ChromaticGrainEffect.effect }
}
