//
//  TextDecoder.swift
//  LegadoBookSource
//
//  第 6 步 6B：响应字节 → Swift String 的解码器（JDK 11 各 Charset Decoder 的逐规则移植）。
//
//  对应 Java/Kotlin 位置：
//   - java.nio.charset.Charset.forName(name)（golden 侧真实 JDK 11 temurin）
//   - sun/nio/cs/UTF_8.java（decodeArrayLoop / malformedN）
//   - sun/nio/cs/UnicodeDecoder.java（UTF-16LE/BE，含 JDK 11 的 0xFFFE 反向 BOM 否决规则）
//   - sun/nio/cs/GB18030.java（Decoder 状态机 + decodeDouble/getChar）
//   - sun/nio/cs/DoubleByte.java（Decoder.decodeLoop + crMalformedOrUnmappable；GBK/GB2312/Big5）
//   - sun/nio/cs/ISO_8859_1.java / MS1252.java（单字节直查）
//
//  语义要点：
//   - 所有解码器都按 Java `new String(bytes, charset)` 的 REPLACE 语义输出 U+FFFD；
//   - 映射表（TextDecodeTables）由 scripts/golden/gen_jdk_tables.py 从 jdk11u
//     （jdk-11.0.24+8）源码/映射文件生成，与 CI golden 的 temurin JDK 11 逐字一致；
//   - charset 名解析覆盖书源常用 9 个字符集及其 JDK 别名（子集，见 canonicalCharsetName）。
//
//  差异：JDK 对未知 charset 名抛 UnsupportedCharsetException；这里返回 nil，
//  由调用方（StrResponse.decodeText）回退到下一级探测（见 StrResponse 注释）。
//

import Foundation

/// 文本解码器：charset 名 → 字节 → String（U+FFFD 替换语义）。
enum TextDecoder {

    /// 按 charset 名解码字节（nil = 未知 charset 名）。
    ///
    /// 对应 Java `new String(bytes, Charset.forName(charsetName))`。
    static func decode(_ bytes: [UInt8], charsetName: String) -> String? {
        guard let canonical = canonicalCharsetName(charsetName) else {
            return nil
        }
        switch canonical {
        case "UTF-8":
            return decodeUTF8(bytes)
        case "GBK":
            return decodeDoubleByte(bytes, single: TextDecodeTables.gbkSingle,
                                    leadMask: TextDecodeTables.gbkLead,
                                    flat: TextDecodeTables.gbkDouble,
                                    b1Min: 0x81, b1Max: 0xFE, b2Min: 0x40, b2Max: 0xFE)
        case "GB2312":
            return decodeDoubleByte(bytes, single: TextDecodeTables.gb2312Single,
                                    leadMask: TextDecodeTables.gb2312Lead,
                                    flat: TextDecodeTables.gb2312Double,
                                    b1Min: 0xA1, b1Max: 0xF7, b2Min: 0xA1, b2Max: 0xFE)
        case "Big5":
            return decodeDoubleByte(bytes, single: TextDecodeTables.big5Single,
                                    leadMask: TextDecodeTables.big5Lead,
                                    flat: TextDecodeTables.big5Double,
                                    b1Min: 0xA1, b1Max: 0xF9, b2Min: 0x40, b2Max: 0xFE)
        case "GB18030":
            return decodeGB18030(bytes)
        case "UTF-16LE":
            return decodeUTF16(bytes, littleEndian: true)
        case "UTF-16BE":
            return decodeUTF16(bytes, littleEndian: false)
        case "ISO-8859-1":
            return decodeSingleIdentity(bytes)
        case "windows-1252":
            return decodeWindows1252(bytes)
        default:
            return nil
        }
    }

