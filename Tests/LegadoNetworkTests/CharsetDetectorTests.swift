//
//  CharsetDetectorTests.swift
//  LegadoNetworkTests
//
//  第 6 步 6B：字符集检测器（CharsetDetector）与响应解码链（TextDecoder /
//  EncodingDetect / StrResponse.decodeText）的独立单元测试。
//
//  测试数据均为合成字节串（与 golden 用例同源规则），预期值与 JDK 11 行为一致：
//   - 检测器：icu4j 移植（CharsetDetector.detect）；
//   - 解码：JDK 11 sun.nio.cs 各 Decoder 的 U+FFFD 替换语义（TextDecoder）。
//

import XCTest
@testable import LegadoBookSource

final class CharsetDetectorTests: XCTestCase {

    private func bytes(_ hex: String) -> [UInt8] {
        var result: [UInt8] = []
        var i = hex.startIndex
        while i < hex.endIndex {
            let next = hex.index(i, offsetBy: 2, limitedBy: hex.endIndex) ?? hex.endIndex
            if let v = UInt8(hex[i..<next], radix: 16) {
                result.append(v)
            }
            i = next
        }
        return result
    }

    // MARK: - 检测器（CharsetDetector.detect）

    func testDetectPureASCII() {
        let data = Array("The quick brown fox jumps over the lazy dog.".utf8)
        XCTAssertEqual(CharsetDetector.detect(data), "UTF-8")
    }

    func testDetectUTF8WithBOM() {
        let data = Array("\u{FEFF}".utf8) + Array("中文测试".utf8)
        XCTAssertEqual(CharsetDetector.detect(data), "UTF-8")
    }

    func testDetectUTF8ChineseNoBOM() {
        let data = bytes("E4B8ADE69687E6B58BE8AF95") // 中文测试
        XCTAssertEqual(CharsetDetector.detect(data), "UTF-8")
    }

    func testDetectGBKText() {
        let data = bytes("C4E3BAC3CAC0BDE7") // 你好世界
        XCTAssertEqual(CharsetDetector.detect(data), "GB18030")
    }

    func testDetectBig5Text() {
        let data = bytes("A4A4A4E5B4FAB8D5") // 中文測試
        XCTAssertEqual(CharsetDetector.detect(data), "Big5")
    }

    func testDetectUTF16LEWithBOM() {
        let data = bytes("FFFE2D4E8765")
        XCTAssertEqual(CharsetDetector.detect(data), "UTF-16LE")
    }

    func testDetectUTF16BEWithBOM() {
        let data = bytes("FEFF4E2D6587")
        XCTAssertEqual(CharsetDetector.detect(data), "UTF-16BE")
    }

    func testDetectEmptyFallsBackToUTF8() {
        XCTAssertEqual(CharsetDetector.detect([]), "UTF-8")
    }

    func testDetectShortSingleByteFallsBackToUTF8() {
        XCTAssertEqual(CharsetDetector.detect([0x41]), "UTF-8")
    }

    func testDetectAllFirstMatchesDetect() {
        let data = bytes("C4E3BAC3CAC0BDE7")
        let all = CharsetDetector.detectAll(data)
        XCTAssertFalse(all.isEmpty)
        XCTAssertEqual(all.first, CharsetDetector.detect(data))
    }

    // MARK: - BOM 剥离

    func testRemoveUTF8BOMBytes() {
        let data = bytes("EFBBBF41") // BOM + 'A'
        XCTAssertEqual(EncodingDetect.removeUTF8BOM(data), [0x41])
    }

    func testRemoveUTF8BOMBytesNoBOMUntouched() {
        let data = bytes("FFFE41")
        XCTAssertEqual(EncodingDetect.removeUTF8BOM(data), data)
    }

    func testRemoveUTF8BOMString() {
        XCTAssertEqual(EncodingDetect.removeUTF8BOM("\u{FEFF}hello"), "hello")
    }

    // MARK: - decodeText（显式 → 头 → meta → 检测器）

    func testDecodeTextExplicitGBK() {
        let data = bytes("C4E3BAC3CAC0BDE7") // 你 好 世 界
        XCTAssertEqual(StrResponse.decodeText(bytes: data, explicitCharset: "GBK", contentTypeHeader: nil),
                       "你好世界")
    }

    func testDecodeTextExplicitAliasCaseInsensitive() {
        let data = bytes("C4E3BAC3CAC0BDE7")
        // Java Charset.forName("gBk") 同样大小写不敏感
        XCTAssertEqual(StrResponse.decodeText(bytes: data, explicitCharset: "gBk", contentTypeHeader: nil),
                       "你好世界")
    }

