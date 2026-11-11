import Domain
import Foundation

/// The package `id` of `Examples/`, read through the same DataSource an author's folder goes through, when
/// it reads as ready. Every file of the package is copied byte for byte into the in-memory tree, as
/// `ExamplePackagesTests` does, so a suite that holds one example to what it says sees what the README ships.
func loadedExample(_ id: String) async throws -> EffectPackage {
    let rig = PackageRig()
    for file in try ExamplePackagesTests.files(in: id) {
        rig.files.write("\(PackageRig.folder)/\(id)\(ExamplePackagesTests.suffix)/\(file.path)", bytes: file.bytes)
    }
    let listing = await rig.subject.package(.package(id))
    guard case .ready(let package)? = listing else {
        throw ExampleNotReady(id: id, listing: listing)
    }
    return package
}

/// An example that did not read as ready, with what it read as (`nil` when the folder holds no such package).
struct ExampleNotReady: Error, CustomStringConvertible {
    let id: String
    let listing: EffectPackageListing?

    var description: String {
        "example \(id) did not read as ready: \(String(describing: listing))"
    }
}
