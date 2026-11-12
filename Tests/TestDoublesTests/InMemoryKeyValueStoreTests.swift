import TestDoubles
import Testing

@Suite("InMemoryKeyValueStore removeAll")
struct InMemoryKeyValueStoreRemoveAllTests {
    @Test("removeAll empties values, records one reset, and leaves writes unchanged")
    func removeAllEmptiesValuesWithoutWriting() {
        let store = InMemoryKeyValueStore(["a": "one", "b": "two"])
        store.set("three", forKey: "c")
        store.removeValue(forKey: "a")
        let writesBefore = store.writes.values
        #expect(writesBefore == ["c", "a"])
        #expect(store.resets.count == 0)

        store.removeAll()

        #expect(store.values.isEmpty)
        #expect(store.resets.count == 1)
        #expect(store.writes.values == writesBefore)
    }
}
