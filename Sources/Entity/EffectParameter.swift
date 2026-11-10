/// What one knob of an effect is and the values it may take. A closed set, so the panel, the
/// packer and the layout each switch over it exhaustively: a seventh kind is a compile error in
/// every one of them rather than a control that silently never appears.
///
/// Only kinds with a fixed-width field exist (no 3-vector: `EffectParameterFieldType`). `bool` and
/// `choice` reach the shader as `uint`, `color` as `float4` (`EffectParameterKind.fieldType`).
///
/// `Codable` is deliberately absent: the manifest's JSON is shaped for authors to write, not like
/// this enum's synthesized form, and its decoding (with the validation that goes with it) comes
/// with the manifest reader.
public enum EffectParameterKind: Sendable, Hashable {
    /// `step`, when present, is the grid the value snaps to.
    case float(min: Float, max: Float, step: Float?, defaultValue: Float)
    case int(min: Int32, max: Int32, defaultValue: Int32)
    case bool(defaultValue: Bool)
    /// sRGB components in `[0, 1]`, alpha last.
    case color(defaultValue: SIMD4<Float>)
    case vector2(min: SIMD2<Float>, max: SIMD2<Float>, defaultValue: SIMD2<Float>)
    /// `defaultIndex` indexes `options`; the shader receives that index.
    case choice(options: [String], defaultIndex: Int)
}

/// One declared parameter. `id` is the field name the shader reads (`params.<id>`) and the key a
/// stored value is kept under; `label` is only what the panel shows, so it never reaches the
/// compiled shader (`EffectFingerprint`).
public struct EffectParameterSpec: Sendable, Hashable {
    public let id: String
    public let label: String
    public let kind: EffectParameterKind

    public init(id: String, label: String, kind: EffectParameterKind) {
        self.id = id
        self.label = label
        self.kind = kind
    }
}

/// A current setting, one case per `EffectParameterKind` case. It is stored as JSON, one object
/// per effect, so the synthesized form is the persisted one (pinned by a test) and a case is
/// never renamed, as with `EffectOrigin`.
public enum EffectParameterValue: Sendable, Hashable, Codable {
    case float(Float)
    case int(Int32)
    case bool(Bool)
    case color(SIMD4<Float>)
    case vector2(SIMD2<Float>)
    /// The index into the kind's `options`.
    case choice(Int)
}
