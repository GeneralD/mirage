import Domain

/// The effects compiled into the app as string constants (epic #14, D1). Four ship
/// (`effects`), in the order the menu shows them. The first one, `ChromaticGrainEffect`,
/// is `defaultEffect`, which the runtime applies until another effect is prepared.
/// `.lens` packages come from their own DataSource (`EffectPackageDataSource`) behind
/// the same `EffectSource`.
public struct BundledEffectDataSourceImpl: BundledEffects, Sendable {
    public init() {}

    public var defaultEffect: EffectSource { ChromaticGrainEffect.effect }

    public var effects: [EffectSource] {
        [ChromaticGrainEffect.effect, VignetteEffect.effect, PixelateEffect.effect, DuotoneEffect.effect]
    }
}
