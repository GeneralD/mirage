import Domain
import Foundation
import Testing

@testable import UserDefaultsGateway

/// The live smoke of the defaults gateway: a real `UserDefaults` suite named by a UUID, so the
/// user's own defaults are never read or written, and removed again after every test.
@Suite("KeyValueStoreGatewayImpl", .timeLimit(.minutes(1)))
struct KeyValueStoreGatewayImplTests {
    /// Runs `body` over a gateway on a fresh suite, then removes the suite and asserts it is gone.
    private func withSuite(_ body: (KeyValueStoreGatewayImpl, UserDefaults) throws -> Void) throws {
        let name = UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: name))
        defer {
            defaults.removePersistentDomain(forName: name)
            #expect(defaults.persistentDomain(forName: name) == nil, "the suite \(name) is removed after the test")
            removeEmptiedPlist(of: name)
        }
        try body(KeyValueStoreGatewayImpl(defaults: defaults), defaults)
    }

    /// Emptying a domain leaves its (empty) plist in the user's Preferences folder. The suite is
    /// named by a UUID and was ours alone, so the stub goes with it instead of piling up per run.
    private func removeEmptiedPlist(of name: String) {
        guard let library = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first else { return }
        try? FileManager.default.removeItem(at: library.appending(path: "Preferences/\(name).plist"))
    }

    @Test("a key that was never set reads as nil")
    func neverSet() throws {
        try withSuite { gateway, _ in
            #expect(gateway.string(forKey: "selectedEffect") == nil)
        }
    }

    @Test("set, then string, then remove, then nil")
    func roundTrip() throws {
        try withSuite { gateway, _ in
            gateway.set("package:glitch", forKey: "selectedEffect")
            #expect(gateway.string(forKey: "selectedEffect") == "package:glitch")
            gateway.removeValue(forKey: "selectedEffect")
            #expect(gateway.string(forKey: "selectedEffect") == nil)
        }
    }

    @Test("a value goes to the defaults it was given, under the key it was given")
    func writesThrough() throws {
        try withSuite { gateway, defaults in
            gateway.set("bundled:Chromatic Grain", forKey: "selectedEffect")
            #expect(defaults.string(forKey: "selectedEffect") == "bundled:Chromatic Grain")
            defaults.set("package:other", forKey: "selectedEffect")
            #expect(gateway.string(forKey: "selectedEffect") == "package:other")
        }
    }

    @Test("setting a key again replaces its value and leaves the other keys alone")
    func overwriteAndIndependence() throws {
        try withSuite { gateway, _ in
            gateway.set("one", forKey: "a")
            gateway.set("two", forKey: "b")
            gateway.set("three", forKey: "a")
            #expect(gateway.string(forKey: "a") == "three")
            #expect(gateway.string(forKey: "b") == "two")
            gateway.removeValue(forKey: "a")
            #expect(gateway.string(forKey: "a") == nil)
            #expect(gateway.string(forKey: "b") == "two")
        }
    }

    @Test("removing a key that is not there does nothing")
    func removeMissing() throws {
        try withSuite { gateway, _ in
            gateway.removeValue(forKey: "missing")
            gateway.set("kept", forKey: "other")
            gateway.removeValue(forKey: "missing")
            #expect(gateway.string(forKey: "missing") == nil)
            #expect(gateway.string(forKey: "other") == "kept")
        }
    }

    @Test("an empty string is a value, not an absent key")
    func emptyValue() throws {
        try withSuite { gateway, _ in
            gateway.set("", forKey: "empty")
            #expect(gateway.string(forKey: "empty") == "")
        }
    }
}
