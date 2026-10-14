import Darwin
import Foundation

/// How many descriptors of this process refer to `path` right now, read from the kernel with
/// `F_GETPATH`. This is how a test sees that a watch's descriptor was closed: a descriptor has no
/// other observable end. Pass a UUID-named path so a parallel suite's descriptors never match.
///
/// `F_GETPATH` answers with the resolved path (`/private/var/...` for a `/var/...` temporary
/// directory), so `path` goes through `realpath` first; Foundation's `resolvingSymlinksInPath()`
/// maps `/private/var` back to `/var` and would never match. Descriptors are handed out lowest
/// first, so the scan stops at 4096 rather than at the (very large) table size.
func openDescriptorCount(at path: String) -> Int {
    guard let resolved = realpath(path, nil) else { return 0 }
    defer { free(resolved) }
    let target = String(cString: resolved)
    return (0..<4096).filter { descriptor in
        // A `var`: `F_GETPATH` fills the buffer through the pointer.
        var buffer = [CChar](repeating: 0, count: Int(MAXPATHLEN))
        return fcntl(Int32(descriptor), F_GETPATH, &buffer) != -1 && String(cString: buffer) == target
    }.count
}
