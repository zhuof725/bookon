import Foundation
import Combine
import UIKit
import CoreText
import CryptoKit

struct ReadingFontChoice: Codable, Identifiable, Equatable {
    /// The actual PostScript name; empty means the existing reader default.
    let id: String
    let name: String
}

struct ImportedReadingFont: Codable, Identifiable, Equatable {
    let id: String
    let originalName: String
    let storedName: String
    let faces: [ReadingFontChoice]
    let fileSize: Int
}

/// Construct and mutate on the main thread. Deliberately not type-isolated:
/// existing synchronous reader/font caches can use this object without an actor hop.
/// Observe selectedPostScriptName to invalidate layout and repaginate the reader.
final class ReadingFontManager: ObservableObject {
    nonisolated(unsafe) static let shared = ReadingFontManager()
    static let selectionKey = "readingFont.postscript.v1"
    private static let maximumBytes = 32 * 1_024 * 1_024
    private static let maximumFiles = 30
    private static let extensions: Set<String> = ["ttf", "otf", "ttc"]

    @Published private(set) var selectedPostScriptName = ""
    @Published private(set) var importedFonts: [ImportedReadingFont] = []
    @Published private(set) var notice: String?
    private(set) var builtInFonts: [ReadingFontChoice] = []

    var selectedDisplayName: String {
        choices.first { $0.id == selectedPostScriptName }?.name ?? "系统默认"
    }

    private struct Manifest: Codable {
        let version: Int
        let fonts: [ImportedReadingFont]
    }

    private struct FontError: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    private let directory: URL
    private let defaults: UserDefaults
    private let files = FileManager.default
    private var hashes: [String: SHA256.Digest] = [:]
    private var storageIssue: String?
    private var retiredNames: Set<String> = []
    private var choices: [ReadingFontChoice] { builtInFonts + importedFonts.flatMap(\.faces) }
    private var manifestURL: URL { directory.appendingPathComponent("manifest.json") }

    init(directory: URL? = nil, defaults: UserDefaults = .standard) {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Documents", isDirectory: true)
        self.directory = (directory ?? documents.appendingPathComponent("ReadingFonts", isDirectory: true)).standardizedFileURL
        self.defaults = defaults
        builtInFonts = Self.localChoices()
        loadLibrary() // Register every usable owned file BEFORE resolving the saved selection.
        let saved = defaults.string(forKey: Self.selectionKey) ?? ""
        if saved.isEmpty || (choices.contains { $0.id == saved } && UIFont(name: saved, size: 20) != nil) {
            selectedPostScriptName = saved
        } else {
            defaults.set("", forKey: Self.selectionKey)
            appendNotice("之前选择的字体不可用，已恢复系统默认。")
        }
    }

    func select(_ postScriptName: String) throws {
        guard postScriptName.isEmpty || (choices.contains { $0.id == postScriptName }
            && UIFont(name: postScriptName, size: 20) != nil) else {
            throw FontError(message: "此字体不可用，原来的字体选择未改变。")
        }
        guard postScriptName != selectedPostScriptName else { return }
        defaults.set(postScriptName, forKey: Self.selectionKey)
        selectedPostScriptName = postScriptName
    }

    func dismissNotice() { notice = nil }