    func testDecodeTextExplicitWinsOverHeader() {
        let data = bytes("C4E3BAC3CAC0BDE7") // GBK 字节
        // 显式 UTF-8 优先：GBK 字节按 UTF-8 解码（含替换字符），不应得到“你好世界”
        let decoded = StrResponse.decodeText(bytes: data, explicitCharset: "UTF-8",
                                             contentTypeHeader: "text/html; charset=gbk")
        XCTAssertNotEqual(decoded, "你好世界")
        XCTAssertTrue(decoded.contains("\u{FFFD}"))
    }

    func testDecodeTextHeaderCharset() {
        let data = bytes("C4E3BAC3CAC0BDE7")
        XCTAssertEqual(StrResponse.decodeText(bytes: data, explicitCharset: nil,
                                              contentTypeHeader: "text/html; charset=gbk"),
                       "你好世界")
    }

    func testDecodeTextHeaderQuotedCharset() {
        let data = bytes("C4E3BAC3CAC0BDE7")
        XCTAssertEqual(StrResponse.decodeText(bytes: data, explicitCharset: nil,
                                              contentTypeHeader: "text/html; charset=\"gbk\""),
                       "你好世界")
    }

    func testDecodeTextUTF8BOMStrippedBeforeDecode() {
        let data = Array("\u{FEFF}".utf8) + Array("hello 世界".utf8)
        let decoded = StrResponse.decodeText(bytes: data, explicitCharset: "UTF-8", contentTypeHeader: nil)
        XCTAssertEqual(decoded, "hello 世界")
        XCTAssertFalse(decoded.hasPrefix("\u{FEFF}"))
    }

    func testDecodeTextGarbageFallsBackWithReplacement() {
        // 0xFF 在 UTF-8 非法 → U+FFFD；检测器对单字节 0xFF 无匹配 → "UTF-8" 兜底
        let decoded = StrResponse.decodeText(bytes: [0xFF], explicitCharset: nil, contentTypeHeader: nil)
        XCTAssertEqual(decoded, "\u{FFFD}")
    }

    // MARK: - getHtmlEncode / getCharsetFromMeta

    func testGetHtmlEncodeMetaCharsetAttr() {
        let html = "<!DOCTYPE html><html><head><meta charset=\"gbk\"></head><body><p>"
            + "中文</p></body></html>"
        let data = Array(html.utf8) // ASCII 骨架足够（charset 属性是 ASCII）
        XCTAssertEqual(EncodingDetect.getHtmlEncode(data), "gbk")
    }

    func testGetHtmlEncodeMetaHttpEquiv() {
        let html = "<html><head><meta http-equiv=\"Content-Type\" "
            + "content=\"text/html; charset=gb2312\"></head><body></body></html>"
        XCTAssertEqual(EncodingDetect.getHtmlEncode(Array(html.utf8)), "gb2312")
    }

    func testGetHtmlEncodeMetaCaseAndQuoteVariant() {
        let html = "<HTML><HEAD><META CHARSET='GBK'></HEAD><BODY></BODY></HTML>"
        XCTAssertEqual(EncodingDetect.getHtmlEncode(Array(html.utf8)), "GBK")
    }

    func testGetHtmlEncodeMetaUnquotedValue() {
        let html = "<html><head><meta charset=utf-8></head><body></body></html>"
        XCTAssertEqual(EncodingDetect.getHtmlEncode(Array(html.utf8)), "utf-8")
    }

    func testGetHtmlEncodeNoMetaFallsBackToDetector() {
        let data = bytes("C4E3BAC3CAC0BDE7") // GBK 字节，无 HTML
        XCTAssertEqual(EncodingDetect.getHtmlEncode(data), "GB18030")
    }

    func testGetHtmlEncodeContentNoSemicolon() {
        // Kotlin substringAfter(";") 缺省值 = 整串：content="GBK" 直接作为 charset 名
        let html = "<html><head><meta http-equiv=\"Content-Type\" content=\"GBK\">"
            + "</head><body></body></html>"
        XCTAssertEqual(EncodingDetect.getHtmlEncode(Array(html.utf8)), "GBK")
    }

    func testGetCharsetFromMetaDirect() {
        XCTAssertEqual(EncodingDetect.getCharsetFromMeta(
            "<head><meta charset=\"big5\"><meta charset=\"gbk\"></head>"), "big5")
        XCTAssertNil(EncodingDetect.getCharsetFromMeta("<html><body>no head</body></html>"))
    }

    // MARK: - TextDecoder（JDK 11 替换语义）

    func testTextDecoderUTF8Basic() {
        XCTAssertEqual(TextDecoder.decode(bytes("E4B8ADE69687"), charsetName: "UTF-8"), "中文")
    }

    func testTextDecoderUTF8MalformedReplacement() {
        // JDK 11: E2 28 A1 → U+FFFD '(' U+FFFD
        XCTAssertEqual(TextDecoder.decode([0xE2, 0x28, 0xA1], charsetName: "UTF-8"),
                       "\u{FFFD}(\u{FFFD}")
    }

