import Foundation
import CommonCrypto
import CryptoKit
import JavaScriptCore

enum Crypto {
    static func md5(_ s: String) -> String {
        let d = Insecure.MD5.hash(data: Data(s.utf8))
        return d.map { String(format: "%02x", $0) }.joined()
    }

    private static func digest(_ alg: String, _ data: Data) -> Data {
        switch alg.uppercased().replacingOccurrences(of: "-", with: "") {
        case "MD5": return Data(Insecure.MD5.hash(data: data))
        case "SHA1": return Data(Insecure.SHA1.hash(data: data))
        case "SHA384": return Data(SHA384.hash(data: data))
        case "SHA512": return Data(SHA512.hash(data: data))
        default: return Data(SHA256.hash(data: data))
        }
    }
    static func digestHex(_ alg: String, _ s: String) -> String { digest(alg, Data(s.utf8)).hex }
    static func digestBase64(_ alg: String, _ s: String) -> String { digest(alg, Data(s.utf8)).base64EncodedString() }

    private static func hmac(_ alg: String, key: String, _ s: String) -> Data {
        let k = SymmetricKey(data: Data(key.utf8)); let d = Data(s.utf8)
        switch alg.uppercased().replacingOccurrences(of: "-", with: "").replacingOccurrences(of: "HMAC", with: "") {
        case "MD5": return Data(HMAC<Insecure.MD5>.authenticationCode(for: d, using: k))
        case "SHA1": return Data(HMAC<Insecure.SHA1>.authenticationCode(for: d, using: k))
        case "SHA384": return Data(HMAC<SHA384>.authenticationCode(for: d, using: k))
        case "SHA512": return Data(HMAC<SHA512>.authenticationCode(for: d, using: k))
        default: return Data(HMAC<SHA256>.authenticationCode(for: d, using: k))
        }
    }
    static func hmacHex(_ alg: String, key: String, _ s: String) -> String { hmac(alg, key: key, s).hex }
    static func hmacBase64(_ alg: String, key: String, _ s: String) -> String { hmac(alg, key: key, s).base64EncodedString() }

    /// AES / DES / 3DES，mode 形如 "AES/CBC/PKCS5Padding" 或 "CBC"
    static func aes(_ data: Data, key: String, iv: String, mode: String, encrypt: Bool) -> Data? {
        cc(data, key: Data(key.utf8), iv: Data(iv.utf8), transformation: mode.contains("/") ? mode : "AES/\(mode)/PKCS5Padding", encrypt: encrypt)
    }

    static func cc(_ data: Data, key: Data, iv: Data, transformation: String, encrypt: Bool) -> Data? {
        let parts = transformation.uppercased().components(separatedBy: "/")
        let algName = parts.first ?? "AES"
        let mode = parts.count > 1 ? parts[1] : "CBC"
        let padding = parts.count > 2 ? parts[2] : "PKCS5PADDING"
        var alg: CCAlgorithm; var blockSize: Int
        switch algName {
        case "DES": alg = CCAlgorithm(kCCAlgorithmDES); blockSize = kCCBlockSizeDES
        case "DESEDE", "3DES", "TRIPLEDES": alg = CCAlgorithm(kCCAlgorithm3DES); blockSize = kCCBlockSize3DES
        default: alg = CCAlgorithm(kCCAlgorithmAES); blockSize = kCCBlockSizeAES128
        }
        var options: CCOptions = 0
        if padding.contains("PKCS") { options |= CCOptions(kCCOptionPKCS7Padding) }
        if mode == "ECB" { options |= CCOptions(kCCOptionECBMode) }
        var ivData = iv
        if ivData.count < blockSize { ivData.append(Data(repeating: 0, count: blockSize - ivData.count)) }
        let out = UnsafeMutablePointer<UInt8>.allocate(capacity: data.count + blockSize)
        defer { out.deallocate() }
        var moved = 0
        let status = key.withUnsafeBytes { kp in
            ivData.withUnsafeBytes { ip in
                data.withUnsafeBytes { dp in
                    CCCrypt(CCOperation(encrypt ? kCCEncrypt : kCCDecrypt), alg, options,
                            kp.baseAddress, key.count, ip.baseAddress, dp.baseAddress, data.count,
                            out, data.count + blockSize, &moved)
                }
            }
        }
        guard status == kCCSuccess else { return nil }
        return Data(bytes: out, count: moved)
    }

