import Domain
import Foundation

/// Live `AppDirectoriesProvider`: the user's Application Support folder as the OS answers it, and nothing below
/// it (epic #42, D2; the app's own folders are the DataSources' to name). It only reads a path: no environment
/// variable is read and nothing is created. `URL.applicationSupportDirectory` is the same location as
/// `FileManager.urls(for:in:)`, minus the optional.
public struct AppDirectoriesProviderImpl: AppDirectoriesProvider {
    public init() {}

    public var applicationSupportDirectory: String {
        URL.applicationSupportDirectory.path
    }
}
