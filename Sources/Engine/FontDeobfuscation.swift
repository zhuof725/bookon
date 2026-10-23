import Foundation
import CommonCrypto

/// Legado `queryTTF` / `replaceFont` 的字体反爬支持。
/// 只实现这两个函数需要的部分：cmap（Unicode → 轮廓索引）、loca/glyf（轮廓数据）。
/// 轮廓数据用 glyf 原始字节的十六进制串作为 key；同一字体族的混淆字体 glyf 表通常完全一致。
final class SourceFont {
    private let data: Data
    private let tables: [String: (offset: Int, length: Int)]
    private let glyphOffsets: [Int]
    private let unicodeToGlyphID: [Int: Int]
    private var glyphHexCache: [Int: String] = [:]
    private var reverseMap: [String: Int]?

    init?(data: Data) {
        guard data.count > 12 else { return nil }
        self.data = data
        guard let numTables = Self.u16(data, 4) else { return nil }
        var tables: [String: (offset: Int, length: Int)] = [:]
        var p = 12
        for _ in 0..<Int(numTables) {
            guard let tagData = Self.bytes(data, p, 4),
                  let offset = Self.u32(data, p + 8),
                  let length = Self.u32(data, p + 12) else { return nil }
            let tag = String(data: tagData, encoding: .ascii) ?? ""
            tables[tag] = (offset: Int(offset), length: Int(length))
            p += 16
        }
        self.tables = tables
        guard let head = tables["head"], let maxp = tables["maxp"],
              let loca = tables["loca"], let cmap = tables["cmap"] else { return nil }
        guard let locFormat = Self.i16(data, head.offset + 50),
              let numGlyphs = Self.u16(data, maxp.offset + 4) else { return nil }
        // loca：numGlyphs + 1 个偏移
        var offsets: [Int] = []
        offsets.reserveCapacity(Int(numGlyphs) + 1)
        if locFormat == 0 {
            for i in 0...Int(numGlyphs) {
                guard let v = Self.u16(data, loca.offset + i * 2) else { return nil }
                offsets.append(Int(v) * 2)
            }
        } else {
            for i in 0...Int(numGlyphs) {
                guard let v = Self.u32(data, loca.offset + i * 4) else { return nil }
                offsets.append(Int(v))
            }
        }
        self.glyphOffsets = offsets
        self.unicodeToGlyphID = Self.parseCmap(data: data, cmapOffset: cmap.offset, length: cmap.length) ?? [:]
    }

    // MARK: - 公开查询

    func glyphID(for unicode: Int) -> Int {
        unicodeToGlyphID[unicode] ?? 0
    }

    func glyphHex(for unicode: Int) -> String? {
        let gid = glyphID(for: unicode)
        guard gid > 0 else { return nil }
        return glyphHex(glyphID: gid)
    }

    func glyphHex(glyphID gid: Int) -> String? {
        if let cached = glyphHexCache[gid] { return cached }
        guard gid >= 0, gid + 1 < glyphOffsets.count,
              let glyf = tables["glyf"] else { return nil }
        let start = glyphOffsets[gid], end = glyphOffsets[gid + 1]
        guard end > start, start >= 0, end <= glyf.length else { return nil }
        let absolute = glyf.offset + start
        guard let sub = Self.bytes(data, absolute, end - start) else { return nil }
        let hex = sub.map { String(format: "%02x", $0) }.joined()
        glyphHexCache[gid] = hex
        return hex
    }

    func unicode(forGlyph hex: String) -> Int {
        if reverseMap == nil {
            var map: [String: Int] = [:]
            for (unicode, gid) in unicodeToGlyphID {
                guard let g = glyphHex(glyphID: gid) else { continue }
                if map[g] == nil { map[g] = unicode }
            }
            reverseMap = map
        }
        return reverseMap?[hex] ?? 0
    }

    func isBlankUnicode(_ unicode: Int) -> Bool {
        switch unicode {
        case 0x0009, 0x0020, 0x00A0, 0x2002, 0x2003, 0x2007, 0x200A,
             0x200B, 0x200C, 0x200D, 0x202F, 0x205F:
            return true
        default:
            return false
        }
    }

    // MARK: - cmap

    private static func parseCmap(data: Data, cmapOffset: Int, length: Int) -> [Int: Int]? {
        guard let count = u16(data, cmapOffset + 2) else { return nil }
        var best: (format: Int, offset: Int, score: Int)?
        for i in 0..<Int(count) {
            let record = cmapOffset + 4 + i * 8
            guard let platform = u16(data, record),
                  let encoding = u16(data, record + 2),
                  let subOffset = u32(data, record + 4) else { continue }
            let absolute = cmapOffset + Int(subOffset)
            guard absolute >= cmapOffset, absolute + 2 <= cmapOffset + length,
                  let format = u16(data, absolute) else { continue }
            var score = 0
            if platform == 3 && encoding == 10 { score = 4 }
            else if platform == 0 && (encoding == 4 || encoding == 6) { score = 3 }
            else if platform == 3 && encoding == 1 { score = 2 }
            else if platform == 0 { score = 1 }
            guard score > 0 else { continue }
            if best == nil || score > best!.score {
                best = (Int(format), absolute, score)
            }
        }
        guard let chosen = best else { return nil }
        if chosen.format == 12 { return parseFormat12(data: data, offset: chosen.offset) }
        if chosen.format == 4 { return parseFormat4(data: data, offset: chosen.offset) }
        return nil
    }

