/// The text the scaffold command starts a new `.lens` package from (`EffectScaffoldTemplate`): the
/// `manifest.json` and the `effect.metal`, and the rule that decides which names a new package may
/// take. Pure text: writing the files is the package DataSource's.
///
/// - `isValid(name:)` admits only what reads well as a menu name and is safe as a folder name: ASCII
///   letters, digits, spaces, `-` and `_`, from 1 to `nameLimit` characters, starting with a letter or
///   a digit and not ending in a space. Everything else is refused: path separators, dots, quotes,
///   backslashes, control characters, and any non-ASCII text, combining marks included. The check reads
///   the UTF-8 bytes, so an accented letter cannot pass for an ASCII one.
/// - `manifest(named:)` writes the name into the JSON as it is, since the name has been checked.
/// - `effectSource` declares only the kernel. `Uniforms` and `Parameters` are declared for the author by
///   the shader source assembly, so the template does not declare them.
public enum EffectScaffoldTemplate {
    /// The longest name a new package may take, in characters (all of them ASCII, so also in bytes).
    public static let nameLimit = 64

    public static func isValid(name: String) -> Bool {
        let bytes = Array(name.utf8)
        guard (1...nameLimit).contains(bytes.count), let first = bytes.first, let last = bytes.last else { return false }
        return isLetterOrDigit(first) && last != space && bytes.allSatisfy(isAllowed)
    }

    public static func manifest(named name: String) -> String {
        """
        {
          "formatVersion": 1,
          "name": "\(name)",
          "parameters": [
            { "id": "strength", "label": "Strength", "type": "float", "min": 0, "max": 1, "default": 1, "step": 0.05 }
          ]
        }

        """
    }

    public static let effectSource = """
        // Uniforms and Parameters are declared for you: Parameters has one member per entry
        // of "parameters" in manifest.json, under the same id.
        kernel void effect(texture2d<float, access::read> input [[texture(0)]],
                           texture2d<float, access::write> output [[texture(1)]],
                           constant Uniforms &uniforms [[buffer(0)]],
                           constant Parameters &params [[buffer(1)]],
                           uint2 gid [[thread_position_in_grid]]) {
            if (gid.x >= output.get_width() || gid.y >= output.get_height()) { return; }
            uint2 inside = min(gid, uint2(input.get_width() - 1, input.get_height() - 1));
            float3 color = input.read(inside).rgb;
            output.write(float4(mix(color, 1.0f - color, params.strength), 1.0f), gid);
        }

        """

    private static let space: UInt8 = 0x20
    private static let hyphen: UInt8 = 0x2D
    private static let underscore: UInt8 = 0x5F

    private static func isLetterOrDigit(_ byte: UInt8) -> Bool {
        (0x30...0x39).contains(byte) || (0x41...0x5A).contains(byte) || (0x61...0x7A).contains(byte)
    }

    private static func isAllowed(_ byte: UInt8) -> Bool {
        isLetterOrDigit(byte) || byte == space || byte == hyphen || byte == underscore
    }
}