    @discardableResult
    func importFont(from url: URL) throws -> ImportedReadingFont {
        try requireWritableStorage()
        guard url.isFileURL, Self.extensions.contains(url.pathExtension.lowercased()) else {
            throw FontError(message: "仅支持 TTF、OTF 和 TTC 字体文件。")
        }
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        let data = try coordinatedRead(url)
        let digest = SHA256.hash(data: data)
        if let existing = importedFonts.first(where: { hashes[$0.id] == digest && !$0.faces.isEmpty }) {
            notice = "「\(existing.originalName)」已经导入，未添加重复文件，也未改变字体选择。"
            return existing
        }
        guard try ownedFileCount() < Self.maximumFiles else {
            throw FontError(message: "最多保存 30 个字体文件，请先移除不用的字体。")
        }

        let id = UUID().uuidString
        let storedName = id + "." + url.pathExtension.lowercased()
        let destination = try ownedURL(storedName, id: id)
        var committed = false
        var attemptedRegistration = false
        defer {
            if !committed {
                if attemptedRegistration, let warning = unregister(destination) { appendNotice(warning) }
                do { if files.fileExists(atPath: destination.path) { try files.removeItem(at: destination) } }
                catch { appendNotice("未完成导入的本地副本清理失败：\(error.localizedDescription)") }
            }
        }
        // Only an app-owned UUID file is written; the provider's original is never changed.
        do { try data.write(to: destination, options: .atomic) }
        catch { throw FontError(message: "无法保存字体副本：\(error.localizedDescription)") }
        let faces = try descriptors(at: destination)
        let names = Set(faces.map(\.id))
        for existing in importedFonts where !names.isDisjoint(with: existing.faces.map(\.id)) {
            if names == Set(existing.faces.map(\.id)) {
                notice = "此文件的字体已包含在「\(existing.originalName)」中，未重复导入。"
                return existing
            }
            throw FontError(message: "此文件与「\(existing.originalName)」包含同名字体，整份文件未导入，避免覆盖。")
        }
        try rejectRegisteredCollisions(faces, at: destination)
        attemptedRegistration = true
        try register(destination, faces: faces)
        let imported = ImportedReadingFont(id: id, originalName: url.lastPathComponent,
            storedName: storedName, faces: faces, fileSize: data.count)
        let next = importedFonts + [imported]
        try commit(next) // Failure rolls back registration and the copied file; selection stays intact.
        committed = true
        hashes[id] = digest
        importedFonts = next
        notice = nil
        return imported
    }

    func remove(_ imported: ImportedReadingFont) throws {
        try requireWritableStorage()
        guard let owned = importedFonts.first(where: { $0.id == imported.id }) else {
            throw FontError(message: "此字体文件已不在字体库中。")
        }
        // Do not trust filenames/faces supplied by the caller; use the owned manifest entry.
        let url = try ownedURL(owned.storedName, id: owned.id)
        let next = importedFonts.filter { $0.id != owned.id }
        let resetSelection = owned.faces.contains { $0.id == selectedPostScriptName }
        try commit(next) // Do not unregister, delete, or change selection if saving fails.
        importedFonts = next
        hashes.removeValue(forKey: owned.id)
        notice = nil
        if resetSelection {
            defaults.set("", forKey: Self.selectionKey)
            selectedPostScriptName = ""
            appendNotice("已移除当前阅读字体，已恢复系统默认。")
        }
        if !owned.faces.isEmpty, let warning = unregister(url) {
            retiredNames.formUnion(owned.faces.map(\.id))
            appendNotice(warning)
        }
        do {
            if files.fileExists(atPath: url.path) { try files.removeItem(at: url) }
        } catch {
            // The manifest removal is already committed: never pretend the file was deleted.
            appendNotice("字体已从可选列表移除，但本地副本未能删除：\(error.localizedDescription)")
        }
    }

    private static func localChoices() -> [ReadingFontChoice] {
        var result = [ReadingFontChoice(id: "", name: "系统默认")]
        let candidates: [(String, [String])] = [
            ("苹方", ["PingFangSC-Regular"]),
            ("宋体", ["SongtiSC-Regular"]),
            ("楷体", ["STKaiti", "KaitiSC-Regular"])
        ]
        for (label, names) in candidates {
            if let font = names.compactMap({ UIFont(name: $0, size: 20) }).first,
               !result.contains(where: { $0.id == font.fontName }) {
                result.append(ReadingFontChoice(id: font.fontName, name: label))
            }
        }
        return result
    }

