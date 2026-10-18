import Foundation
import CoreML

/// 超分运行时的日志（移植代码里替换了 Aidoku 的 LogManager）。
enum UpscaleLog {
    static func error(_ message: String) {
        #if DEBUG
        print("[upscale] \(message)")
        #endif
        CrashReporter.note("图片超分 \(message)")
    }
}

/// Aidoku 模型仓库的清单条目（https://upscale.aidoku.app/models.json）。
struct UpscaleModelInfo: Decodable {
    let name: String
    let info: String?
    let tags: [String]?
    let type: String?
    let file: String
    let size: Int?
    let config: [String: UpscaleConfigValue]?

    var fileName: String { (file as NSString).lastPathComponent }
    var isPackage: Bool { fileName.hasSuffix(".mlpackage") }

    var configDictionary: [String: Any] {
        var out: [String: Any] = [:]
        for (key, value) in config ?? [:] {
            switch value {
            case .int(let v): out[key] = v
            case .bool(let v): out[key] = v
            case .string(let v): out[key] = v
            case .ints(let v): out[key] = v
            }
        }
        return out
    }
}

/// models.json 的 config 字段是任意标量/整型数组，这里只取推理需要的几种。
enum UpscaleConfigValue: Decodable {
    case int(Int)
    case bool(Bool)
    case string(String)
    case ints([Int])

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let value = try? container.decode(Int.self) {
            self = .int(value)
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([Int].self) {
            self = .ints(value)
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "不支持的配置值")
        }
    }
}

struct UpscaleModelList: Decodable {
    let models: [UpscaleModelInfo]
}

