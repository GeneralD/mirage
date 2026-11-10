/// `manifest.json` of a `.lens` package (epic #42, D1). `formatVersion` (an integer,
/// 1 today) and `name` are required; `author`, `description`, `thumbnail` and `parameters` are
/// optional, and a manifest without `parameters` has an empty list. A key this struct does not
/// know is ignored on decode, so a newer package can carry more than an older build reads.
/// Reading the file is the package DataSource's: this is only the shape both sides
/// share, so `Codable` round-trips it.
public struct EffectManifest: Sendable, Hashable, Codable {
    public let formatVersion: Int
    /// What the menu shows.
    public let name: String
    public let author: String?
    /// What the effect picker's hover says after the author (#12), as written.
    public let description: String?
    /// The picture for the effect picker (#12), as written: a path relative to the package
    /// directory, to a PNG or a JPEG. Whether it can be used is decided when the package is read,
    /// and one that cannot costs the package only its picture (`EffectPackage.thumbnail`).
    public let thumbnail: String?
    /// The knobs the effect declares, in the order the author wrote them. Decoding here gives
    /// them the shape their JSON has; whether they are allowed (ranges, ids, how many) is decided
    /// when the package is read, and a package that breaks a rule is broken as a whole.
    public let parameters: [EffectParameterSpec]

    public init(
        formatVersion: Int, name: String, author: String? = nil, description: String? = nil, thumbnail: String? = nil,
        parameters: [EffectParameterSpec] = []
    ) {
        self.formatVersion = formatVersion
        self.name = name
        self.author = author
        self.description = description
        self.thumbnail = thumbnail
        self.parameters = parameters
    }

    private enum CodingKeys: String, CodingKey {
        case formatVersion, name, author, description, thumbnail, parameters
    }

    /// `parameters` that is absent or `null` is the empty list, as a `null` thumbnail is no thumbnail.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            formatVersion: try container.decode(Int.self, forKey: .formatVersion),
            name: try container.decode(String.self, forKey: .name),
            author: try container.decodeIfPresent(String.self, forKey: .author),
            description: try container.decodeIfPresent(String.self, forKey: .description),
            thumbnail: try container.decodeIfPresent(String.self, forKey: .thumbnail),
            parameters: try container.decodeIfPresent([EffectParameterSpec].self, forKey: .parameters) ?? [])
    }

    /// An empty `parameters` is left out, so the manifest of an effect without knobs is written as it
    /// was before they existed.
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(formatVersion, forKey: .formatVersion)
        try container.encode(name, forKey: .name)
        try container.encodeIfPresent(author, forKey: .author)
        try container.encodeIfPresent(description, forKey: .description)
        try container.encodeIfPresent(thumbnail, forKey: .thumbnail)
        if !parameters.isEmpty { try container.encode(parameters, forKey: .parameters) }
    }
}
