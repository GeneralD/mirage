/// The one place in `Sources/` that knows the product's name (see
/// `docs/ARCHITECTURE.md` → Rename-safe naming). Everything else is role-named.
///
/// The bundle identifiers and the Mach service name are plain literals, not
/// derived, because `project.yml` (the other place they live) and the
/// provisioning profiles need the same literal strings and
/// `scripts/check-service-names.sh` compares them textually. Renaming the
/// product edits this file, `project.yml` and `README.md`, then re-issues the
/// two provisioning profiles.
public enum ProductIdentity {
    public static let displayName = "Mirage"
    public static let hostBundleID = "com.generald.mirage"
    public static let extensionBundleID = "com.generald.mirage.CameraExtension"
    /// Registered by the extension, looked up by the host. Must match the
    /// `mach-register` / `mach-lookup` entitlements generated from `project.yml`.
    public static let machServiceName = "com.generald.mirage.frames"
    /// `os.Logger` subsystem for both processes.
    public static let logSubsystem = "com.generald.mirage"
}
