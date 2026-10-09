/// Named seed sets for property tests that want more (or other) runs than `standardSeeds`.
public enum Seeds {
    /// Every seed in `range`, in order: `Seeds.range(0..<50)` runs fifty replays.
    public static func range(_ range: Range<UInt64>) -> [UInt64] {
        Array(range)
    }
}