/// 模型的下载、安装、加载。模型来自 Aidoku 的公开模型仓库（waifu2x / Real-ESRGAN）。
/// `.mlpackage` 在服务端是 zip（下载后用 ZipReader 解开），`.mlmodel` 是单文件。
/// 加载走 `MLModel.compileModel(at:)`，.mlmodel / .mlpackage 都能在运行时编译。
actor UpscaleModelStore {
    static let shared = UpscaleModelStore()

    static let listURL = URL(string: "https://upscale.aidoku.app/models.json")!
    private static let supportedTypes: Set<String> = ["multiarray", "image"]

    private var modelCache: [String: ImageProcessingModel] = [:]
    private var cachedList: [UpscaleModelInfo]?

    // MARK: 清单

    func availableModels() async -> [UpscaleModelInfo] {
        if let cachedList { return cachedList }
        do {
            let (data, _) = try await URLSession.shared.data(from: Self.listURL)
            let list = try JSONDecoder().decode(UpscaleModelList.self, from: data)
            let models = list.models.filter { Self.supportedTypes.contains(($0.type ?? "").lowercased()) }
            cachedList = models
            return models
        } catch {
            UpscaleLog.error("模型清单获取失败 \(error.localizedDescription)")
            return []
        }
    }

    // MARK: 安装状态

    func installedFileNames() -> [String] {
        let dir = (try? modelsDirectory()) ?? URL(fileURLWithPath: "/dev/null")
        let files = (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
        return files.filter { $0.hasSuffix(".mlpackage") || $0.hasSuffix(".mlmodel") }.sorted()
    }

    func isInstalled(_ fileName: String) -> Bool {
        guard let dir = try? modelsDirectory() else { return false }
        let url = dir.appendingPathComponent((fileName as NSString).lastPathComponent)
        return FileManager.default.fileExists(atPath: url.path)
    }

    func installedSize(_ fileName: String) -> Int {
        guard let dir = try? modelsDirectory() else { return 0 }
        let url = dir.appendingPathComponent((fileName as NSString).lastPathComponent)
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) else { return 0 }
        if isDir.boolValue {
            guard let enumerator = FileManager.default.enumerator(atPath: url.path) else { return 0 }
            var total = 0
            for case let subpath as String in enumerator {
                let attrs = try? FileManager.default.attributesOfItem(atPath: url.appendingPathComponent(subpath).path)
                total += (attrs?[.size] as? NSNumber)?.intValue ?? 0
            }
            return total
        }
        let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
        return (attrs?[.size] as? NSNumber)?.intValue ?? 0
    }

    // MARK: 下载与删除

    func download(_ info: UpscaleModelInfo,
                  progress: @escaping (Double) -> Void) async throws {
        let fileName = info.fileName
        let target = try modelsDirectory().appendingPathComponent(fileName)
        let isPackage = info.isPackage
        let url = URL(string: info.file, relativeTo: Self.listURL)!
        let downloadURL = isPackage ? url.appendingPathExtension("zip") : url

        let (tempURL, response) = try await downloadToTemp(downloadURL, progress: progress)
        defer { try? FileManager.default.removeItem(at: tempURL) }
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw URLError(.badServerResponse)
        }
        let data = try Data(contentsOf: tempURL)
        progress(1)

        // 全部准备好再替换旧模型，避免半成品把可用模型弄坏。
        if isPackage {
            let staging = try modelsDirectory().appendingPathComponent(fileName + ".installing")
            try? FileManager.default.removeItem(at: staging)
            defer { try? FileManager.default.removeItem(at: staging) }
            try extractPackage(zip: data, to: staging)
            if FileManager.default.fileExists(atPath: target.path) {
                try FileManager.default.removeItem(at: target)
            }
            try FileManager.default.moveItem(at: staging, to: target)
        } else {
            try data.write(to: target, options: .atomic)
        }
        modelCache[fileName] = nil
    }

    func remove(_ fileName: String) {
        guard let dir = try? modelsDirectory() else { return }
        let name = (fileName as NSString).lastPathComponent
        try? FileManager.default.removeItem(at: dir.appendingPathComponent(name))
        modelCache[name] = nil
    }

    // MARK: 加载

    /// 按档位取模型：档位对应模型优先，没装就退回已装的任意模型。
    func model(for quality: UpscaleQuality) throws -> ImageProcessingModel? {
        if isInstalled(quality.modelFile) {
            return try loadModel(fileName: quality.modelFile)
        }
        guard let fallback = installedFileNames().first else { return nil }
        return try loadModel(fileName: fallback)
    }

    func loadModel(fileName: String) throws -> ImageProcessingModel? {
        let name = (fileName as NSString).lastPathComponent
        if let cached = modelCache[name] { return cached }
        guard let dir = try? modelsDirectory() else { return nil }
        let url = dir.appendingPathComponent(name)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let compiled = try MLModel.compileModel(at: url)
        let mlModel = try MLModel(contentsOf: compiled)
        // 目前仓库里的两个模型都是 multiarray 型（input/output 两个端口），
        // waifu2x 需要 shrinkSize 裁边，Real-ESRGAN 是整块 256。
        var config: [String: Any] = [
            "inputName": "input",
            "outputName": "output",
            "blockSize": 256,
            "scale": 2,
        ]
        if name.contains("waifu2x") {
            config["blockSize"] = 156
            config["shrinkSize"] = 7
        }
        let model = MultiArrayModel(model: mlModel, config: config)
        modelCache[name] = model
        return model
    }

    // MARK: 内部

    private func modelsDirectory() throws -> URL {
        let base = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                               appropriateFor: nil, create: true)
        let dir = base.appendingPathComponent("LegadoReading/UpscaleModels", isDirectory: true)
        if !FileManager.default.fileExists(atPath: dir.path) {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    /// 把 `.mlpackage` 的 zip 解到目录。zip 里可能是包本身，也可能是套了一层同名目录。
    private func extractPackage(zip: Data, to directory: URL) throws {
        let reader = try ZipReader(data: zip)
        let names = reader.entries.keys.filter { !$0.hasSuffix("/") }.sorted()
        guard !names.isEmpty else { throw ZipReader.ZipError.corrupt }

        // 若所有条目都位于同名顶层目录下，剥掉这一层。
        var prefix = ""
        let first = names[0]
        if let slash = first.firstIndex(of: "/") {
            let candidate = String(first[first.startIndex..<slash]) + "/"
            if names.allSatisfy({ $0.hasPrefix(candidate) }) { prefix = candidate }
        }

        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for name in names {
            var relative = prefix.isEmpty ? name : String(name.dropFirst(prefix.count))
            // 防目录穿越。
            let parts = relative.split(separator: "/")
            guard !parts.contains(".."), !parts.isEmpty else { continue }
            let outURL = directory.appendingPathComponent(relative)
            try FileManager.default.createDirectory(at: outURL.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            try reader.read(name).write(to: outURL, options: .atomic)
        }
    }

    private func downloadToTemp(_ url: URL,
                                progress: @escaping @Sendable (Double) -> Void) async throws -> (URL, URLResponse) {
        final class Box: @unchecked Sendable {
            var task: URLSessionDownloadTask?
            var observation: NSKeyValueObservation?
        }
        let box = Box()
        return try await withCheckedThrowingContinuation { continuation in
            let task = URLSession.shared.downloadTask(with: url) { fileURL, response, error in
                defer { box.observation = nil }
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let fileURL, let response else {
                    continuation.resume(throwing: URLError(.badServerResponse))
                    return
                }
                let temp = FileManager.default.temporaryDirectory
                    .appendingPathComponent("upscale-" + UUID().uuidString + ".bin")
                do {
                    try FileManager.default.moveItem(at: fileURL, to: temp)
                    continuation.resume(returning: (temp, response))
                } catch {
                    continuation.resume(throwing: error)
                }
            }
            box.task = task
            var last: Double = -1
            box.observation = task.progress.observe(\.fractionCompleted, options: [.new]) { _, change in
                guard let value = change.newValue, value.isFinite else { return }
                guard value - last >= 0.02 || value >= 1 else { return }
                last = value
                progress(value)
            }
            task.resume()
        }
    }
}