    /// java.createSymmetricCrypto(transformation, key, iv) → 对象 { decrypt, decryptStr, encrypt, encryptBase64, encryptHex }
    static func symmetricObject(_ ctx: JSContext, _ transformation: String, _ key: JSValue, _ iv: JSValue) -> JSValue {
        func bytes(_ v: JSValue) -> Data {
            if v.isUndefined || v.isNull { return Data() }
            if v.isString { return Data((v.toString() ?? "").utf8) }
            if let arr = v.toArray() as? [NSNumber] { return Data(arr.map { UInt8(truncatingIfNeeded: $0.intValue) }) }
            return Data((v.toString() ?? "").utf8)
        }
        let k = bytes(key), i = bytes(iv)
        let o = JSValue(newObjectIn: ctx)!
        func input(_ v: JSValue) -> Data {
            if v.isString {
                let s = v.toString() ?? ""
                if let d = Data(base64Encoded: s, options: .ignoreUnknownCharacters), !d.isEmpty { return d }
                return Encodings.hexToData(s)
            }
            return bytes(v)
        }
        let decryptStr: @convention(block) (JSValue) -> String = { v in
            cc(input(v), key: k, iv: i, transformation: transformation, encrypt: false).flatMap { String(data: $0, encoding: .utf8) } ?? ""
        }
        let decrypt: @convention(block) (JSValue) -> [UInt8] = { v in
            cc(input(v), key: k, iv: i, transformation: transformation, encrypt: false).map { [UInt8]($0) } ?? []
        }
        let encryptBase64: @convention(block) (JSValue) -> String = { v in
            cc(bytes(v), key: k, iv: i, transformation: transformation, encrypt: true)?.base64EncodedString() ?? ""
        }
        let encryptHex: @convention(block) (JSValue) -> String = { v in
            cc(bytes(v), key: k, iv: i, transformation: transformation, encrypt: true)?.hex ?? ""
        }
        let encrypt: @convention(block) (JSValue) -> [UInt8] = { v in
            cc(bytes(v), key: k, iv: i, transformation: transformation, encrypt: true).map { [UInt8]($0) } ?? []
        }
        o.setObject(decryptStr, forKeyedSubscript: "decryptStr" as NSString)
        o.setObject(decrypt, forKeyedSubscript: "decrypt" as NSString)
        o.setObject(encryptBase64, forKeyedSubscript: "encryptBase64" as NSString)
        o.setObject(encryptHex, forKeyedSubscript: "encryptHex" as NSString)
        o.setObject(encrypt, forKeyedSubscript: "encrypt" as NSString)
        return o
    }
}

extension Data {
    var hex: String { map { String(format: "%02x", $0) }.joined() }
}

enum Encodings {
    static func nsEncoding(_ charset: String?) -> String.Encoding {
        guard let c = charset?.lowercased().replacingOccurrences(of: "-", with: "").replacingOccurrences(of: "_", with: "") else { return .utf8 }
        switch c {
        case "gbk", "gb2312", "gb18030", "cp936", "ms936":
            return String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue)))
        case "big5", "big5hkscs":
            return String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.big5.rawValue)))
        case "utf16": return .utf16
        case "iso88591", "latin1": return .isoLatin1
        default: return .utf8
        }
    }
    static func encode(_ s: String, charset: String?) -> Data { s.data(using: nsEncoding(charset)) ?? Data(s.utf8) }
    static func decode(_ d: Data, charset: String?) -> String { String(data: d, encoding: nsEncoding(charset)) ?? String(decoding: d, as: UTF8.self) }
    static func percentEncodeGBK(_ s: String) -> String {
        encode(s, charset: "gbk").map { b -> String in
            let c = Character(UnicodeScalar(b))
            if b < 128, c.isLetter || c.isNumber || "-_.*".contains(c) { return String(c) }
            return String(format: "%%%02X", b)
        }.joined()
    }
    static func hexToData(_ s: String) -> Data {
        var d = Data(); var chars = Array(s.filter { !$0.isWhitespace })
        if chars.count % 2 == 1 { chars.insert("0", at: 0) }
        var i = 0
        while i + 1 < chars.count {
            if let b = UInt8(String(chars[i...i+1]), radix: 16) { d.append(b) }
            i += 2
        }
        return d
    }
}

/// 中文数字章节转换（java.toNumChapter）
enum ChineseNumber {
    static func convertChapter(_ s: String) -> String {
        guard let re = try? NSRegularExpression(pattern: #"(第)([零〇一二两三四五六七八九十百千万壹贰叁肆伍陆柒捌玖拾佰仟]+)([章节回集卷部篇])"#) else { return s }
        let ns = s as NSString
        var out = s
        for m in re.matches(in: s, range: NSRange(location: 0, length: ns.length)).reversed() {
            let num = ns.substring(with: m.range(at: 2))
            let r = Range(m.range, in: out)!
            out.replaceSubrange(r, with: "第\(toInt(num))\(ns.substring(with: m.range(at: 3)))")
        }
        return out
    }
    static func toInt(_ s: String) -> Int {
        let digits: [Character: Int] = ["零":0,"〇":0,"一":1,"二":2,"两":2,"三":3,"四":4,"五":5,"六":6,"七":7,"八":8,"九":9,
                                        "壹":1,"贰":2,"叁":3,"肆":4,"伍":5,"陆":6,"柒":7,"捌":8,"玖":9]
        let units: [Character: Int] = ["十":10,"拾":10,"百":100,"佰":100,"千":1000,"仟":1000,"万":10000]
        var total = 0, section = 0, num = 0
        for c in s {
            if let d = digits[c] { num = d }
            else if let u = units[c] {
                if u == 10000 { section = (section + (num == 0 ? 0 : num)) * u; total += section; section = 0 }
                else { section += (num == 0 ? 1 : num) * u }
                num = 0
            }
        }
        return total + section + num
    }
}
