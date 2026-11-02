import Foundation

/// Reads NewPipe's backup zips. Written in plain Swift because iOS has no public zip API.
public struct ZipArchive {
    public enum Failure: Error, Equatable {
        case notAZip, unsupported(String), corrupt(String), missing(String)
    }

    private struct Entry {
        let method: Int
        let crc: UInt32
        let compressedSize: Int
        let size: Int
        let headerOffset: Int
    }

    private let bytes: [UInt8]
    private var entries: [String: Entry] = [:]

    public var names: [String] { entries.keys.sorted() }

    public init(_ data: Data) throws {
        bytes = [UInt8](data)
        guard bytes.count >= 22 else { throw Failure.notAZip }
        // The end record sits at the end, followed by a comment of at most 64 KB.
        var end = bytes.count - 22
        let lowest = max(0, end - 0xFFFF)
        while end >= lowest, u32(end) != 0x0605_4B50 { end -= 1 }
        guard end >= lowest else { throw Failure.notAZip }

        var offset = Int(u32(end + 16))
        let count = Int(u16(end + 10))
        if count == 0xFFFF || offset == 0xFFFF_FFFF {
            throw Failure.unsupported("zip64")
        }
        for _ in 0..<count {
            guard offset + 46 <= bytes.count, u32(offset) == 0x0201_4B50 else {
                throw Failure.corrupt("central directory")
            }
            let nameLength = Int(u16(offset + 28))
            let extraLength = Int(u16(offset + 30))
            let commentLength = Int(u16(offset + 32))
            guard offset + 46 + nameLength <= bytes.count else {
                throw Failure.corrupt("entry name")
            }
            let name = String(decoding: bytes[(offset + 46)..<(offset + 46 + nameLength)],
                              as: UTF8.self)
            entries[name] = Entry(method: Int(u16(offset + 10)), crc: u32(offset + 16),
                                  compressedSize: Int(u32(offset + 20)),
                                  size: Int(u32(offset + 24)),
                                  headerOffset: Int(u32(offset + 42)))
            offset += 46 + nameLength + extraLength + commentLength
        }
    }

    public func read(_ name: String) throws -> Data {
        guard let entry = entries[name] else { throw Failure.missing(name) }
        let header = entry.headerOffset
        guard header + 30 <= bytes.count, u32(header) == 0x0403_4B50 else {
            throw Failure.corrupt(name)
        }
        let start = header + 30 + Int(u16(header + 26)) + Int(u16(header + 28))
        guard start + entry.compressedSize <= bytes.count else { throw Failure.corrupt(name) }
        let raw = bytes[start..<(start + entry.compressedSize)]
        let output: [UInt8]
        switch entry.method {
        case 0: output = Array(raw)
        case 8: output = try Inflate.decompress(Array(raw), expectedSize: entry.size)
        default: throw Failure.unsupported("compression method \(entry.method)")
        }
        guard output.count == entry.size, CRC32.checksum(output) == entry.crc else {
            throw Failure.corrupt(name)
        }
        return Data(output)
    }

    private func u16(_ i: Int) -> UInt16 { UInt16(bytes[i]) | UInt16(bytes[i + 1]) << 8 }
    private func u32(_ i: Int) -> UInt32 {
        UInt32(bytes[i]) | UInt32(bytes[i + 1]) << 8 | UInt32(bytes[i + 2]) << 16
            | UInt32(bytes[i + 3]) << 24
    }
}

enum CRC32 {
    private static let table: [UInt32] = (0..<256).map { index -> UInt32 in
        var c = UInt32(index)
        for _ in 0..<8 { c = c & 1 == 1 ? 0xEDB8_8320 ^ (c >> 1) : c >> 1 }
        return c
    }

    static func checksum(_ bytes: [UInt8]) -> UInt32 {
        var c: UInt32 = 0xFFFF_FFFF
        for byte in bytes { c = table[Int((c ^ UInt32(byte)) & 0xFF)] ^ (c >> 8) }
        return c ^ 0xFFFF_FFFF
    }
}

/// RFC 1951 DEFLATE decoder.
enum Inflate {
    private static let lengthBase = [3, 4, 5, 6, 7, 8, 9, 10, 11, 13, 15, 17, 19, 23, 27, 31, 35, 43,
                                     51, 59, 67, 83, 99, 115, 131, 163, 195, 227, 258]
    private static let lengthExtra = [0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 2, 2, 2, 2, 3, 3, 3, 3, 4,
                                      4, 4, 4, 5, 5, 5, 5, 0]
    private static let distanceBase = [1, 2, 3, 4, 5, 7, 9, 13, 17, 25, 33, 49, 65, 97, 129, 193, 257,
                                       385, 513, 769, 1025, 1537, 2049, 3073, 4097, 6145, 8193,
                                       12289, 16385, 24577]
    private static let distanceExtra = [0, 0, 0, 0, 1, 1, 2, 2, 3, 3, 4, 4, 5, 5, 6, 6, 7, 7, 8, 8, 9,
                                        9, 10, 10, 11, 11, 12, 12, 13, 13]
    private static let codeOrder = [16, 17, 18, 0, 8, 7, 9, 6, 10, 5, 11, 4, 12, 3, 13, 2, 14, 1, 15]

