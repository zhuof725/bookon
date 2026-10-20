import Foundation

/// 导入宽松解析 + 未知字段保留。
enum SourceImportRegression {
    static func run(_ check: (Bool, String) -> Void) throws {
        // 尾逗号 + 注释 + 单引号（Gson 宽松模式常见写法）
        let loose = """
        [
          // 第一条
          {'bookSourceName': '甲', 'bookSourceUrl': 'https://a.example', 'weight': 7, 'storageKind': 0, 'customField': {'x': 1},},
          /* 第二条 */
          {"bookSourceName": "乙", "bookSourceUrl": "https://b.example", "ruleSearch": {"bookList": ".book"}},
        ]
        """
        let outcome = try SourceImportParser.parse(loose)
        check(outcome.report.imported == 2 && outcome.report.failed == 0, "宽松导入：尾逗号/注释/单引号")
        check(outcome.sources.first?.bookSourceName == "甲", "宽松导入：单引号字段")
        check(outcome.sources.first?.weight == 7, "宽松导入：weight 建模")
        check(outcome.sources.first?.storageKind == 0, "宽松导入：storageKind 建模")

        // 一条坏数据不影响其余
        let mixed = """
        [
          {"bookSourceName":"好","bookSourceUrl":"https://good.example"},
          {"bookSourceName":"坏", "bookSourceUrl": },
          {"bookSourceName":"也好","bookSourceUrl":"https://good2.example"}
        ]
        """
        let mixedOutcome = try SourceImportParser.parse(mixed)
        check(mixedOutcome.report.imported == 2, "坏数据：其余书源仍导入")
        check(mixedOutcome.report.failed == 1, "坏数据：失败数 1")
        check(mixedOutcome.report.summary.contains("成功 2 条、失败 1 条"), "坏数据：提示成功/失败条数")

        // 单对象 + JSONL
        let single = try SourceImportParser.parse(#"{"bookSourceName":"单","bookSourceUrl":"https://one.example"}"#)
        check(single.report.imported == 1, "单对象导入")
        let lines = """
        {"bookSourceName":"行1","bookSourceUrl":"https://l1.example"}
        {"bookSourceName":"行2","bookSourceUrl":"https://l2.example"}
        """
        check(try SourceImportParser.parse(lines).report.imported == 2, "JSONL 导入")

        // 未知字段 round-trip
        let json = """
        {"bookSourceUrl":"https://round.example","bookSourceName":"往返",
         "weight":3,"storageKind":0,"ruleReview":{"reviewUrl":"/r","enabled":true},
         "someFutureField":"keep-me","nestedFuture":{"a":[1,2,3]}}
        """
        let decoded = try JSONDecoder().decode(BookSource.self, from: Data(json.utf8))
        check(decoded.unknownFields["someFutureField"]?.stringValue == "keep-me", "未知字段：导入保留")
        check(decoded.ruleReview?.reviewUrl == "/r", "段评规则：ruleReview 建模")
        let encoded = try JSONEncoder().encode(decoded)
        let object = try JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        check(object?["someFutureField"] as? String == "keep-me", "未知字段：导出写回")
        check((object?["nestedFuture"] as? [String: Any])?["a"] != nil, "未知字段：嵌套对象写回")
        check(object?["weight"] as? Int == 3, "weight：导出保留")
        check((object?["ruleReview"] as? [String: Any])?["reviewUrl"] as? String == "/r", "ruleReview：导出保留")
        let again = try JSONDecoder().decode(BookSource.self, from: encoded)
        check(again.unknownFields["someFutureField"]?.stringValue == "keep-me", "未知字段：再次导入仍在")
    }
}

/// JsExtensions 补齐：AES/DES、文件、HTML、章节号、字体、evalJS。
enum JSExtensionsRegression {
    static func run(_ check: (Bool, String) -> Void) throws {
        let source = BookSource(bookSourceUrl: "https://js-ext.example", bookSourceName: "扩展")
        let context = RuleContext(source: source)

        // AES/DES：16 字节 key、ECB/PKCS5Padding
        let plain = "legado-js"
        let key = "0123456789abcdef"
        let cipher = JSEngine.shared.evalString(
            "java.aesEncodeToBase64String('\(plain)','\(key)','AES/ECB/PKCS5Padding','')",
            context: context)
        check(cipher?.isEmpty == false, "aesEncodeToBase64String 有输出")
        let round = JSEngine.shared.evalString(
            "java.aesDecodeToString('\(cipher ?? "")','\(key)','AES/ECB/PKCS5Padding','')",
            context: context)
        check(round == plain, "aesDecodeToString 往返")
        let des = JSEngine.shared.evalString(
            "java.desDecodeToString(java.createSymmetricCrypto('DES/ECB/PKCS5Padding','12345678',null).encryptBase64('des-text'),'12345678','DES/ECB/PKCS5Padding','')",
            context: context)
        check(des == "des-text", "desDecodeToString")

        // evalJS / htmlFormat / toNumChapter
        check(JSEngine.shared.evalString("java.evalJS('1+2')", context: context) == "3", "java.evalJS")
        check(SourceJSUtilities.toNumChapter("第十二章 风起") == "第12章 风起", "toNumChapter 中文数字")
        check(SourceJSUtilities.toNumChapter("第两百章") == "第200章", "toNumChapter 百位")
        check(SourceJSUtilities.toNumChapter("第102章") == "第102章", "toNumChapter 阿拉伯数字")
        let html = SourceJSUtilities.htmlFormat(
            "<style>x{}</style><p>第一段</p><script>bad()</script>第二段<br><img src='/a.png'>",
            baseUrl: "https://img.example/book/1")
        check(html.contains("第一段") && html.contains("第二段"), "htmlFormat 保留正文")
        check(html.contains("<img src=\"https://img.example/a.png\">"), "htmlFormat 图片绝对化")
        check(!html.contains("bad()") && !html.contains("x{}"), "htmlFormat 去掉脚本/样式")

        // importScript / cacheFile / readTxtFile：用本地文件（不联网）
        let dir = JavaBridge.scriptCacheDirectory
        let file = dir.appendingPathComponent("js-ext-\(UUID().uuidString).js")
        try "var fromFile = 42;".write(to: file, atomically: true, encoding: .utf8)
        check(JSEngine.shared.evalString("java.importScript('\(file.lastPathComponent)')", context: context) == "var fromFile = 42;",
              "importScript 读取本地脚本")
        check(JSEngine.shared.evalString("java.readTxtFile('\(file.lastPathComponent)')", context: context) == "var fromFile = 42;",
              "readTxtFile")
        try? FileManager.default.removeItem(at: file)

        // 字体：构造两个 cmap 不同、glyf 相同的 TTF
        let fontA = MiniTTF.make(unicode: 0x41)   // 'A' -> gid 1
        let fontB = MiniTTF.make(unicode: 0x42)   // 'B' -> gid 1
        check(SourceFont(data: fontA)?.glyphID(for: 0x41) == 1, "queryTTF：cmap 解析")
        check(SourceFont(data: fontA)?.unicode(forGlyph: MiniTTF.glyphHex) == 0x41, "queryTTF：轮廓反查")
        let idA = SourceFontRegistry.register(data: fontA) ?? 0
        let idB = SourceFontRegistry.register(data: fontB) ?? 0
        check(idA > 0 && idB > 0, "queryTTF：字体句柄")
        let replaced = JSEngine.shared.evalString(
            "var a=java.queryTTF('hex:\(fontA.map { String(format: "%02x", $0) }.joined())');" +
            "var b=java.queryTTF('hex:\(fontB.map { String(format: "%02x", $0) }.joined())');" +
            "java.replaceFont('A',a,b)", context: context)
        check(replaced == "B", "replaceFont：轮廓相同则映射到正确字体")
    }
}

/// 最小 TTF：只含 head/maxp/loca/glyf/cmap，足够验证 queryTTF 的解析路径。
enum MiniTTF {
    static let glyphHex = "00010000000000000000"   // 10 字节假轮廓