    func testTextDecoderUTF8OverlongRejected() {
        // C0 AF 为过度编码（JDK 一律判非法）：两个 U+FFFD
        XCTAssertEqual(TextDecoder.decode([0xC0, 0xAF], charsetName: "UTF-8"),
                       "\u{FFFD}\u{FFFD}")
    }

    func testTextDecoderGBK() {
        XCTAssertEqual(TextDecoder.decode(bytes("C4E3BAC3CAC0BDE7"), charsetName: "GBK"), "你好世界")
    }

    func testTextDecoderGBKInvalidTrailRescan() {
        // 0x81 0x7F：0x7F 是单字节（DEL）→ malformed(1)：U+FFFD + DEL
        XCTAssertEqual(TextDecoder.decode([0x81, 0x7F], charsetName: "GBK"),
                       "\u{FFFD}\u{7F}")
    }

    func testTextDecoderGB2312() {
        XCTAssertEqual(TextDecoder.decode(bytes("D6D0BBAAC8CBC3F1B9B2BACDB9FA"), charsetName: "GB2312"),
                       "中华人民共和国")
    }

    func testTextDecoderGB18030TwoByte() {
        XCTAssertEqual(TextDecoder.decode(bytes("D6D0"), charsetName: "GB18030"), "中")
    }

    func testTextDecoderGB18030FourByte() {
        // U+20000（扩展 B 区，GB18030 四字节 95 32 82 36）
        XCTAssertEqual(TextDecoder.decode(bytes("95328236"), charsetName: "GB18030"),
                       String(UnicodeScalar(0x20000) ?? " "))
    }

    func testTextDecoderGB18030_2005Additions() {
        // A6F6-A6F8 在 GB18030-2005 / JDK 表中为希腊字母 χψω（Python codec 为 PUA，两者不同）
        XCTAssertEqual(TextDecoder.decode(bytes("A6F6A6F7A6F8"), charsetName: "GB18030"), "χψω")
    }

    func testTextDecoderBig5() {
        XCTAssertEqual(TextDecoder.decode(bytes("A4A4A4E5B4FAB8D5"), charsetName: "Big5"), "中文測試")
    }

    func testTextDecoderUTF16LEWithBOM() {
        // BOM 在 UTF-16LE 下解出 U+FEFF（UTF-8 BOM 剥离不影响 FF FE）
        XCTAssertEqual(TextDecoder.decode(bytes("FFFE2D4E8765"), charsetName: "UTF-16LE"),
                       "\u{FEFF}中文")
    }

    func testTextDecoderUTF16BEReversedBOMMalformed() {
        // JDK 11 规则：UTF-16BE 下 FF FE 解出 0xFFFE（反向 BOM）→ malformed(2) → U+FFFD
        XCTAssertEqual(TextDecoder.decode(bytes("FFFE"), charsetName: "UTF-16BE"), "\u{FFFD}")
    }

    func testTextDecoderUTF16LEUnpairedSurrogate() {
        // LE 高代理 D800 后跟非低代理 → malformed(4) → 一个 U+FFFD
        XCTAssertEqual(TextDecoder.decode(bytes("00D84100"), charsetName: "UTF-16LE"), "\u{FFFD}")
    }

    func testTextDecoderISO88591() {
        XCTAssertEqual(TextDecoder.decode(bytes("636166E9"), charsetName: "ISO-8859-1"), "café")
        // 0x80-0x9F 是 C1 控制符（原样映射）
        XCTAssertEqual(TextDecoder.decode([0x80, 0x9F], charsetName: "Latin1"),
                       "\u{80}\u{9F}")
    }

    func testTextDecoderWindows1252() {
        XCTAssertEqual(TextDecoder.decode(bytes("9371756F74656494"), charsetName: "windows-1252"),
                       "\u{201C}quoted\u{201D}")
        // 0x81 未定义 → U+FFFD
        XCTAssertEqual(TextDecoder.decode([0x81], charsetName: "cp1252"), "\u{FFFD}")
    }

    func testTextDecoderUnknownCharsetReturnsNil() {
        XCTAssertNil(TextDecoder.decode([0x41], charsetName: "not-a-charset"))
    }

    func testCanonicalCharsetAliases() {
        XCTAssertEqual(TextDecoder.canonicalCharsetName("utf8"), "UTF-8")
        XCTAssertEqual(TextDecoder.canonicalCharsetName("EUC-CN"), "GB2312")
        XCTAssertEqual(TextDecoder.canonicalCharsetName("latin1"), "ISO-8859-1")
        XCTAssertEqual(TextDecoder.canonicalCharsetName("cp1252"), "windows-1252")
        XCTAssertEqual(TextDecoder.canonicalCharsetName("gb18030-2000"), "GB18030")
        XCTAssertNil(TextDecoder.canonicalCharsetName("euc-kr"))
    }
}