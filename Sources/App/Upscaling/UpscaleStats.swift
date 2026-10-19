import SwiftUI

/// 超分作用对象（封面 / 漫画页）。
enum UpscaleKind {
    case cover
    case manga

    var label: String {
        switch self {
        case .cover: return "封面"
        case .manga: return "漫画页"
        }
    }
}

/// 超分运行情况：让用户能看到「到底有没有作用在封面上」。
/// 记录本次启动以来的张数与最近一次的详情（放大成功 / 跳过原因 / 失败原因）。
@MainActor
final class UpscaleStats: ObservableObject {
    static let shared = UpscaleStats()

    @Published private(set) var coverCount = 0
    @Published private(set) var mangaCount = 0
    @Published private(set) var coverLine: String?
    @Published private(set) var mangaLine: String?

    private init() {}

    func line(for kind: UpscaleKind) -> String? {
        switch kind {
        case .cover: return coverLine
        case .manga: return mangaLine
        }
    }

    func count(for kind: UpscaleKind) -> Int {
        switch kind {
        case .cover: return coverCount
        case .manga: return mangaCount
        }
    }

    func record(_ kind: UpscaleKind, _ text: String) {
        let prefix = count(for: kind) > 0 ? "已放大 \(count(for: kind)) 张 · " : ""
        switch kind {
        case .cover: coverLine = prefix + text
        case .manga: mangaLine = prefix + text
        }
    }

    func recordSuccess(_ kind: UpscaleKind, detail: String) {
        switch kind {
        case .cover:
            coverCount += 1
            coverLine = "已放大 \(coverCount) 张 · 最近：\(detail)"
        case .manga:
            mangaCount += 1
            mangaLine = "已放大 \(mangaCount) 张 · 最近：\(detail)"
        }
    }

    func reset() {
        coverCount = 0
        mangaCount = 0
        coverLine = nil
        mangaLine = nil
    }
}
