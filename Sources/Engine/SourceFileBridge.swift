import Foundation

/// 书源 JS 的文件与压缩包 API（对应 Legado `JsExtensions` 的
/// `getFile / readFile / deleteFile / downloadFile / unArchiveFile / unzipFile /
/// unrarFile / un7zFile / getZipStringContent / getZipByteArrayContent /
/// getTxtInFolder` 等）。
///
/// Legado 的路径是相对 `externalCache` 的「沙箱相对路径」，这里用 Caches 目录
/// 做同样的根，并强制校验规范化后的路径仍在根内，避免 `../` 越界。
enum SourceFileBridge {
    enum BridgeError: Error { case illegalPath, notFound, unsupportedArchive }

    /// 所有相对路径的根。与 Legado 的 `externalCache` 对应。
    static var root: URL {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("sourceFiles", isDirectory: true)
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    /// 把书源给的路径解析成根目录下的绝对 URL，并确认没有越界。
    static func resolve(_ path: String) throws -> URL {
        let raw = path.trimmingCharacters(in: .whitespacesAndNewlines)
        let rootURL = root
        // Legado 把以 / 开头的路径也视为根内路径（直接拼在缓存目录后面）。
        let trimmed = raw.hasPrefix("/") ? String(raw.dropFirst()) : raw
        let candidate = URL(fileURLWithPath: trimmed, relativeTo: rootURL).standardizedFileURL
        let rootPath = rootURL.standardizedFileURL.path
        guard candidate.path == rootPath || candidate.path.hasPrefix(rootPath + "/") else {
            throw BridgeError.illegalPath
        }
        return candidate
    }

    static func readFile(_ path: String) -> [UInt8]? {
        guard let url = try? resolve(path), let data = try? Data(contentsOf: url) else { return nil }
        return [UInt8](data)
    }

    static func writeFile(_ path: String, bytes: [UInt8]) -> String {
        guard let url = try? resolve(path) else { return "" }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        guard (try? Data(bytes).write(to: url)) != nil else { return "" }
        return url.path
    }

    static func deleteFile(_ path: String) -> Bool {
        guard let url = try? resolve(path) else { return false }
        guard FileManager.default.fileExists(atPath: url.path) else { return false }
        return (try? FileManager.default.removeItem(at: url)) != nil
    }

    static func exists(_ path: String) -> Bool {
        guard let url = try? resolve(path) else { return false }
        return FileManager.default.fileExists(atPath: url.path)
    }

    /// GB18030（兼容 GBK/GB2312）。Foundation 没有 `.gb18030` 便捷成员，需要走 CFString 转换。
    static let gb18030 = String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(
        CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue)))

    /// 书源脚本里 `getThemeConfigMap()` 需要判断当前是否深色。
    /// 书源线程不是主线程，读 UserDefaults 里的外观设置即可。
    static var isDarkMode: Bool {
        switch UserDefaults.standard.string(forKey: "app.appearance.v1") ?? "system" {
        case "dark": return true
        case "light": return false
        default:
            // system：没法在后台线程问 UITraitCollection，按浅色返回。
            return false
        }
    }

    /// `getTxtInFolder`：把目录下所有 .txt 按文件名顺序拼起来。
    static func txtInFolder(_ path: String) -> String {
        guard let dir = try? resolve(path),
              let names = try? FileManager.default.contentsOfDirectory(atPath: dir.path) else { return "" }
        var out = ""
        for name in names.sorted() where name.lowercased().hasSuffix(".txt") {
            let file = dir.appendingPathComponent(name)
            if let text = try? String(contentsOf: file, encoding: .utf8) {
                out += text
            } else if let data = try? Data(contentsOf: file),
                      let text = String(data: data, encoding: SourceFileBridge.gb18030) {
                out += text
            }
        }
        return out
    }

    // MARK: - 压缩包

    /// `unzipFile` / `unArchiveFile`：解压到同目录的子文件夹，返回该文件夹的相对路径。
    /// iOS 端只内置 ZIP（`ZipReader`）；RAR / 7z 需要外部库，未支持时返回空串。
    static func unarchive(_ path: String) -> String {
        guard let url = try? resolve(path) else { return "" }
        let ext = url.pathExtension.lowercased()
        guard ext == "zip" else { return "" }
        guard let data = try? Data(contentsOf: url) else { return "" }
        let folder = url.deletingPathExtension()
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        guard let reader = try? ZipReader(data: data) else { return "" }
        for (name, _) in reader.entries {
            guard let payload = try? reader.read(name) else { continue }
            let target = folder.appendingPathComponent(name)
            // 防 zip slip
            guard target.standardizedFileURL.path.hasPrefix(folder.standardizedFileURL.path) else { continue }
            try? FileManager.default.createDirectory(at: target.deletingLastPathComponent(),
                                                     withIntermediateDirectories: true)
            try? payload.write(to: target)
        }
        return folder.lastPathComponent
    }

    /// `getZipStringContent`：读压缩包内某个条目的文本。
    static func zipStringContent(_ path: String, _ entry: String, _ charset: String? = nil) -> String {
        guard let url = try? resolve(path), let data = try? Data(contentsOf: url),
              let reader = try? ZipReader(data: data), let payload = try? reader.read(entry) else { return "" }
        return decode(payload, charset: charset)
    }

    /// `getZipByteArrayContent`：读压缩包内某个条目的字节。
    static func zipByteArrayContent(_ path: String, _ entry: String) -> [UInt8]? {
        guard let url = try? resolve(path), let data = try? Data(contentsOf: url),
              let reader = try? ZipReader(data: data), let payload = try? reader.read(entry) else { return nil }
        return [UInt8](payload)
    }

    static func decode(_ data: Data, charset: String? = nil) -> String {
        let name = (charset ?? "").uppercased()
        switch name {
        case "UTF-8", "UTF8":
            if let text = String(data: data, encoding: .utf8) { return text }
        case "GBK", "GB2312", "GB18030":
            if let text = String(data: data, encoding: gb18030) { return text }
        default:
            break
        }
        if let text = String(data: data, encoding: .utf8) { return text }
        return String(data: data, encoding: gb18030) ?? ""
    }
}
