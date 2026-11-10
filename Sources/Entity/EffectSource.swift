/// One effect as the runtime sees it: the kernel source to compile and how.
/// Where the source came from (the bundled effect, a `.lens` package) is the
/// catalog's business (`BundledEffects`, `EffectPackages`); the runtime only hashes it for its cache.
public struct EffectSource: Sendable, Hashable {
    /// A display name for logs and the menu; not part of the runtime's cache key,
    /// so two names over one source and options share one compiled library.
    public let name: String
    /// The author's MSL, without the prelude (`ShaderCompilationDataSource`
    /// prepends it).
    public let source: String
    public let options: ShaderCompileOptions
    /// The knobs the effect declares, in manifest order; `[]` for an effect without any, which is
    /// also the default, so existing call sites compile unchanged. Only their layout is part of what
    /// compiles (`EffectFingerprint`); the labels and defaults are the panel's.
    public let parameters: [EffectParameterSpec]

    public init(name: String, source: String, options: ShaderCompileOptions = ShaderCompileOptions(), parameters: [EffectParameterSpec] = []) {
        self.name = name
        self.source = source
        self.options = options
        self.parameters = parameters
    }
}
