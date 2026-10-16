import SwiftUI

/// 书源编辑（对齐 Legado 原版 BookSourceEditActivity）：
/// 顶部类型与开关，分 基本/搜索/发现/详情/目录/正文 六页填写规则；字段名与原版一致。
/// 空白字段保存为 nil，不在 JSON 里写空串。
struct SourceEditView: View {
    /// nil = 新建书源。
    let original: BookSource?
    let store: AppStore

    @Environment(\.dismiss) private var dismiss
    @ThemePalette private var palette

    @State private var draft: BookSource
    @State private var tab: Tab = .base
    @State private var error: String?
    @State private var confirmDiscard = false

    init(original: BookSource?, store: AppStore) {
        self.original = original
        self.store = store
        _draft = State(initialValue: original ?? BookSource(bookSourceUrl: "", bookSourceName: ""))
    }

    enum Tab: String, CaseIterable, Identifiable {
        case base = "基本", search = "搜索", explore = "发现", info = "详情", toc = "目录", content = "正文"
        var id: String { rawValue }
    }

    struct Field: Identifiable {
        let label: String
        let key: String
        let get: (BookSource) -> String
        let set: (inout BookSource, String) -> Void
        var id: String { key }
    }

    private var changed: Bool { draft != (original ?? BookSource(bookSourceUrl: "", bookSourceName: "")) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    headerCard
                    Picker("分类", selection: $tab) {
                        ForEach(Tab.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("sourceEdit.tabs")
                    VStack(spacing: 10) {
                        ForEach(Self.fields(for: tab)) { fieldRow($0) }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .scrollDismissesKeyboard(.interactively)
            .background { AppThemeCanvas().ignoresSafeArea() }
            .navigationTitle(original == nil ? "新建书源" : "编辑书源")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { if changed { confirmDiscard = true } else { dismiss() } }
                        .accessibilityIdentifier("sourceEdit.cancel")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { save() }.accessibilityIdentifier("sourceEdit.save")
                }
            }
            .alert(error ?? "", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                Button("好", role: .cancel) {}
            }
            .alert("放弃未保存的修改？", isPresented: $confirmDiscard) {
                Button("继续编辑", role: .cancel) {}
                Button("放弃", role: .destructive) { dismiss() }
            }
        }
        .interactiveDismissDisabled(changed)
    }

