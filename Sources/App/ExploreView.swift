import SwiftUI

/// 「探索」：自己拼的发现页。每张卡片 = 一个（或几个）书源发现分类 + 一种参考版式。
struct ExploreView: View {
    @ThemePalette private var palette
    @EnvironmentObject private var appStore: AppStore
    @StateObject private var store: ExploreStore
    @State private var sheet: ExploreSheet?

    private enum ExploreSheet: Identifiable {
        case add
        case manage
        case metaImport
        case edit(ExploreBoard)

        var id: String {
            switch self {
            case .add: return "add"
            case .manage: return "manage"
            case .metaImport: return "meta"
            case .edit(let board): return "edit-" + board.id
            }
        }
    }

    init() {
        _store = StateObject(wrappedValue: ExploreStore())
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                if store.boards.isEmpty {
                    emptyState
                } else {
                    ForEach(store.boards) { board in
                        ExploreBoardCard(store: store,
                                         board: board,
                                         onEdit: { sheet = .edit(board) },
                                         onDelete: { remove(board) })
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 28)
        }
        .refreshable { await store.refreshAll() }
        .foregroundStyle(palette.primary)
        .background { AppThemeCanvas().ignoresSafeArea() }
        .navigationTitle("探索")
        .toolbar(.visible, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) { menuButton }
        }
        .sheet(item: $sheet) { item in
            switch item {
            case .add:
                ExploreBoardEditor(board: nil) { boards in
                    store.add(boards)
                    sheet = nil
                }
                .environmentObject(appStore)
            case .manage:
                ExploreManageSheet(store: store)
                    .environmentObject(appStore)
            case .metaImport:
                ExploreMetaImportSheet {
                    store.reloadMeta()
                }
            case .edit(let board):
                ExploreBoardEditor(board: board) { store.update($0.first ?? board) }
                    .environmentObject(appStore)
            }
        }
        .accessibilityIdentifier("explore.page")
    }

    private var menuButton: some View {
        Menu {
            Button {
                sheet = .add
            } label: {
                Label("添加板块", systemImage: "plus")
            }
            Button {
                sheet = .manage
            } label: {
                Label("管理板块", systemImage: "slider.horizontal.3")
            }
            Divider()
            Button {
                Task { await store.refreshAll() }
            } label: {
                Label("刷新全部", systemImage: "arrow.clockwise")
            }
            Button {
                sheet = .metaImport
            } label: {
                Label("导入标签 / 推荐语…", systemImage: "text.badge.plus")
            }
        } label: {
            HStack(spacing: 4) {
                Text("管理").appFont(.system(size: 14, weight: .medium))
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .semibold))
            }
            .foregroundStyle(palette.primary)
            .padding(.horizontal, 12)
            .frame(height: 34)
            .background { Capsule().stroke(palette.border.opacity(0.6), lineWidth: 1) }
            .contentShape(Capsule())
        }
        .accessibilityIdentifier("explore.menu")
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "sparkles.rectangle.stack")
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(palette.secondary)
            Text("还没有探索板块")
                .appFont(.system(size: 19, weight: .semibold))
            Text("把书源的发现分类做成卡片：畅销精选、品质好书、双列榜单、新书榜、分类推荐、猜你喜欢，六种版式随时换。")
                .appFont(.system(size: 13))
                .foregroundStyle(palette.secondary)
                .multilineTextAlignment(.center)
                .lineSpacing(3)
            Button {
                sheet = .add
            } label: {
                Text("添加板块")
                    .appFont(.system(size: 15, weight: .semibold))
                    .foregroundStyle(palette.onAccent)
                    .padding(.horizontal, 24)
                    .frame(height: 42)
                    .background { Capsule().fill(palette.accent) }
            }
            .buttonStyle(.plain)
            .padding(.top, 4)
            .accessibilityIdentifier("explore.empty.add")
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 22)
        .padding(.vertical, 30)
        .background {
            RoundedRectangle(cornerRadius: ExploreStyle.cardRadius, style: .continuous)
                .fill(palette.surface)
        }
    }

    private func remove(_ board: ExploreBoard) {
        withAnimation(.easeInOut(duration: 0.2)) {
            store.remove(id: board.id)
        }
    }
}

// MARK: - 管理板块

struct ExploreManageSheet: View {
    @ThemePalette private var palette
    @EnvironmentObject private var appStore: AppStore
    @ObservedObject var store: ExploreStore
    @Environment(\.dismiss) private var dismiss
    @State private var sheet: ManageSheet?

    private enum ManageSheet: Identifiable {
        case add
        case edit(ExploreBoard)