    /// charset 名 → 规范名（对应 Java 别名表子集；大小写不敏感、忽略 -/_/: 分隔符）。
    ///
    /// 对应 Java：
    ///  - sun/nio/cs/StandardCharsets.java.template（标准 charset 别名）
    ///  - make/data/charsetmapping/charsets（GB2312=EUC_CN / Big5 / GBK / windows-1252 别名）
    ///  - GB18030.java 的 canonicalize（gb18030-2000 / gb18030-2022 运行时别名）
    /// 差异：仅收录书源常用 9 个字符集的别名（JDK 完整别名表超出 Swift 可维护范围；
    /// 未收录的名字返回 nil，调用方回退下一级探测）。
    static func canonicalCharsetName(_ name: String) -> String? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let key = trimmed.lowercased().filter { $0 != "-" && $0 != "_" && $0 != ":" && $0 != " " }
        switch key {
        case "utf8", "unicode11utf8":
            return "UTF-8"
        case "gbk", "cp936", "windows936":
            return "GBK"
        case "gb2312", "gb231280", "gb23121980", "euccn", "xeucn", "csgb2312", "chinese", "isoir58":
            return "GB2312"
        case "gb18030", "gb180302000", "gb180302022":
            return "GB18030"
        case "big5", "bigfive", "csbig5", "cnbig5", "xxbig5":
            return "Big5"
        case "utf16le", "unicodefffe", "unicodelittleunmarked":
            return "UTF-16LE"
        case "utf16be", "unicodefeff", "unicodebigunmarked":
            return "UTF-16BE"
        case "iso88591", "iso885911987", "latin1", "l1", "cp819", "ibm819", "isoir100", "csisolatin1":
            return "ISO-8859-1"
        case "windows1252", "cp1252", "cp5348", "ibm1252":
            return "windows-1252"
        default:
            return nil
        }
    }

    // MARK: - 工具

    /// 把码点数组拼成 String（非法码点按 U+FFFD 兜底，避免强制解包）。
    private static func buildString(_ scalars: [UInt32]) -> String {
        var result = ""
        result.reserveCapacity(scalars.count)
        for v in scalars {
            if let us = UnicodeScalar(v) {
                result.unicodeScalars.append(us)
            } else {
                // U+FFFD 为合法标量（防御分支，现实不会走到）
                if let fffd = UnicodeScalar(0xFFFD) {
                    result.unicodeScalars.append(fffd)
                }
            }
        }
        return result
    }

    /// 安全标量：代理区/越界码点一律替换为 U+FFFD（JDK 解码器不会产出，防御用）。
    private static func safeScalar(_ v: Int) -> UInt32 {
        if v >= 0 && v <= 0x10FFFF && !(v >= 0xD800 && v <= 0xDFFF) {
            return UInt32(v)
        }
        return 0xFFFD
    }

    // MARK: - UTF-8（JDK 11 sun.nio.cs.UTF_8 + REPLACE）

    /// 对应 Java `charset("UTF-8")` 的 String(byte[], utf8) 语义。
    ///
    /// 规则逐条对应 JDK 11 decodeArrayLoop / malformedN：
    ///  - 2 字节 C2-DF：第二字节非续字节 → malformed(1)；
    ///  - 3 字节 E0-EF：E0 的第二字节须 A0-BF；ED 不得编代理（结果是代理 → malformed(3)）；
    ///    完整 3 字节可用时 malformedN 给 1 或 2 的长度；
    ///  - 4 字节 F0-F4：F0 第二字节须 90-BF、F4 须 80-8F；码点须在 0x10000-0x10FFFF
    ///    （最短形式检查）；malformedN 给 1/2/3 的长度；
    ///  - 输入结尾的不完整序列：整个剩余段按一个 U+FFFD 消费（CharsetDecoder
    ///    end-of-input malformedForLength(in.remaining())）。
    static func decodeUTF8(_ bytes: [UInt8]) -> String {
        var out: [UInt32] = []
        var i = 0
        let n = bytes.count
        while i < n {
            let b1 = Int(bytes[i])
            if b1 <= 0x7F {
                out.append(UInt32(b1))
                i += 1
                continue
            }
            if b1 >= 0xC2 && b1 <= 0xDF {
                if i + 1 >= n || (bytes[i + 1] & 0xC0) != 0x80 {
                    out.append(0xFFFD)
                    i += 1
                    continue
                }
                out.append(UInt32(((b1 & 0x1F) << 6) | (Int(bytes[i + 1]) & 0x3F)))
                i += 2
                continue
            }
            if b1 >= 0xE0 && b1 <= 0xEF {
                let rem = n - i
                if rem < 3 {
                    // JDK isMalformed3_2：E0 后 A0-BF 检查 + 续字节检查
                    if rem > 1 && ((b1 == 0xE0 && (bytes[i + 1] & 0xE0) == 0x80)
                        || (bytes[i + 1] & 0xC0) != 0x80) {
                        out.append(0xFFFD)
                        i += 1
                        continue
                    }
                    out.append(0xFFFD)
                    i += rem
                    continue
                }
                let b2 = Int(bytes[i + 1])
                let b3 = Int(bytes[i + 2])
                let malformed = (b1 == 0xE0 && (b2 & 0xE0) == 0x80)
                    || (b2 & 0xC0) != 0x80 || (b3 & 0xC0) != 0x80
                if malformed {
                    // malformedN(nb=3)：b2 违例（E0 下限或非续字节）→ 1，否则 2
                    let len = ((b1 == 0xE0 && (b2 & 0xE0) == 0x80) || (b2 & 0xC0) != 0x80) ? 1 : 2
                    out.append(0xFFFD)
                    i += len
                    continue
                }
                let c = ((b1 & 0x0F) << 12) | ((b2 & 0x3F) << 6) | (b3 & 0x3F)
                if c >= 0xD800 && c <= 0xDFFF {
                    // 编成代理（ED A0-BF …）→ malformedForLength(3)
                    out.append(0xFFFD)
                    i += 3
                    continue
                }
                out.append(UInt32(c))
                i += 3
                continue
            }
            if b1 >= 0xF0 && b1 <= 0xF4 {
                let rem = n - i
                if rem < 4 {
                    if rem > 1 && utf8Malformed4_2(b1, Int(bytes[i + 1])) {
                        out.append(0xFFFD)
                        i += 1
                        continue
                    }
                    if rem > 2 && (bytes[i + 2] & 0xC0) != 0x80 {
                        out.append(0xFFFD)
                        i += 2
                        continue
                    }
                    out.append(0xFFFD)
                    i += rem
                    continue
                }
                let b2 = Int(bytes[i + 1])
                let b3 = Int(bytes[i + 2])
                let b4 = Int(bytes[i + 3])
                let uc = ((b1 & 0x07) << 18) | ((b2 & 0x3F) << 12) | ((b3 & 0x3F) << 6) | (b4 & 0x3F)
                let malformed = (b2 & 0xC0) != 0x80 || (b3 & 0xC0) != 0x80
                    || (b4 & 0xC0) != 0x80 || uc < 0x10000 || uc > 0x10FFFF
                if malformed {
                    // malformedN(nb=4)：首二字节违例 → 1；第三字节违例 → 2；否则 3
                    var len = 1
                    if !((b1 > 0xF4)
                        || (b1 == 0xF0 && (b2 < 0x90 || b2 > 0xBF))
                        || (b1 == 0xF4 && (b2 & 0xF0) != 0x80)
                        || (b2 & 0xC0) != 0x80) {
                        len = (b3 & 0xC0) != 0x80 ? 2 : 3
                    }
                    out.append(0xFFFD)
                    i += len
                    continue
                }
                out.append(UInt32(uc))
                i += 4
                continue
            }
            // C0/C1、F5-FF、游离续字节 80-BF → malformed(1)
            out.append(0xFFFD)
            i += 1
        }
        return buildString(out)
    }

    /// JDK `isMalformed4_2`：4 字节序列只够前 2 字节时的违例判定。
    private static func utf8Malformed4_2(_ b1: Int, _ b2: Int) -> Bool {
        return (b1 == 0xF0 && (b2 < 0x90 || b2 > 0xBF))
            || (b1 == 0xF4 && (b2 & 0xF0) != 0x80)
            || (b2 & 0xC0) != 0x80
    }

    // MARK: - 双字节族（GBK / GB2312 / Big5，JDK DoubleByte.Decoder）

    /// 对应 Java `DoubleByte.Decoder.decodeLoop` + crMalformedOrUnmappable 的 REPLACE 语义。
    ///
    /// 规则（与 JDK 逐条对应）：
    ///  - b2cSB 命中的单字节直接输出（本族单字节区均为 0x00-0x7F）；
    ///  - 非单字节时取第二字节：越出 [b2Min, b2Max] 或映射为 U+FFFD 时走
    ///    crMalformedOrUnmappable：b1 非 lead / b2 是 lead / b2 是单字节 → malformed(1)（只吃 b1，
    ///    然后重扫 b2）；否则 unmappable(2)（b1+b2 一起换成 U+FFFD）；
    ///  - 结尾只剩 1 字节 → malformed(1)。
    static func decodeDoubleByte(_ bytes: [UInt8], single: [UInt16], leadMask: [UInt16],
                                 flat: [UInt16], b1Min: Int, b1Max: Int,
                                 b2Min: Int, b2Max: Int) -> String {
        var out: [UInt32] = []
        var i = 0
        let n = bytes.count
        let stride = b2Max - b2Min + 1
        while i < n {
            let b1 = Int(bytes[i])
            if Int(single[b1]) != 0xFFFD {
                out.append(UInt32(single[b1]))
                i += 1
                continue
            }
            if i + 1 >= n {
                out.append(0xFFFD)
                i += 1
                continue
            }
            let b2 = Int(bytes[i + 1])
            let b1IsLead = b1 >= b1Min && b1 <= b1Max && leadMask[b1 - b1Min] == 1
            var c: Int = 0xFFFD
            if b1IsLead && b2 >= b2Min && b2 <= b2Max {
                c = Int(flat[(b1 - b1Min) * stride + (b2 - b2Min)])
            }
            if c != 0xFFFD {
                out.append(UInt32(c))
                i += 2
                continue
            }
            // crMalformedOrUnmappable(b1, b2)
            let b2IsLead = b2 >= b1Min && b2 <= b1Max && leadMask[b2 - b1Min] == 1
            let b2IsSingle = Int(single[b2]) != 0xFFFD
            if !b1IsLead || b2IsLead || b2IsSingle {
                out.append(0xFFFD)
                i += 1
            } else {
                out.append(0xFFFD)
                i += 2
            }
        }
        return buildString(out)
    }

    // MARK: - GB18030（JDK 11 sun.nio.cs.GB18030.Decoder 状态机）

    /// 对应 Java `GB18030.Decoder` 的 REPLACE 语义：
    ///  - 单字节：0x00-0x7F；
    ///  - 双字节：0x81-0xFE + 0x40-0x7E/0x80-0xFE（decodeDouble 查 index1/index2 展平表）；
    ///  - 四字节：0x81-0xFE + 0x30-0x39 + 0x81-0xFE + 0x30-0x39，offset 公式后
    ///    按 getChar（decoderIndex 展平表）与三段线性偏移计算；
    ///  - 4 字节区 BMP 外（offset 0x2E248..0x12E247）按 offset - 0x1E248 直接得到码点；
    ///  - 各违例分支的消费长度与 JDK 一致（1/2/3/4 或结尾剩余段整体一个 U+FFFD）。
    static func decodeGB18030(_ bytes: [UInt8]) -> String {
        var out: [UInt32] = []
        var i = 0
        let n = bytes.count
        while i < n {
            let b1 = Int(bytes[i])
            if b1 & 0x80 == 0 {
                out.append(UInt32(b1))
                i += 1
                continue
            }
            if b1 < 0x81 || b1 > 0xFE {
                out.append(0xFFFD)
                i += 1
                continue
            }
            if i + 1 >= n {
                // 结尾只剩 lead → malformed(1)
                out.append(0xFFFD)
                i += 1
                continue
            }
            let b2 = Int(bytes[i + 1])
            if b2 < 0x30 {
                out.append(0xFFFD)
                i += 1
                continue
            }
            if b2 >= 0x30 && b2 <= 0x39 {
                // 四字节
                if i + 3 >= n {
                    // 结尾不足 4 字节 → 剩余段整体一个 U+FFFD（end-of-input 语义）
                    out.append(0xFFFD)
                    break
                }
                let b3 = Int(bytes[i + 2])
                let b4 = Int(bytes[i + 3])
                if b3 < 0x81 || b3 > 0xFE {
                    out.append(0xFFFD)
                    i += 3
                    continue
                }
                if b4 < 0x30 || b4 > 0x39 {
                    out.append(0xFFFD)
                    i += 4
                    continue
                }
                let offset = (((b1 - 0x81) * 10 + (b2 - 0x30)) * 126 + b3 - 0x81) * 10 + b4 - 0x30
                var v = 0xFFFD
                if offset <= 0x4A62 {
                    v = Int(TextDecodeTables.gb18030FourBmp[offset])
                } else if offset <= 0x82BC {
                    // IS_2000 属性默认 false：0x4A71-0x4A78 走 getChar，其余 +0x5543
                    if offset >= 0x4A71 && offset <= 0x4A78 {
                        v = Int(TextDecodeTables.gb18030FourBmp[offset])
                    } else {
                        v = offset + 0x5543
                    }
                } else if offset <= 0x830D {
                    v = Int(TextDecodeTables.gb18030FourBmp[offset])
                } else if offset <= 0x93A8 {
                    v = offset + 0x6557
                } else if offset <= 0x99FB {
                    v = Int(TextDecodeTables.gb18030FourBmp[offset])
                } else if offset >= 0x2E248 && offset < 0x12E248 {
                    v = offset - 0x1E248
                }
                out.append(safeScalar(v))
                i += 4
                continue
            }
            if b2 == 0x7F || b2 == 0xFF || b2 < 0x40 {
                out.append(0xFFFD)
                i += 2
                continue
            }
            // 双字节
            out.append(safeScalar(Int(TextDecodeTables.gb18030Double[(b1 - 0x81) * 191 + (b2 - 0x40)])))
            i += 2
        }
        return buildString(out)
    }

    // MARK: - UTF-16LE/BE（JDK 11 UnicodeDecoder + JDK 11 的 0xFFFE 否决规则）

    /// 对应 Java `String(bytes, "UTF-16LE"/"UTF-16BE")`（JDK 11 UnicodeDecoder）：
    ///  - 高代理须紧跟低代理，否则 4 字节整体一个 U+FFFD；
    ///  - 孤立低代理 → malformed(2)；结尾不完整序列 → 剩余段整体一个 U+FFFD；
    ///  - 0xFFFE（反向 BOM）→ malformed(2)（JDK 11 特有；JDK 17 已删除该规则——golden 用 JDK 11）。
    static func decodeUTF16(_ bytes: [UInt8], littleEndian: Bool) -> String {
        var out: [UInt32] = []
        var i = 0
        let n = bytes.count
        while i + 1 < n {
            let b1 = Int(bytes[i])
            let b2 = Int(bytes[i + 1])
            let c = littleEndian ? ((b2 << 8) | b1) : ((b1 << 8) | b2)
            if c == 0xFFFE {
                out.append(0xFFFD)
                i += 2
                continue
            }
            if c >= 0xD800 && c <= 0xDBFF {
                if i + 4 > n {
                    // 结尾不完整代理对：整段剩余一个 U+FFFD
                    out.append(0xFFFD)
                    break
                }
                let b3 = Int(bytes[i + 2])
                let b4 = Int(bytes[i + 3])
                let c2 = littleEndian ? ((b4 << 8) | b3) : ((b3 << 8) | b4)
                if !(c2 >= 0xDC00 && c2 <= 0xDFFF) {
                    out.append(0xFFFD)
                    i += 4
                    continue
                }
                out.append(UInt32(0x10000 + ((c - 0xD800) << 10) + (c2 - 0xDC00)))
                i += 4
                continue
            }
            if c >= 0xDC00 && c <= 0xDFFF {
                out.append(0xFFFD)
                i += 2
                continue
            }
            out.append(UInt32(c))
            i += 2
        }
        if i < n {
            out.append(0xFFFD)
        }
        return buildString(out)
    }

    // MARK: - 单字节（ISO-8859-1 / windows-1252）

    /// ISO-8859-1：字节值即码点（JDK sun.nio.cs.ISO_8859_1，恒为有效映射）。
    static func decodeSingleIdentity(_ bytes: [UInt8]) -> String {
        var out: [UInt32] = []
        out.reserveCapacity(bytes.count)
        for b in bytes {
            out.append(UInt32(b))
        }
        return buildString(out)
    }

    /// windows-1252：JDK MS1252 表（0x81/0x8D/0x8F/0x90/0x9D → U+FFFD）。
    static func decodeWindows1252(_ bytes: [UInt8]) -> String {
        var out: [UInt32] = []
        out.reserveCapacity(bytes.count)
        for b in bytes {
            out.append(UInt32(TextDecodeTables.windows1252[Int(b)]))
        }
        return buildString(out)
    }
}