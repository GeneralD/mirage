/// One effect as the runtime sees it: the kernel source to compile and how.
/// Where the source came from (the bundled effect, a `.lens` package) is the
/// package layer's business (MVP-B); the runtime only hashes it for its cache.
public struct EffectSource: Sendable, Hashable {
    /// A display name for logs and the menu; never part of the cache key's
    /// meaning beyond equality.
    public let name: String
    /// The author's MSL, without the prelude (`ShaderCompilationDataSource`
    /// prepends it).
    public let source: String
    public let options: ShaderCompileOptions

    public init(name: String, source: String, options: ShaderCompileOptions = ShaderCompileOptions()) {
        self.name = name
        self.source = source
        self.options = options
    }
}
