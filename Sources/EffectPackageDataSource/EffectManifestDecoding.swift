import Domain
import Foundation

/// How the text of a `manifest.json` becomes an `EffectManifest`, or the reason it cannot
/// (epic #42, D1 / D3). Pure functions: reading the file is `EffectPackageDataSourceImpl`'s.
///
/// - `formatVersion` is checked first, on its own, so a manifest of a format this build does not
///   read is reported as that (`unsupportedFormatVersion`) even when the rest of it has a shape
///   this build would reject. Only version 1 is read.
/// - `name` is required and is trimmed; a name that is empty after the trim is invalid. The
///   trimmed name is what the menu shows.
/// - `author` and `description` are optional. A key this build does not know is ignored, so a
///   newer package can carry more than an older build reads; `parameters` is one of them until
///   MVP-C interprets it, whatever shape its value has.
/// - Everything else that is wrong with the text (not JSON, not an object, a required key
///   missing, a value of the wrong type) is `manifestInvalid`, with a message that names the key.
///   The messages are built from the decoder's coding path and not from its own wording, so they
///   do not change with the locale or the OS.
public enum EffectManifestDecoding {
    /// The only `formatVersion` this build reads.
    public static let supportedFormatVersion = 1

    public static func decode(_ text: String) -> Result<EffectManifest, EffectPackageProblem> {
        let data = Data(text.utf8)
        let decoder = JSONDecoder()
        do {
            let version = try decoder.decode(FormatProbe.self, from: data).formatVersion
            guard version == supportedFormatVersion else { return .failure(.unsupportedFormatVersion(version)) }
            let manifest = try decoder.decode(EffectManifest.self, from: data)
            let name = manifest.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { return .failure(.manifestInvalid(message: "\"name\" is empty")) }
            return .success(EffectManifest(formatVersion: version, name: name, author: manifest.author, description: manifest.description))
        } catch {
            return .failure(.manifestInvalid(message: message(for: error)))
        }
    }

    /// Only the key that decides whether the rest is read.
    private struct FormatProbe: Decodable {
        let formatVersion: Int
    }

    private static func message(for error: any Error) -> String {
        guard let error = error as? DecodingError else { return "not valid JSON" }
        return switch error {
        case .keyNotFound(let key, let context): "missing required key \(quoted(context.codingPath + [key]))"
        case .typeMismatch(_, let context): "\(subject(of: context)) has the wrong type"
        case .valueNotFound(_, let context): "\(subject(of: context)) has no value"
        case .dataCorrupted(let context): context.codingPath.isEmpty ? "not valid JSON" : "\(subject(of: context)) is not valid"
        @unknown default: "not valid JSON"
        }
    }

    /// The key a problem is about, or the manifest as a whole when the path is empty.
    private static func subject(of context: DecodingError.Context) -> String {
        context.codingPath.isEmpty ? "the manifest" : quoted(context.codingPath)
    }

    private static func quoted(_ path: [any CodingKey]) -> String {
        "\"\(path.map(\.stringValue).joined(separator: "."))\""
    }
}
