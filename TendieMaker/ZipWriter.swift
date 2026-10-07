import Foundation

/// Minimal ZIP writer — stores files uncompressed (method 0).
/// No dependencies, no deflate bugs. JPEGs barely compress anyway,
/// so the size difference vs deflate is negligible.
struct ZipWriter {
    private struct Entry {
        let name: Data
        let data: Data
    }
    private var entries: [Entry] = []

    mutating func add(name: String, data: Data) {
        entries.append(Entry(name: name.data(using: .utf8)!, data: data))
    }

    // MARK: - CRC32

    private static let crcTable: [UInt32] = (0..<256).map { i in
        var c = UInt32(i)
        for _ in 0..<8 {
            c = (c & 1) != 0 ? 0xEDB8_8320 ^ (c >> 1) : c >> 1
        }
        return c
    }

    private static func crc32(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFF_FFFF
        for byte in data {
            crc = crcTable[Int((crc ^ UInt32(byte)) & 0xFF)] ^ (crc >> 8)
        }
        return crc ^ 0xFFFF_FFFF
    }

    // MARK: - Archive (stored, no compression)

    private static func dosDateTime(_ date: Date) -> (time: UInt16, date: UInt16) {
        let c = Calendar(identifier: .gregorian).dateComponents(
            [.year, .month, .day, .hour, .minute, .second], from: date)
        let t = UInt16(((c.hour ?? 0) << 11) | ((c.minute ?? 0) << 5) | ((c.second ?? 0) >> 1))
        let d = UInt16((((c.year ?? 1980) - 1980) << 9) | ((c.month ?? 1) << 5) | (c.day ?? 1))
        return (t, d)
    }

    // MARK: - Archive data

    func archive() throws -> Data {
        var out = Data()
        struct Central {
            let name: Data
            let crc: UInt32
            let csize: Int
            let usize: Int
            let offset: Int
            let time: UInt16
            let date: UInt16
        }
        var central: [Central] = []

        for e in entries {
            let crc = Self.crc32(e.data)
            let (dt, dd) = Self.dosDateTime(Date())
            let offset = out.count
            // local file header
            out.appendLE(UInt32(0x0403_4B50))
            out.appendLE(UInt16(20))          // version needed
            out.appendLE(UInt16(0x0800))       // UTF-8 flag
            out.appendLE(UInt16(0))            // stored (no compression)
            out.appendLE(dt)
            out.appendLE(dd)
            out.appendLE(crc)
            out.appendLE(UInt32(e.data.count))
            out.appendLE(UInt32(e.data.count))
            out.appendLE(UInt16(e.name.count))
            out.appendLE(UInt16(0))            // extra length
            out.append(e.name)
            out.append(e.data)
            central.append(Central(name: e.name, crc: crc, csize: e.data.count,
                                   usize: e.data.count, offset: offset, time: dt, date: dd))
        }

        let centralStart = out.count
        for c in central {
            out.appendLE(UInt32(0x0201_4B50))
            out.appendLE(UInt16(20))          // version made by
            out.appendLE(UInt16(20))          // version needed
            out.appendLE(UInt16(0x0800))
            out.appendLE(UInt16(0))
            out.appendLE(c.time)
            out.appendLE(c.date)
            out.appendLE(c.crc)
            out.appendLE(UInt32(c.csize))
            out.appendLE(UInt32(c.usize))
            out.appendLE(UInt16(c.name.count))
            out.appendLE(UInt16(0)); out.appendLE(UInt16(0))  // extra, comment
            out.appendLE(UInt16(0))            // disk number
            out.appendLE(UInt16(0))            // internal attrs
            out.appendLE(UInt32(0))            // external attrs
            out.appendLE(UInt32(c.offset))
            out.append(c.name)
        }
        let centralSize = out.count - centralStart
        // end of central directory
        out.appendLE(UInt32(0x0605_4B50))
        out.appendLE(UInt16(0)); out.appendLE(UInt16(0))
        out.appendLE(UInt16(central.count)); out.appendLE(UInt16(central.count))
        out.appendLE(UInt32(centralSize))
        out.appendLE(UInt32(centralStart))
        out.appendLE(UInt16(0))
        return out
    }
}

private extension Data {
    mutating func appendLE<T: FixedWidthInteger>(_ v: T) {
        var x = v.littleEndian
        Swift.withUnsafeBytes(of: &x) { append(contentsOf: $0) }
    }
}
