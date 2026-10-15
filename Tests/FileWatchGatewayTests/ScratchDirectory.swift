import Foundation

/// A directory of its own under the system temporary directory, named by a UUID so
/// parallel suites never meet. Real file system, no environment variable read; the
/// test removes it with `remove()` (in a `defer`), leaving nothing behind.
struct ScratchDirectory {
    let url: URL

    var path: String { url.path }

    init() throws {
        url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    /// The path of `name` inside the directory (nothing is created).
    func appending(_ name: String) -> String {
        url.appendingPathComponent(name).path
    }

    func remove() {
        try? FileManager.default.removeItem(at: url)
    }
}