    private static func parseFormat4(data: Data, offset: Int) -> [Int: Int]? {
        guard let segCountX2 = u16(data, offset + 6) else { return nil }
        let segCount = Int(segCountX2) / 2
        guard segCount > 0 else { return nil }
        let endBase = offset + 14
        let startBase = endBase + segCount * 2 + 2
        let deltaBase = startBase + segCount * 2
        let rangeBase = deltaBase + segCount * 2
        var map: [Int: Int] = [:]
        for i in 0..<segCount {
            guard let end = u16(data, endBase + i * 2),
                  let start = u16(data, startBase + i * 2),
                  let delta = i16(data, deltaBase + i * 2),
                  let rangeOffset = u16(data, rangeBase + i * 2) else { continue }
            if start > end { continue }
            for cp in Int(start)...Int(end) {
                if cp == 0xFFFF { continue }
                var gid = 0
                if rangeOffset == 0 {
                    gid = (cp &+ Int(delta)) & 0xFFFF
                } else {
                    let addr = rangeBase + i * 2 + Int(rangeOffset) + (cp - Int(start)) * 2
                    guard let raw = u16(data, addr), raw != 0 else { continue }
                    gid = (Int(raw) &+ Int(delta)) & 0xFFFF
                }
                if gid > 0 { map[cp] = gid }
            }
        }
        return map
    }

    private static func parseFormat12(data: Data, offset: Int) -> [Int: Int]? {
        guard let groups = u32(data, offset + 12) else { return nil }
        var map: [Int: Int] = [:]
        var p = offset + 16
        for _ in 0..<Int(groups) {
            guard let start = u32(data, p), let end = u32(data, p + 4),
                  let startGlyph = u32(data, p + 8) else { return map }
            if start <= end, end - start < 0x20000 {
                for cp in Int(start)...Int(end) {
                    map[cp] = Int(startGlyph) + (cp - Int(start))
                }
            }
            p += 12
        }
        return map
    }

    // MARK: - 字节读取

    static func bytes(_ data: Data, _ offset: Int, _ length: Int) -> Data? {
        guard offset >= 0, length >= 0, offset + length <= data.count else { return nil }
        return data.subdata(in: offset..<(offset + length))
    }

    static func u16(_ data: Data, _ offset: Int) -> UInt16? {
        guard offset >= 0, offset + 2 <= data.count else { return nil }
        return (UInt16(data[offset]) << 8) | UInt16(data[offset + 1])
    }

    static func i16(_ data: Data, _ offset: Int) -> Int16? {
        guard let v = u16(data, offset) else { return nil }
        return Int16(bitPattern: v)
    }

    static func u32(_ data: Data, _ offset: Int) -> UInt32? {
        guard offset >= 0, offset + 4 <= data.count else { return nil }
        return (UInt32(data[offset]) << 24) | (UInt32(data[offset + 1]) << 16)
            | (UInt32(data[offset + 2]) << 8) | UInt32(data[offset + 3])
    }
}

/// queryTTF 返回给 JS 的字体对象注册表（JS 侧只持有整数句柄）。
enum SourceFontRegistry {
    private static let lock = NSLock()
    private nonisolated(unsafe) static var fonts: [Int: SourceFont] = [:]
    private nonisolated(unsafe) static var nextID = 1
    private nonisolated(unsafe) static var byDigest: [String: Int] = [:]

    static func register(data: Data) -> Int? {
        guard let font = SourceFont(data: data) else { return nil }
        let digest = sha256(data)
        lock.lock(); defer { lock.unlock() }
        if let existing = byDigest[digest], fonts[existing] != nil { return existing }
        let id = nextID
        nextID += 1
        fonts[id] = font
        byDigest[digest] = id
        if fonts.count > 16, let oldest = fonts.keys.min() {
            fonts.removeValue(forKey: oldest)
            byDigest = byDigest.filter { $0.value != oldest }
        }
        return id
    }

    static func font(_ id: Int) -> SourceFont? {
        lock.lock(); defer { lock.unlock() }
        return fonts[id]
    }

    static func sha256(_ data: Data) -> String {
        var digest = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
        data.withUnsafeBytes { _ = CC_SHA256($0.baseAddress, CC_LONG(data.count), &digest) }
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}

/// 原版 `replaceFont`：用错误字体的轮廓数据去正确字体里反查 Unicode。
enum FontDeobfuscation {
    static func replace(text: String, error: SourceFont, correct: SourceFont, filter: Bool) -> String {
        var out = String()
        out.reserveCapacity(text.count)
        for scalar in text.unicodeScalars {
            let code = Int(scalar.value)
            if error.isBlankUnicode(code) {
                out.unicodeScalars.append(scalar)
                continue
            }
            let glyph = error.glyphHex(for: code)
            if glyph == nil && filter { continue }
            var mapped = 0
            if let glyph { mapped = correct.unicode(forGlyph: glyph) }
            if mapped != 0, let s = UnicodeScalar(mapped) {
                out.unicodeScalars.append(s)
            } else {
                out.unicodeScalars.append(scalar)
            }
        }
        return out
    }
}