    private func loadLibrary() {
        do {
            try ensureDirectory()
            guard files.fileExists(atPath: manifestURL.path) else { return }
            // A symlinked manifest must never read or overwrite an external file.
            guard (try? files.destinationOfSymbolicLink(atPath: manifestURL.path)) == nil else {
                throw FontError(message: "字体清单不能是符号链接。")
            }
            let manifestData = try readLimited(manifestURL)
            let manifest = try JSONDecoder().decode(Manifest.self, from: manifestData)
            guard manifest.version == 1, manifest.fonts.count <= Self.maximumFiles else {
                throw FontError(message: "字体清单版本不受支持或文件数超过上限。")
            }
            var ids: Set<String> = []
            var storedNames: Set<String> = []
            var faceNames: Set<String> = []
            for entry in manifest.fonts {
                let url: URL
                do {
                    url = try ownedURL(entry.storedName, id: entry.id)
                    guard ids.insert(entry.id).inserted, storedNames.insert(entry.storedName).inserted else {
                        throw FontError(message: "清单存在重复记录。")
                    }
                } catch {
                    appendNotice("已忽略不安全或重复的字体记录：\(entry.originalName)。")
                    continue
                }
                var attemptedRegistration = false
                do {
                    let data = try readLimited(url)
                    let faces = try descriptors(at: url)
                    guard faceNames.isDisjoint(with: faces.map(\.id)) else {
                        throw FontError(message: "字体名称与已导入文件重复。")
                    }
                    try rejectRegisteredCollisions(faces, at: url)
                    attemptedRegistration = true
                    try register(url, faces: faces)
                    faceNames.formUnion(faces.map(\.id))
                    hashes[entry.id] = SHA256.hash(data: data)
                    importedFonts.append(ImportedReadingFont(id: entry.id, originalName: entry.originalName,
                        storedName: entry.storedName, faces: faces, fileSize: data.count))
                } catch {
                    if attemptedRegistration, let warning = unregister(url) { appendNotice(warning) }
                    // Keep a removable record, but never offer missing/corrupt faces as choices.
                    importedFonts.append(ImportedReadingFont(id: entry.id, originalName: entry.originalName,
                        storedName: entry.storedName, faces: [], fileSize: max(0, entry.fileSize)))
                    appendNotice("「\(entry.originalName)」不可用：\(error.localizedDescription) 可移除后重新导入。")
                }
            }
        } catch {
            storageIssue = "字体库清单无法读取，已保留原文件。请检查本地存储后重新打开应用：\(error.localizedDescription)"
            appendNotice(storageIssue!)
        }
    }

    private func requireWritableStorage() throws {
        if let storageIssue { throw FontError(message: storageIssue) }
        try ensureDirectory()
    }

    private func ensureDirectory() throws {
        guard directory.isFileURL,
              (try? files.destinationOfSymbolicLink(atPath: directory.path)) == nil else {
            throw FontError(message: "字体目录无效，不能使用符号链接目录。")
        }
        try files.createDirectory(at: directory, withIntermediateDirectories: true)
        guard try directory.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true else {
            throw FontError(message: "无法访问本地字体目录。")
        }
    }

    private func ownedURL(_ basename: String, id: String) throws -> URL {
        guard UUID(uuidString: id) != nil, !basename.contains("/"), !basename.contains("\\"),
              !basename.hasPrefix("."), (basename as NSString).deletingPathExtension == id,
              Self.extensions.contains((basename as NSString).pathExtension.lowercased()) else {
            throw FontError(message: "字体文件记录无效，已阻止访问字体目录之外的文件。")
        }
        let url = directory.appendingPathComponent(basename).standardizedFileURL
        guard url.deletingLastPathComponent().standardizedFileURL.path == directory.path,
              (try? files.destinationOfSymbolicLink(atPath: url.path)) == nil,
              url.resolvingSymlinksInPath().deletingLastPathComponent().path == directory.resolvingSymlinksInPath().path else {
            throw FontError(message: "字体文件路径不安全，不能使用符号链接。")
        }
        return url
    }

