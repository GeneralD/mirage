/// The row layout of pixel bytes. A packed image has rows of `width * 4` bytes; a surface has rows of
/// `bytesPerRow` bytes, which may be wider (alignment padding). Both directions check every size before
/// any row is sliced, so input that does not fit answers `nil` instead of trapping.
enum SurfaceRows {
    /// Spreads each packed row of `bgra` to `bytesPerRow`, padding it with zeros.
    static func padded(_ bgra: [UInt8], width: Int, height: Int, bytesPerRow: Int) -> [UInt8]? {
        guard let rowBytes = rowBytes(width: width, height: height, bytesPerRow: bytesPerRow),
            bgra.count == rowBytes * height
        else { return nil }
        return (0..<height).flatMap { row -> [UInt8] in
            Array(bgra[row * rowBytes..<(row + 1) * rowBytes]) + [UInt8](repeating: 0, count: bytesPerRow - rowBytes)
        }
    }

    /// Keeps the first `width * 4` bytes of each `bytesPerRow` row of `padded`, dropping the padding.
    static func packed(_ padded: [UInt8], width: Int, height: Int, bytesPerRow: Int) -> [UInt8]? {
        guard let rowBytes = rowBytes(width: width, height: height, bytesPerRow: bytesPerRow),
            padded.count == bytesPerRow * height
        else { return nil }
        return (0..<height).flatMap { row -> [UInt8] in
            Array(padded[row * bytesPerRow..<row * bytesPerRow + rowBytes])
        }
    }

    /// `width * 4` for a geometry whose rows fit: a positive width and height, and a stride that holds a row.
    private static func rowBytes(width: Int, height: Int, bytesPerRow: Int) -> Int? {
        guard width > 0, height > 0 else { return nil }
        let rowBytes = width * 4
        guard bytesPerRow >= rowBytes else { return nil }
        return rowBytes
    }
}
