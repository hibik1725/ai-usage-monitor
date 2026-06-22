import Foundation

// Faithful port of CodexBar's GrokWebBillingFetcher gRPC-Web/protobuf scanner (MIT).
// The GetGrokCreditsConfig response has no published schema, so we scan the raw
// protobuf generically: a fixed32 (Float) whose field-path ends in field 1 and is
// within 0...100 is the used-percent; a future varint in UNIX-seconds range at path
// [1,5,1] (else the earliest future varint) is the reset time.

public struct GrokBilling: Sendable {
    public var usedPercent: Double?
    public var resetsAt: Date?
}

public enum GrokProtobuf {
    struct Fixed32 { var path: [UInt64]; var value: Float; var order: Int }
    struct Varint { var path: [UInt64]; var value: UInt64 }

    struct Scan {
        var fixed32: [Fixed32] = []
        var varints: [Varint] = []
        mutating func merge(_ o: Scan) {
            fixed32.append(contentsOf: o.fixed32)
            varints.append(contentsOf: o.varints)
        }
    }

    public static func parse(_ data: Data, now: Date = Date()) -> GrokBilling? {
        var payloads = grpcWebDataFrames(from: data)
        if payloads.isEmpty, looksLikeProtobuf(data) { payloads = [data] }
        guard !payloads.isEmpty else { return nil }

        var scan = Scan()
        for p in payloads { scan.merge(scanProtobuf(p, depth: 0, path: [], order: 0).scan) }

        let percent = scan.fixed32
            .filter { $0.path.last == 1 && $0.value.isFinite && $0.value >= 0 && $0.value <= 100 }
            .min { a, b in a.path.count == b.path.count ? a.order < b.order : a.path.count < b.path.count }
            .map { Double($0.value) }

        let resets: [(path: [UInt64], date: Date)] = scan.varints.compactMap { f in
            guard f.value >= 1_700_000_000, f.value <= 2_100_000_000 else { return nil }
            return (f.path, Date(timeIntervalSince1970: TimeInterval(f.value)))
        }
        let future = resets.filter { $0.date > now }
        let reset = future.filter { $0.path == [1, 5, 1] }.map(\.date).min()
            ?? future.map(\.date).min()

        let hasUsagePeriod = scan.varints.contains { f in
            f.path.starts(with: [1, 6]) || (f.path == [1, 8, 1] && (f.value == 1 || f.value == 2))
        }
        let noUsageYet = percent == nil && scan.fixed32.isEmpty && reset != nil && hasUsagePeriod
        guard let p = percent ?? (noUsageYet ? 0 : nil) else { return nil }
        return GrokBilling(usedPercent: p, resetsAt: reset)
    }

    static func looksLikeProtobuf(_ data: Data) -> Bool {
        guard let first = data.first else { return false }
        let field = first >> 3
        let wire = first & 0x07
        return field > 0 && (wire == 0 || wire == 1 || wire == 2 || wire == 5)
    }

    static func grpcWebDataFrames(from data: Data) -> [Data] {
        let bytes = [UInt8](data)
        var frames: [Data] = []
        var i = 0
        while i < bytes.count {
            guard i + 5 <= bytes.count else { return [] }
            let flags = bytes[i]
            let len = (Int(bytes[i + 1]) << 24) | (Int(bytes[i + 2]) << 16)
                | (Int(bytes[i + 3]) << 8) | Int(bytes[i + 4])
            let start = i + 5
            let end = start + len
            guard len >= 0, end <= bytes.count else { return [] }
            if flags & 0x80 == 0 { frames.append(Data(bytes[start..<end])) }
            i = end
        }
        return frames
    }

    /// gRPC-Web trailer (flag bit 0x80) → key/value map. Used to detect grpc-status != 0.
    public static func trailerFields(from data: Data) -> [String: String] {
        let bytes = [UInt8](data)
        var fields: [String: String] = [:]
        var i = 0
        while i + 5 <= bytes.count {
            let flags = bytes[i]
            let len = (Int(bytes[i + 1]) << 24) | (Int(bytes[i + 2]) << 16)
                | (Int(bytes[i + 3]) << 8) | Int(bytes[i + 4])
            let start = i + 5
            let end = start + len
            guard len >= 0, end <= bytes.count else { break }
            if flags & 0x80 != 0, let text = String(data: Data(bytes[start..<end]), encoding: .utf8) {
                for line in text.components(separatedBy: .newlines) where !line.isEmpty {
                    guard let sep = line.firstIndex(of: ":") else { continue }
                    let key = line[..<sep].trimmingCharacters(in: .whitespaces).lowercased()
                    let val = line[line.index(after: sep)...].trimmingCharacters(in: .whitespaces)
                    fields[key] = val.removingPercentEncoding ?? val
                }
            }
            i = end
        }
        return fields
    }

    private static func scanProtobuf(
        _ data: Data, depth: Int, path: [UInt64], order: Int
    ) -> (scan: Scan, order: Int) {
        let bytes = [UInt8](data)
        var scan = Scan()
        var i = 0
        var nextOrder = order

        while i < bytes.count {
            let fieldStart = i
            guard let key = readVarint(bytes, index: &i), key != 0 else {
                i = fieldStart + 1
                continue
            }
            let fieldNumber = key >> 3
            let wire = key & 0x07
            let fieldPath = path + [fieldNumber]

            switch wire {
            case 0:
                if let v = readVarint(bytes, index: &i) {
                    scan.varints.append(Varint(path: fieldPath, value: v))
                } else { i = fieldStart + 1 }
            case 1:
                guard i + 8 <= bytes.count else { return (scan, nextOrder) }
                i += 8
            case 2:
                guard let len = readVarint(bytes, index: &i),
                      len <= UInt64(bytes.count - i)
                else { i = fieldStart + 1; continue }
                let start = i
                let end = i + Int(len)
                if depth < 4 {
                    let nested = scanProtobuf(Data(bytes[start..<end]), depth: depth + 1,
                                              path: fieldPath, order: nextOrder)
                    scan.merge(nested.scan)
                    nextOrder = nested.order
                }
                i = end
            case 5:
                guard i + 4 <= bytes.count else { return (scan, nextOrder) }
                let bits = UInt32(bytes[i]) | (UInt32(bytes[i + 1]) << 8)
                    | (UInt32(bytes[i + 2]) << 16) | (UInt32(bytes[i + 3]) << 24)
                scan.fixed32.append(Fixed32(path: fieldPath, value: Float(bitPattern: bits), order: nextOrder))
                nextOrder += 1
                i += 4
            default:
                i = fieldStart + 1
            }
        }
        return (scan, nextOrder)
    }

    private static func readVarint(_ bytes: [UInt8], index: inout Int) -> UInt64? {
        var value: UInt64 = 0
        var shift: UInt64 = 0
        while index < bytes.count, shift < 64 {
            let byte = bytes[index]
            index += 1
            value |= UInt64(byte & 0x7F) << shift
            if byte & 0x80 == 0 { return value }
            shift += 7
        }
        return nil
    }
}
