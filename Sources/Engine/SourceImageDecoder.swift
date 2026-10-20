import Foundation

/// 书源 coverDecodeJs：原版在图片下载后执行脚本，`result` 是图片字节（有符号 int 数组），
/// 脚本返回解密后的字节。解密失败时保留原图，避免整本书没有封面。
enum SourceImageDecoder {
    static func decode(_ data: Data, src: String, source: BookSource?) -> Data {
        guard let source,
              let script = source.coverDecodeJs?.trimmingCharacters(in: .whitespacesAndNewlines),
              !script.isEmpty else { return data }
        let value = JSEngine.shared.eval(script, result: SourceCrypto.toSigned(data),
                                         baseUrl: src, vars: ["src": src],
                                         context: RuleContext(source: source))
        guard let decoded = bytes(from: value), !decoded.isEmpty else {
            if let error = JSEngine.lastError {
                DebugLog.add("◇coverDecodeJs 执行失败：\(error)")
            } else {
                DebugLog.add("◇coverDecodeJs 未返回字节，保留原图")
            }
            return data
        }
        return decoded
    }

    static func bytes(from value: Any?) -> Data? {
        if let data = value as? Data { return data }
        if let list = value as? [Any] {
            var bytes = [UInt8]()
            bytes.reserveCapacity(list.count)
            for item in list {
                if let n = item as? NSNumber { bytes.append(UInt8(truncatingIfNeeded: n.intValue)) }
                else if let i = item as? Int { bytes.append(UInt8(truncatingIfNeeded: i)) }
                else { return nil }
            }
            return Data(bytes)
        }
        if let dict = value as? [String: Any] {
            // JS 的 Uint8Array 有时桥接成 {0:..,1:..}；按连续数字键还原。
            let keys = dict.keys.compactMap { Int($0) }.sorted()
            guard keys.count == dict.count, keys.first == 0 else { return nil }
            var bytes = [UInt8]()
            bytes.reserveCapacity(keys.count)
            for key in keys {
                guard let n = dict[String(key)] as? NSNumber else { return nil }
                bytes.append(UInt8(truncatingIfNeeded: n.intValue))
            }
            return Data(bytes)
        }
        return nil
    }
}