    private struct Huffman {
        var counts = [Int](repeating: 0, count: 16)
        var symbols: [Int]

        init(lengths: ArraySlice<Int>) {
            symbols = [Int](repeating: 0, count: lengths.count)
            for length in lengths { counts[length] += 1 }
            counts[0] = 0
            var offsets = [Int](repeating: 0, count: 16)
            for i in 1..<15 { offsets[i + 1] = offsets[i] + counts[i] }
            for (symbol, length) in lengths.enumerated() where length != 0 {
                symbols[offsets[length]] = symbol
                offsets[length] += 1
            }
        }
    }

    private struct Bits {
        let input: [UInt8]
        var position = 0
        var buffer = 0
        var available = 0

        mutating func take(_ count: Int) throws -> Int {
            while available < count {
                guard position < input.count else { throw ZipArchive.Failure.corrupt("deflate") }
                buffer |= Int(input[position]) << available
                position += 1
                available += 8
            }
            let value = buffer & ((1 << count) - 1)
            buffer >>= count
            available -= count
            return value
        }

        mutating func decode(_ table: Huffman) throws -> Int {
            var code = 0, first = 0, index = 0
            for length in 1...15 {
                code |= try take(1)
                let count = table.counts[length]
                if code - count < first { return table.symbols[index + (code - first)] }
                index += count
                first = (first + count) << 1
                code <<= 1
            }
            throw ZipArchive.Failure.corrupt("deflate code")
        }
    }

    static func decompress(_ input: [UInt8], expectedSize: Int) throws -> [UInt8] {
        var bits = Bits(input: input)
        var output = [UInt8]()
        output.reserveCapacity(expectedSize)
        var isLast = false
        while !isLast {
            isLast = try bits.take(1) == 1
            switch try bits.take(2) {
            case 0:
                bits.buffer = 0
                bits.available = 0
                guard bits.position + 4 <= input.count else {
                    throw ZipArchive.Failure.corrupt("deflate")
                }
                let length = Int(input[bits.position]) | Int(input[bits.position + 1]) << 8
                bits.position += 4
                guard bits.position + length <= input.count else {
                    throw ZipArchive.Failure.corrupt("deflate")
                }
                output += input[bits.position..<(bits.position + length)]
                bits.position += length
            case 1:
                var lengths = [Int](repeating: 8, count: 288)
                for i in 144..<256 { lengths[i] = 9 }
                for i in 256..<280 { lengths[i] = 7 }
                try inflateBlock(&bits, &output, Huffman(lengths: lengths[...]),
                                 Huffman(lengths: [Int](repeating: 5, count: 30)[...]))
            case 2:
                let literalCount = try bits.take(5) + 257
                let distanceCount = try bits.take(5) + 1
                let codeCount = try bits.take(4) + 4
                var codeLengths = [Int](repeating: 0, count: 19)
                for i in 0..<codeCount { codeLengths[codeOrder[i]] = try bits.take(3) }
                let codes = Huffman(lengths: codeLengths[...])
                var lengths = [Int]()
                while lengths.count < literalCount + distanceCount {
                    let symbol = try bits.decode(codes)
                    switch symbol {
                    case 0..<16: lengths.append(symbol)
                    case 16:
                        guard let last = lengths.last else {
                            throw ZipArchive.Failure.corrupt("deflate lengths")
                        }
                        lengths += [Int](repeating: last, count: try bits.take(2) + 3)
                    case 17: lengths += [Int](repeating: 0, count: try bits.take(3) + 3)
                    default: lengths += [Int](repeating: 0, count: try bits.take(7) + 11)
                    }
                }
                guard lengths.count == literalCount + distanceCount else {
                    throw ZipArchive.Failure.corrupt("deflate lengths")
                }
                try inflateBlock(&bits, &output, Huffman(lengths: lengths[..<literalCount]),
                                 Huffman(lengths: lengths[literalCount...]))
            default:
                throw ZipArchive.Failure.corrupt("deflate block type")
            }
        }
        return output
    }

    private static func inflateBlock(_ bits: inout Bits, _ output: inout [UInt8],
                                     _ literals: Huffman, _ distances: Huffman) throws {
        while true {
            let symbol = try bits.decode(literals)
            if symbol < 256 {
                output.append(UInt8(symbol))
            } else if symbol == 256 {
                return
            } else {
                guard symbol - 257 < lengthBase.count else {
                    throw ZipArchive.Failure.corrupt("deflate length")
                }
                let length = lengthBase[symbol - 257] + (try bits.take(lengthExtra[symbol - 257]))
                let code = try bits.decode(distances)
                guard code < distanceBase.count else {
                    throw ZipArchive.Failure.corrupt("deflate distance")
                }
                let distance = distanceBase[code] + (try bits.take(distanceExtra[code]))
                guard distance <= output.count else {
                    throw ZipArchive.Failure.corrupt("deflate distance")
                }
                for _ in 0..<length { output.append(output[output.count - distance]) }
            }
        }
    }
}