    static func make(unicode: UInt16) -> Data {
        var head = Data(count: 54)
        head[0] = 0; head[1] = 1; head[2] = 0; head[3] = 0
        put16(&head, 18, 1000)       // unitsPerEm
        put16(&head, 50, 0)          // indexToLocFormat = short
        var maxp = Data(count: 6)
        put32(&maxp, 0, 0x00010000)
        put16(&maxp, 4, 2)           // numGlyphs
        var loca = Data(count: 6)
        put16(&loca, 0, 0)
        put16(&loca, 2, 0)
        put16(&loca, 4, 5)           // 10 / 2
        let glyf = Data([0x00, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00])
        var cmap = Data()
        append16(&cmap, 0); append16(&cmap, 1)
        append16(&cmap, 3); append16(&cmap, 1); append32(&cmap, 12)
        // format 4, 2 segments
        append16(&cmap, 4); append16(&cmap, 32); append16(&cmap, 0)
        append16(&cmap, 4); append16(&cmap, 4); append16(&cmap, 1); append16(&cmap, 0)
        append16(&cmap, unicode)     // endCode[0]
        append16(&cmap, 0xFFFF)      // endCode[1]
        append16(&cmap, 0)           // reservedPad
        append16(&cmap, unicode)     // startCode[0]
        append16(&cmap, 0xFFFF)      // startCode[1]
        append16(&cmap, 1 &- unicode) // idDelta[0] -> gid 1
        append16(&cmap, 1)           // idDelta[1]
        append16(&cmap, 0)           // idRangeOffset[0]
        append16(&cmap, 0)           // idRangeOffset[1]

        let tables: [(String, Data)] = [("cmap", cmap), ("glyf", glyf), ("head", head),
                                        ("loca", loca), ("maxp", maxp)]
        var output = Data()
        append32(&output, 0x00010000)
        append16(&output, UInt16(tables.count))
        append16(&output, 0); append16(&output, 0); append16(&output, 0)
        var offset = 12 + tables.count * 16
        var directory = Data()
        var body = Data()
        for (tag, table) in tables {
            directory.append(tag.data(using: .ascii)!)
            append32(&directory, 0)
            append32(&directory, UInt32(offset))
            append32(&directory, UInt32(table.count))
            body.append(table)
            let pad = (4 - table.count % 4) % 4
            if pad > 0 { body.append(Data(count: pad)) }
            offset += table.count + pad
        }
        output.append(directory)
        output.append(body)
        return output
    }

    private static func append16(_ data: inout Data, _ value: UInt16) {
        data.append(UInt8(value >> 8)); data.append(UInt8(value & 0xFF))
    }
    private static func append32(_ data: inout Data, _ value: UInt32) {
        data.append(UInt8((value >> 24) & 0xFF)); data.append(UInt8((value >> 16) & 0xFF))
        data.append(UInt8((value >> 8) & 0xFF)); data.append(UInt8(value & 0xFF))
    }
    private static func put16(_ data: inout Data, _ offset: Int, _ value: UInt16) {
        data[offset] = UInt8(value >> 8); data[offset + 1] = UInt8(value & 0xFF)
    }
    private static func put32(_ data: inout Data, _ offset: Int, _ value: UInt32) {
        data[offset] = UInt8((value >> 24) & 0xFF); data[offset + 1] = UInt8((value >> 16) & 0xFF)
        data[offset + 2] = UInt8((value >> 8) & 0xFF); data[offset + 3] = UInt8(value & 0xFF)
    }
}