    // MARK: 顶部：类型 + 开关

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("类型").foregroundStyle(palette.primary)
                Spacer()
                Picker("类型", selection: Binding(get: { draft.bookSourceType ?? 0 },
                                                  set: { draft.bookSourceType = $0 == 0 ? nil : $0 })) {
                    Text("文本").tag(0); Text("音频").tag(1); Text("图片").tag(2)
                    Text("文件").tag(3); Text("视频").tag(4)
                }
                .pickerStyle(.menu)
                .accessibilityIdentifier("sourceEdit.type")
            }
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: 10) {
                chip("启用", isOn: Binding(get: { draft.enabled ?? true }, set: { draft.enabled = $0 }))
                chip("发现", isOn: Binding(get: { draft.enabledExplore ?? true }, set: { draft.enabledExplore = $0 }))
                chip("CookieJar", isOn: Binding(get: { draft.enabledCookieJar ?? true }, set: { draft.enabledCookieJar = $0 }))
                chip("事件监听", isOn: Binding(get: { draft.eventListener ?? false }, set: { draft.eventListener = $0 }))
                chip("定制按钮", isOn: Binding(get: { draft.customButton ?? false }, set: { draft.customButton = $0 }))
            }
        }
        .appFont(.subheadline)
        .padding(16)
        .background { ThemeSurface(shape: RoundedRectangle(cornerRadius: 18, style: .continuous)) }
    }

    private func chip(_ title: String, isOn: Binding<Bool>) -> some View {
        Button { isOn.wrappedValue.toggle() } label: {
            HStack(spacing: 6) {
                Image(systemName: isOn.wrappedValue ? "checkmark.square.fill" : "square")
                    .foregroundStyle(isOn.wrappedValue ? palette.accent : palette.secondary)
                Text(title).foregroundStyle(palette.primary).lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityValue(isOn.wrappedValue ? "已开启" : "已关闭")
        .accessibilityIdentifier("sourceEdit.flag.\(title)")
    }

    // MARK: 字段

    private func fieldRow(_ f: Field) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("\(f.label)（\(f.key)）")
                .appFont(.caption).foregroundStyle(palette.secondary)
            TextField("", text: Binding(get: { f.get(draft) }, set: { f.set(&draft, $0) }), axis: .vertical)
                .lineLimit(1...10)
                .appFont(.system(.footnote, design: .monospaced))
                .foregroundStyle(palette.primary)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background { ThemeSurface(shape: RoundedRectangle(cornerRadius: 14, style: .continuous)) }
        .accessibilityIdentifier("sourceEdit.field.\(tab.rawValue).\(f.key)")
    }

    private static func clean(_ v: String) -> String? {
        v.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : v
    }

    private static func top(_ label: String, _ key: String, _ kp: WritableKeyPath<BookSource, String?>) -> Field {
        Field(label: label, key: key, get: { $0[keyPath: kp] ?? "" }, set: { $0[keyPath: kp] = clean($1) })
    }

    private static func rule<R>(_ label: String, _ key: String, _ rk: WritableKeyPath<BookSource, R?>,
                                _ fk: WritableKeyPath<R, String?>, empty: R) -> Field {
        Field(label: label, key: key,
              get: { $0[keyPath: rk]?[keyPath: fk] ?? "" },
              set: { s, v in
                  var r = s[keyPath: rk] ?? empty
                  r[keyPath: fk] = clean(v)
                  s[keyPath: rk] = r
              })
    }

    static func fields(for tab: Tab) -> [Field] {
        switch tab {
        case .base:
            return [
                Field(label: "源 URL", key: "bookSourceUrl", get: { $0.bookSourceUrl },
                      set: { $0.bookSourceUrl = $1.trimmingCharacters(in: .whitespacesAndNewlines) }),
                Field(label: "源名称", key: "bookSourceName", get: { $0.bookSourceName }, set: { $0.bookSourceName = $1 }),
                top("源分组", "bookSourceGroup", \.bookSourceGroup),
                top("源注释", "bookSourceComment", \.bookSourceComment),
                top("登录 URL", "loginUrl", \.loginUrl),
                top("登录 UI", "loginUi", \.loginUi),
                top("登录检查 JS", "loginCheckJs", \.loginCheckJs),
                top("封面解密", "coverDecodeJs", \.coverDecodeJs),
                top("书籍 URL 正则", "bookUrlPattern", \.bookUrlPattern),
                top("请求头", "header", \.header),
                top("变量说明", "variableComment", \.variableComment),
                top("并发率", "concurrentRate", \.concurrentRate),
                top("jsLib", "jsLib", \.jsLib),
            ]
        case .search:
            let e = SearchRule()
            return [
                top("搜索地址", "searchUrl", \.searchUrl),
                rule("校验关键字", "checkKeyWord", \.ruleSearch, \.checkKeyWord, empty: e),
                rule("书籍列表规则", "bookList", \.ruleSearch, \.bookList, empty: e),
                rule("书名规则", "name", \.ruleSearch, \.name, empty: e),
                rule("作者规则", "author", \.ruleSearch, \.author, empty: e),
                rule("分类规则", "kind", \.ruleSearch, \.kind, empty: e),
                rule("字数规则", "wordCount", \.ruleSearch, \.wordCount, empty: e),
                rule("最新章节规则", "lastChapter", \.ruleSearch, \.lastChapter, empty: e),
                rule("简介规则", "intro", \.ruleSearch, \.intro, empty: e),
                rule("封面规则", "coverUrl", \.ruleSearch, \.coverUrl, empty: e),
                rule("详情页 URL 规则", "bookUrl", \.ruleSearch, \.bookUrl, empty: e),
            ]
        case .explore:
            let e = SearchRule()
            return [
                top("发现地址规则", "exploreUrl", \.exploreUrl),
                rule("书籍列表规则", "bookList", \.ruleExplore, \.bookList, empty: e),
                rule("书名规则", "name", \.ruleExplore, \.name, empty: e),
                rule("作者规则", "author", \.ruleExplore, \.author, empty: e),
                rule("分类规则", "kind", \.ruleExplore, \.kind, empty: e),
                rule("字数规则", "wordCount", \.ruleExplore, \.wordCount, empty: e),
                rule("最新章节规则", "lastChapter", \.ruleExplore, \.lastChapter, empty: e),
                rule("简介规则", "intro", \.ruleExplore, \.intro, empty: e),
                rule("封面规则", "coverUrl", \.ruleExplore, \.coverUrl, empty: e),
                rule("详情页 URL 规则", "bookUrl", \.ruleExplore, \.bookUrl, empty: e),
            ]
        case .info:
            let e = BookInfoRule()
            return [
                rule("预处理规则", "init", \.ruleBookInfo, \.`init`, empty: e),
                rule("书名规则", "name", \.ruleBookInfo, \.name, empty: e),
                rule("作者规则", "author", \.ruleBookInfo, \.author, empty: e),
                rule("分类规则", "kind", \.ruleBookInfo, \.kind, empty: e),
                rule("字数规则", "wordCount", \.ruleBookInfo, \.wordCount, empty: e),
                rule("最新章节规则", "lastChapter", \.ruleBookInfo, \.lastChapter, empty: e),
                rule("简介规则", "intro", \.ruleBookInfo, \.intro, empty: e),
                rule("封面规则", "coverUrl", \.ruleBookInfo, \.coverUrl, empty: e),
                rule("目录 URL 规则", "tocUrl", \.ruleBookInfo, \.tocUrl, empty: e),
                rule("允许修改书名作者", "canReName", \.ruleBookInfo, \.canReName, empty: e),
                rule("下载 URL 规则", "downloadUrls", \.ruleBookInfo, \.downloadUrls, empty: e),
            ]
        case .toc:
            let e = TocRule()
            return [
                rule("更新之前 JS", "preUpdateJs", \.ruleToc, \.preUpdateJs, empty: e),
                rule("目录列表规则", "chapterList", \.ruleToc, \.chapterList, empty: e),
                rule("章节名称规则", "chapterName", \.ruleToc, \.chapterName, empty: e),
                rule("章节 URL 规则", "chapterUrl", \.ruleToc, \.chapterUrl, empty: e),
                rule("格式化规则", "formatJs", \.ruleToc, \.formatJs, empty: e),
                rule("Volume 标识", "isVolume", \.ruleToc, \.isVolume, empty: e),
                rule("章节信息", "updateTime", \.ruleToc, \.updateTime, empty: e),
                rule("VIP 标识", "isVip", \.ruleToc, \.isVip, empty: e),
                rule("购买标识", "isPay", \.ruleToc, \.isPay, empty: e),
                rule("目录下一页规则", "nextTocUrl", \.ruleToc, \.nextTocUrl, empty: e),
            ]
        case .content:
            let e = ContentRule()
            return [
                rule("正文规则", "content", \.ruleContent, \.content, empty: e),
                rule("正文下一页 URL 规则", "nextContentUrl", \.ruleContent, \.nextContentUrl, empty: e),
                rule("副文规则", "subContent", \.ruleContent, \.subContent, empty: e),
                rule("替换规则", "replaceRegex", \.ruleContent, \.replaceRegex, empty: e),
                rule("章节名称规则", "title", \.ruleContent, \.title, empty: e),
                rule("资源正则", "sourceRegex", \.ruleContent, \.sourceRegex, empty: e),
                rule("图片样式", "imageStyle", \.ruleContent, \.imageStyle, empty: e),
                rule("图片解密", "imageDecode", \.ruleContent, \.imageDecode, empty: e),
                rule("WebView JS", "webJs", \.ruleContent, \.webJs, empty: e),
                rule("购买操作", "payAction", \.ruleContent, \.payAction, empty: e),
                rule("回调操作", "callBackJs", \.ruleContent, \.callBackJs, empty: e),
            ]
        }
    }

    // MARK: 保存

    private func save() {
        var s = draft
        s.bookSourceUrl = s.bookSourceUrl.trimmingCharacters(in: .whitespacesAndNewlines)
        s.bookSourceName = s.bookSourceName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.bookSourceUrl.isEmpty else { error = "源 URL 不能为空"; tab = .base; return }
        guard !s.bookSourceName.isEmpty else { error = "源名称不能为空"; tab = .base; return }
        if s.bookSourceUrl != original?.bookSourceUrl,
           store.sources.contains(where: { $0.bookSourceUrl == s.bookSourceUrl }) {
            error = "已存在相同源 URL 的书源"; tab = .base; return
        }
        s.lastUpdateTime = Int64(Date().timeIntervalSince1970 * 1000)
        store.saveEditedSource(s, replacing: original?.bookSourceUrl)
        dismiss()
    }
}
