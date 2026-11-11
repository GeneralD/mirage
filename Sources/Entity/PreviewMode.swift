/// What the preview shows of each frame the pipeline presents: the output alone
/// (`after`, the default), or the output with the input its pass was run on
/// (`split`), so a before/after view can draw both.
public enum PreviewMode: Sendable, Hashable, CaseIterable {
    case after, split
}
