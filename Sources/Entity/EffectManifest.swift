/// `manifest.json` of a `.lens` package (epic #42, D1). `formatVersion` (an integer,
/// 1 today) and `name` are required; `author` and `description` are optional. A key
/// this struct does not know is ignored on decode, so a newer package can carry more
/// than an older build reads; `parameters` is among them until MVP-C interprets it.
/// Reading the file is the package DataSource's: this is only the shape both sides
/// share, so `Codable` round-trips it.
public struct EffectManifest: Sendable, Hashable, Codable {
    public let formatVersion: Int
    /// What the menu shows.
    public let name: String
    public let author: String?
    public let description: String?

    public init(formatVersion: Int, name: String, author: String? = nil, description: String? = nil) {
        self.formatVersion = formatVersion
        self.name = name
        self.author = author
        self.description = description
    }
}
