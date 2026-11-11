import Foundation

/// One fenced code block of a Markdown document: the info string split into its language and its `key=value` attributes, the lines
/// inside the fence (each followed by a newline), and the 1-based line the fence opens on.
public struct MarkdownFence: Sendable, Hashable {
    public let language: String
    public let attributes: [String: String]
    public let text: String
    public let line: Int

    public init(language: String, attributes: [String: String], text: String, line: Int) {
        self.language = language
        self.attributes = attributes
        self.text = text
        self.line = line
    }
}

/// Why a repository file could not be read.
public enum MarkdownFenceError: Error, Equatable {
    /// No folder at or above the given source file holds a `Package.swift`, so the repository root is unknown.
    case noRepositoryRoot(String)
    /// The file at the given repository-relative path is missing or is not UTF-8.
    case unreadable(String)
}

/// The fenced code blocks of a Markdown document, read the way CommonMark reads them, so a suite can run the examples a document
/// shows. Only fences are read: headings, tables and links are other suites' concern.
public enum MarkdownFences {
    /// Every fenced code block of `markdown`, in document order. A fence that is never closed runs to the end of the document.
    public static func all(in markdown: String) -> [MarkdownFence] {
        let scan = documentLines(markdown).enumerated().reduce(into: Scan()) { state, numbered in
            let (offset, line) = numbered
            if let pending = state.open {
                if closes(line, pending) {
                    state.fences.append(pending.fence)
                    state.open = nil
                } else {
                    state.open = pending.appending(unindented(line, by: pending.indent))
                }
            } else {
                state.open = opener(line, openedAt: offset + 1)
            }
        }
        return scan.open.map { scan.fences + [$0.fence] } ?? scan.fences
    }

    /// The UTF-8 text of the file at `path`, given relative to the repository root. The root is the first folder, going up from the
    /// folder of `filePath`, that holds a `Package.swift`. Pass the caller's `#filePath` so the root is found from the calling suite.
    public static func read(_ path: String, from filePath: String = #filePath) throws -> String {
        guard let root = enclosingRepository(of: URL(fileURLWithPath: filePath).deletingLastPathComponent()) else {
            throw MarkdownFenceError.noRepositoryRoot(filePath)
        }
        guard let text = try? String(contentsOf: root.appending(path: path), encoding: .utf8) else {
            throw MarkdownFenceError.unreadable(path)
        }
        return text
    }

    private static func enclosingRepository(of folder: URL) -> URL? {
        if FileManager.default.fileExists(atPath: folder.appending(path: "Package.swift").path) {
            return folder
        }
        let parent = folder.deletingLastPathComponent()
        return parent.path == folder.path ? nil : enclosingRepository(of: parent)
    }

    /// The lines of the document, with `\r\n` read as `\n`. The newline that ends the last line does not start a line of its own.
    private static func documentLines(_ markdown: String) -> [String] {
        let lines = markdown.replacingOccurrences(of: "\r\n", with: "\n")
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)
        return lines.last == "" ? Array(lines.dropLast()) : lines
    }

    /// The fence a line opens, if it opens one: up to three spaces, three or more backticks or tildes, then the info string. A backtick
    /// fence's info string holds no backtick.
    private static func opener(_ line: String, openedAt: Int) -> OpenFence? {
        let indent = leadingSpaces(line)
        let rest = line.dropFirst(indent)
        guard indent <= 3, let marker = rest.first, marker == "`" || marker == "~" else { return nil }
        let length = rest.prefix(while: { $0 == marker }).count
        let info = rest.dropFirst(length).trimmingCharacters(in: .whitespaces)
        guard length >= 3, marker == "~" || !info.contains("`") else { return nil }
        return OpenFence(marker: marker, length: length, indent: indent, info: info, openedAt: openedAt, body: [])
    }

    /// Whether a line closes the open fence: up to three spaces, at least as many of the same marker, then only whitespace.
    private static func closes(_ line: String, _ pending: OpenFence) -> Bool {
        let indent = leadingSpaces(line)
        let rest = line.dropFirst(indent)
        let run = rest.prefix(while: { $0 == pending.marker }).count
        return indent <= 3 && run >= pending.length && rest.dropFirst(run).allSatisfy { $0 == " " || $0 == "\t" }
    }

    /// A body line with up to as many leading spaces removed as the opening line was indented.
    private static func unindented(_ line: String, by indent: Int) -> String {
        String(line.dropFirst(min(indent, leadingSpaces(line))))
    }

    private static func leadingSpaces(_ line: String) -> Int {
        line.prefix(while: { $0 == " " }).count
    }

    /// What the scan carries: the fences finished so far, and the fence still open.
    private struct Scan {
        var fences: [MarkdownFence] = []
        var open: OpenFence?
    }

    /// A fence whose closing line has not been seen yet.
    private struct OpenFence {
        let marker: Character
        let length: Int
        let indent: Int
        let info: String
        let openedAt: Int
        let body: [String]

        func appending(_ line: String) -> OpenFence {
            OpenFence(marker: marker, length: length, indent: indent, info: info, openedAt: openedAt, body: body + [line])
        }

        /// The first word of the info string is the language, unless it is a `key=value` pair; every other word is an attribute. A word
        /// without `=` is an attribute with an empty value, and a repeated key keeps its last value.
        var fence: MarkdownFence {
            let words = info.split(whereSeparator: { $0 == " " || $0 == "\t" }).map(String.init)
            let language = words.first.flatMap { $0.contains("=") ? nil : $0 } ?? ""
            let attributeWords = language.isEmpty ? words : Array(words.dropFirst())
            let attributes = attributeWords.reduce(into: [String: String]()) { pairs, word in
                if let equals = word.firstIndex(of: "=") {
                    pairs[String(word[..<equals])] = String(word[word.index(after: equals)...])
                } else {
                    pairs[word] = ""
                }
            }
            return MarkdownFence(language: language, attributes: attributes, text: body.map { $0 + "\n" }.joined(), line: openedAt)
        }
    }
}
