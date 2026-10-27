import Dependencies

/// `BundledEffectDataSource`: the effects that ship inside the app. Their MSL is
/// a Swift string constant rather than a resource (epic #14, D1), so no
/// `Bundle.main`, no bundle port and no resource bundle in the Xcode shell. They
/// come out as the same `EffectSource` a `.lens` package does
/// (`EffectPackageDataSource`), so `EffectRuntimeRepository` never knows
/// where an effect came from.
public protocol BundledEffects: Sendable {
    /// The effect `EffectRuntimeRepository` runs while no other one has been prepared.
    var defaultEffect: EffectSource { get }
}

public enum BundledEffectsKey: TestDependencyKey {
    public static let testValue: any BundledEffects = UnimplementedBundledEffects()
}

extension DependencyValues {
    public var bundledEffects: any BundledEffects {
        get { self[BundledEffectsKey.self] }
        set { self[BundledEffectsKey.self] = newValue }
    }
}

private struct UnimplementedBundledEffects: BundledEffects {
    var defaultEffect: EffectSource {
        reportIssue("BundledEffects.defaultEffect not implemented")
        return EffectSource(name: "unimplemented", source: "")
    }
}
