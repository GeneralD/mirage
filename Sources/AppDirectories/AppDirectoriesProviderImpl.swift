import Domain
import Foundation

/// Live `AppDirectoriesProvider`: the effects and diagnostics folders, each a last component inside a folder
/// named by the host bundle id inside the user's Application Support directory (epic #42, D2). They only build
/// paths: no environment variable is read and nothing is created, because the first listing or writer makes the folder.
/// `URL.applicationSupportDirectory` is the same location as `FileManager.urls(for:in:)`, minus the optional.
public struct AppDirectoriesProviderImpl: AppDirectoriesProvider {
    public init() {}

    public var effectsDirectory: String {
        hostFolder(named: "Effects")
    }

    public var diagnosticsDirectory: String {
        hostFolder(named: "Diagnostics")
    }

    private func hostFolder(named last: String) -> String {
        URL.applicationSupportDirectory
            .appending(path: ProductIdentity.hostBundleID, directoryHint: .isDirectory)
            .appending(path: last, directoryHint: .isDirectory)
            .path
    }
}