        var id: String {
            switch self {
            case .add: return "add"
            case .edit(let board): return "edit-" + board.id
            }
        }
    }

    var body: some View {
        NavigationStack {
            List {
                if store.boards.isEmpty {
                    Text("还没有板块。点右上角 + 添加一个。")
                        .appFont(.footnote)
                        .foregroundStyle(palette.secondary)
                        .independentGlassRow()
                } else {
                    Section {
                        ForEach(store.boards) { board in
                            Button {
                                sheet = .edit(board)
                            } label: {
                                row(board)
                            }
                            .buttonStyle(.plain)
                            .independentGlassRow()
                        }
                        .onMove { store.move(from: $0, to: $1) }
                        .onDelete { store.remove(at: $0) }
                    } footer: {
                        Text("点一行编辑；右上角「编辑」可拖动排序或删除。")
                            .appFont(.caption)
                            .foregroundStyle(palette.secondary)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background { AppThemeCanvas().ignoresSafeArea() }
            .navigationTitle("探索板块")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { EditButton() }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { sheet = .add } label: { Image(systemName: "plus") }
                        .accessibilityIdentifier("explore.manage.add")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
            .sheet(item: $sheet) { item in
                switch item {
                case .add:
                    ExploreBoardEditor(board: nil) { store.add($0) }
                        .environmentObject(appStore)
                case .edit(let board):
                    ExploreBoardEditor(board: board) { store.update($0.first ?? board) }
                        .environmentObject(appStore)
                }
            }
        }
        .accessibilityIdentifier("explore.manage.page")
    }

    private func row(_ board: ExploreBoard) -> some View {
        HStack(spacing: 12) {
            Image(systemName: board.layout.symbol)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(palette.secondary)
                .frame(width: 26)
            VStack(alignment: .leading, spacing: 2) {
                Text(board.displayTitle)
                    .appFont(.system(size: 16, weight: .medium))
                    .foregroundStyle(palette.primary)
                    .lineLimit(1)
                Text(detail(board))
                    .appFont(.system(size: 11.5))
                    .foregroundStyle(palette.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 6)
            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(palette.secondary)
        }
        .contentShape(Rectangle())
        .padding(.vertical, 2)
    }

    private func detail(_ board: ExploreBoard) -> String {
        let sourceNames = board.visibleCategories.compactMap { category in
            appStore.source(for: category.sourceURL)?.bookSourceName
        }
        let sourceText = Array(Set(sourceNames)).sorted().joined(separator: "、")
        let count = board.visibleCategories.count
        return [board.layout.title, sourceText, "\(count) 个分类"].filter { !$0.isEmpty }.joined(separator: " · ")
    }
}

// MARK: - 导入标签 / 推荐语（AI 接入点）

/// 外部（AI）生成的标签与推荐语的粘贴入口。
/// 只写本机文件，不上传；格式见 `ExploreMetaStore`。
struct ExploreMetaImportSheet: View {
    @ThemePalette private var palette
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var message: String?
    @State private var failed = false
    var onImported: () -> Void

    var body: some View {
        NavigationStack {
            List {
                Section {
                    TextEditor(text: $text)
                        .font(.system(size: 12, design: .monospaced))
                        .frame(minHeight: 220)
                        .accessibilityIdentifier("explore.meta.text")
                } header: {
                    Text("JSON")
                } footer: {
                    Text("格式：{\"书籍地址\": {\"tags\": [\"求生游戏\", \"悬疑流\"], \"reason\": \"这本「都市」佳作与你的匹配度高达 87%！\"}}\n也可以只写 {\"书籍地址\": [\"标签\", \"标签\"]}。")
                        .appFont(.caption)
                }
                if let message {
                    Section {
                        Text(message)
                            .appFont(.footnote)
                            .foregroundStyle(failed ? Color.red : palette.secondary)
                    }
                }
                Section {
                    Text("写入 Application Support/LegadoReading/explore-meta.json，卡片上的标签与「猜你喜欢」的推荐语会立即跟着变。")
                        .appFont(.caption)
                        .foregroundStyle(palette.secondary)
                }
            }
            .scrollContentBackground(.hidden)
            .background { AppThemeCanvas().ignoresSafeArea() }
            .navigationTitle("导入标签 / 推荐语")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("导入") { importJSON() }
                        .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .accessibilityIdentifier("explore.meta.page")
    }

    private func importJSON() {
        do {
            let count = try ExploreMetaStore.merge(json: text)
            failed = false
            message = "已写入 \(count) 本书。"
            onImported()
        } catch {
            failed = true
            message = error.localizedDescription
        }
    }
}
