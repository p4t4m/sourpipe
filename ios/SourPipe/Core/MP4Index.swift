import Foundation

/// Reads the real length of a fragmented MP4 (as YouTube and other DASH services send) from its
/// segment index. AVFoundation adds the fragments to the length the header already declares, so
/// these files load at twice their length with the second half empty.
public enum MP4Index {
    /// Seconds covered by the top-level `sidx` box, or nil if `data` (the start of the file) has none.
    public static func duration(of data: Data) -> Double? {
        let bytes = [UInt8](data)
        var position = 0
        while position + 8 <= bytes.count {
            var size = Int(read32(bytes, position))
            let type = String(bytes: bytes[position + 4 ..< position + 8], encoding: .ascii)
            var header = 8
            if size == 1 {
                guard position + 16 <= bytes.count else { return nil }
                size = Int(read64(bytes, position + 8))
                header = 16
            }
            if type == "sidx" { return sidx(bytes, start: position + header) }
            // Fragments start after the index; nothing to find past the first one.
            if type == "moof" || type == "mdat" || size < header { return nil }
            position += size
        }
        return nil
    }

    private static func sidx(_ b: [UInt8], start: Int) -> Double? {
        guard start + 12 <= b.count else { return nil }
        let version = b[start]
        let timescale = read32(b, start + 8)
        var p = start + 12 + (version == 0 ? 8 : 16)
        guard timescale > 0, p + 4 <= b.count else { return nil }
        let count = Int(UInt16(b[p + 2]) << 8 | UInt16(b[p + 3]))
        p += 4
        guard p + count * 12 <= b.count else { return nil }
        var total: UInt64 = 0
        for index in 0..<count {
            total += UInt64(read32(b, p + index * 12 + 4))
        }
        return total > 0 ? Double(total) / Double(timescale) : nil
    }

    private static func read32(_ b: [UInt8], _ p: Int) -> UInt32 {
        UInt32(b[p]) << 24 | UInt32(b[p + 1]) << 16 | UInt32(b[p + 2]) << 8 | UInt32(b[p + 3])
    }

    private static func read64(_ b: [UInt8], _ p: Int) -> UInt64 {
        UInt64(read32(b, p)) << 32 | UInt64(read32(b, p + 4))
    }
}