    private func ownedFileCount() throws -> Int {
        var names = Set(importedFonts.map(\.storedName))
        // Include orphaned owned copies after interrupted writes/deletes in the limit.
        for url in try files.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) {
            if Self.extensions.contains(url.pathExtension.lowercased()),
               UUID(uuidString: url.deletingPathExtension().lastPathComponent) != nil {
                names.insert(url.lastPathComponent)
            }
        }
        return names.count
    }

    private func coordinatedRead(_ url: URL) throws -> Data {
        var coordinationError: NSError?
        var result: Result<Data, Error>?
        NSFileCoordinator(filePresenter: nil).coordinate(readingItemAt: url, options: [], error: &coordinationError) { readableURL in
            result = Result { try self.readLimited(readableURL) }
        }
        if let coordinationError {
            throw FontError(message: "无法读取所选文件：\(coordinationError.localizedDescription)")
        }
        guard let result else { throw FontError(message: "未能读取所选字体文件。") }
        return try result.get()
    }

    private func readLimited(_ url: URL) throws -> Data {
        let info = try url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey, .isSymbolicLinkKey])
        guard info.isRegularFile == true, info.isSymbolicLink != true else {
            throw FontError(message: "请选择普通字体文件，不能导入文件夹或符号链接。")
        }
        guard let size = info.fileSize, size > 0, size <= Self.maximumBytes else {
            throw FontError(message: "文件不能为空，且每个文件不能超过 32 MB。")
        }
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var data = Data()
        // Enforce the limit while reading as well, even if the provider changes its file size.
        while let part = try handle.read(upToCount: min(65_536, Self.maximumBytes + 1 - data.count)), !part.isEmpty {
            data.append(part)
            guard data.count <= Self.maximumBytes else {
                throw FontError(message: "每个字体文件不能超过 32 MB。")
            }
        }
        guard !data.isEmpty else { throw FontError(message: "字体文件为空。") }
        return data
    }

    private func descriptors(at url: URL) throws -> [ReadingFontChoice] {
        guard let descriptors = CTFontManagerCreateFontDescriptorsFromURL(url as CFURL) as? [CTFontDescriptor],
              !descriptors.isEmpty else {
            throw FontError(message: "文件不包含有效字体，或格式已损坏。")
        }
        var names: Set<String> = []
        var result: [ReadingFontChoice] = []
        for descriptor in descriptors {
            guard let name = CTFontDescriptorCopyAttribute(descriptor, kCTFontNameAttribute) as? String,
                  !name.isEmpty, name.utf8.count <= 512 else {
                throw FontError(message: "字体缺少有效的 PostScript 名称。")
            }
            guard names.insert(name).inserted else { continue }
            let display = CTFontDescriptorCopyLocalizedAttribute(descriptor, kCTFontDisplayNameAttribute, nil) as? String
            result.append(ReadingFontChoice(id: name, name: display?.isEmpty == false ? display! : name))
        }
        return result
    }

    private func isRegistered(_ name: String, from url: URL) -> Bool {
        guard let font = UIFont(name: name, size: 20), font.fontName == name else { return false }
        let coreFont = CTFontCreateWithName(name as CFString, 20, nil)
        guard let source = CTFontCopyAttribute(coreFont, kCTFontURLAttribute) as? URL else { return false }
        return source.standardizedFileURL.resolvingSymlinksInPath() == url.standardizedFileURL.resolvingSymlinksInPath()
    }

    private func rejectRegisteredCollisions(_ faces: [ReadingFontChoice], at url: URL) throws {
        for face in faces {
            if retiredNames.contains(face.id) {
                throw FontError(message: "「\(face.name)」仍被当前进程使用，请重新打开应用后再导入。")
            }
            if builtInFonts.contains(where: { $0.id == face.id }) ||
                (UIFont(name: face.id, size: 20) != nil && !isRegistered(face.id, from: url)) {
                throw FontError(message: "「\(face.name)」与设备已安装或已注册的字体同名，不能覆盖。")
            }
        }
    }

    private func register(_ url: URL, faces: [ReadingFontChoice]) throws {
        var error: Unmanaged<CFError>?
        let registered = CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error)
        let underlying = error?.takeRetainedValue()
        // A second manager in the same process can encounter the same already-registered URL.
        if !registered && !faces.allSatisfy({ isRegistered($0.id, from: url) }) {
            let detail = underlying.map { CFErrorCopyDescription($0) as String } ?? "系统未能加载此字体。"
            throw FontError(message: "字体注册失败：\(detail)")
        }
        guard faces.allSatisfy({ UIFont(name: $0.id, size: 20)?.fontName == $0.id }) else {
            throw FontError(message: "字体注册后仍无法使用，未加入字体库。")
        }
    }

    private func unregister(_ url: URL) -> String? {
        guard files.fileExists(atPath: url.path) else { return nil }
        var error: Unmanaged<CFError>?
        let unregistered = CTFontManagerUnregisterFontsForURL(url as CFURL, .process, &error)
        let underlying = error?.takeRetainedValue()
        guard !unregistered else { return nil }
        let detail = underlying.map { CFErrorCopyDescription($0) as String } ?? "系统仍保留此字体。"
        return "系统未能注销此字体：\(detail) 字体可能仍被本次进程的排版缓存引用，退出应用后释放；它不会重新出现在可选列表。"
    }

    private func commit(_ fonts: [ImportedReadingFont]) throws {
        guard (try? files.destinationOfSymbolicLink(atPath: manifestURL.path)) == nil else {
            throw FontError(message: "字体清单路径不安全，未保存任何更改。")
        }
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(Manifest(version: 1, fonts: fonts)).write(to: manifestURL, options: .atomic)
        } catch {
            throw FontError(message: "字体清单保存失败，原有字体库和选择未改变：\(error.localizedDescription)")
        }
    }

    private func appendNotice(_ message: String) {
        notice = notice.map { $0 + "\n" + message } ?? message
    }
}
