import Domain
import Foundation

/// Live `AppDirectoriesProvider`: the effects folder, `Effects` inside a folder named by the host
/// bundle id inside the user's Application Support directory (epic #42, D2). It only builds the path:
/// no environment variable is read and nothing is created, because the first listing makes the folder.
/// `URL.applicationSupportDirectory` is the same location as `FileManager.urls(for:in:)`, minus the optional.
public struct AppDirectoriesProviderImpl: AppDirectoriesProvider {
    public init() {}

    public var effectsDirectory: String {
        URL.applicationSupportDirectory
            .appending(path: ProductIdentity.hostBundleID, directoryHint: .isDirectory)
            .appending(path: "Effects", directoryHint: .isDirectory)
            .path
    }
}
