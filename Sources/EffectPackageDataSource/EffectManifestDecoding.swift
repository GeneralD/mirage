import Domain
import Foundation

/// How the text of a `manifest.json` becomes an `EffectManifest`, or the reason it cannot
/// (epic #42, D1 / D3). Pure functions: reading the file is `EffectPackageDataSourceImpl`'s.
///
/// - `formatVersion` is checked first, on its own, so a manifest of a format this build does not
///   read is reported as that (`unsupportedFormatVersion`) even when the rest of it has a shape
///   this build would reject. Only version 1 is read. A `formatVersion` that is a number but not an
///   integer (1.5, or a whole number beyond `Int`) is `manifestInvalid` and names the key.
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
            switch try decoder.decode(FormatProbe.self, from: data).formatVersion {
            case .number(let number): return .failure(.manifestInvalid(message: message(forFormatVersion: number)))
            case .integer(let version) where version != supportedFormatVersion: return .failure(.unsupportedFormatVersion(version))
            case .integer: break
            }
            let manifest = try decoder.decode(EffectManifest.self, from: data)
            let name = manifest.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { return .failure(.manifestInvalid(message: "\"name\" is empty")) }
            return .success(
                EffectManifest(formatVersion: supportedFormatVersion, name: name, author: manifest.author, description: manifest.description))
        } catch {
            return .failure(.manifestInvalid(message: message(for: error)))
        }
    }

    /// Only the key that decides whether the rest is read.
    private struct FormatProbe: Decodable {
        let formatVersion: FormatVersion
    }

    /// What `formatVersion` holds: an `Int`, or else any other JSON number. The decoder reports a number
    /// it cannot read as an `Int` (1.5, 99999999999999999999) as a text that is not JSON, with no coding
    /// path, so it cannot be told from one; read again as a `Double` the number is there, and the key is
    /// named by whoever reads the case. A value that is no number at all (text, `null`) fails both
    /// reads, and the second one's error names the key; a missing key never gets this far. A number
    /// beyond even a `Double` (1e400) fails the second read too, with no path, and stays "not valid
    /// JSON". The rows of `EffectManifestDecodingTests` pin each of these.
    private enum FormatVersion: Decodable {
        case integer(Int)
        case number(Double)

        init(from decoder: any Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let integer = try? container.decode(Int.self) {
                self = .integer(integer)
            } else {
                self = .number(try container.decode(Double.self))
            }
        }
    }

    /// A whole number that does not fit an `Int` is out of range; anything else is not an integer.
    private static func message(forFormatVersion number: Double) -> String {
        number.rounded() == number ? "\"formatVersion\" is out of range" : "\"formatVersion\" is not an integer"
    }

    /// `.dataCorrupted` has no key to name, so it is always "not valid JSON": the decoder reports a bad
    /// escape met while a value is read (a lone surrogate in `name`) with an empty coding path, as it
    /// does a truncated text or a number beyond a `Double`, and the manifest has no decoding strategy
    /// that could raise it with a path of its own.
    private static func message(for error: any Error) -> String {
        guard let error = error as? DecodingError else { return "not valid JSON" }
        return switch error {
        case .keyNotFound(let key, let context): "missing required key \(quoted(context.codingPath + [key]))"
        case .typeMismatch(_, let context): "\(subject(of: context)) has the wrong type"
        case .valueNotFound(_, let context): "\(subject(of: context)) has no value"
        case .dataCorrupted: "not valid JSON"
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
