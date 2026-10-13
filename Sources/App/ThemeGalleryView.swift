import SwiftUI

/// Picking a template creates only a draft. The editor owns persistence.
struct ThemeGalleryView: View {
    let onCancel: () -> Void
    let onSelect: (AppTheme) -> Void

    @State private var searchText = ""
    @State private var category: GalleryCategory = .all
    @FocusState private var searchFocused: Bool
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    init(onCancel: @escaping () -> Void = {}, onSelect: @escaping (AppTheme) -> Void = { _ in }) {
        self.onCancel = onCancel
        self.onSelect = onSelect
    }

    private enum GalleryCategory: String, CaseIterable, Identifiable {
        case all, solid, gradient
        var id: String { rawValue }
        var title: String {
            switch self {
            case .all: return "全部"
            case .solid: return "纯色"
            case .gradient: return "渐变"
            }
        }
        var style: AppThemeBackgroundStyle? {
            switch self {
            case .all: return nil
            case .solid: return .solid
            case .gradient: return .gradient
            }
        }
    }

    private var templates: [AppTheme] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return AppTheme.templates.filter {
            (category.style == nil || $0.backgroundStyle == category.style)
                && (query.isEmpty || $0.name.localizedStandardContains(query))
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text("从模板开始")
                        .appFont(.headline)
                    Text("同时查看浅色与深色。选取后可编辑，保存前不会更改当前主题。")
                        .appFont(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    searchField
                    categoryPicker
                    if templates.isEmpty {
                        VStack(spacing: 8) {
                            Image(systemName: "magnifyingglass")
                                .font(.system(size: 24))
                                .accessibilityHidden(true)
                            Text("没有找到匹配的模板")
                                .appFont(.headline)
                            Text("试试其他名称或分类。")
                                .appFont(.footnote)
                        }
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(24)
                        .modifier(SettingsGlassSurface())
                    } else {
                        LazyVStack(spacing: 12) {
                            ForEach(templates) { template in
                                Button {
                                    searchFocused = false
                                    onSelect(template.draft())
                                } label: {
                                    ThemeSplitPreview(theme: template, isSelected: false)
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("模板 \(template.name)")
                                .accessibilityHint("创建草稿并进入编辑，不会立即应用")
                                .accessibilityIdentifier("theme.template.\(template.id)")
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 28)
            }
            .scrollIndicators(.hidden)
            .scrollDismissesKeyboard(.interactively)
            .background(ThemeHubSurface.canvas.ignoresSafeArea())
            .navigationTitle("选择模板")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        searchFocused = false
                        onCancel()
                    } label: {
                        Text("取消")
                            .appFont(.body)
                            .frame(minWidth: 44, minHeight: 44)
                    }
                    .accessibilityIdentifier("theme.editor.cancel")
                }
            }
        }
        .foregroundStyle(.primary)
        .tint(.primary)
        .modifier(AppTypographyRoot())
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            TextField("搜索 \(AppTheme.templates.count) 个模板", text: $searchText)
                .appFont(.subheadline)
                .textInputAutocapitalization(.never)
                .disableAutocorrection(true)
                .submitLabel(.search)
                .focused($searchFocused)
                .onSubmit { searchFocused = false }
                .accessibilityLabel("搜索模板")
                .accessibilityIdentifier("theme.template.search")
            if !searchText.isEmpty {
                Button { searchText = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(.secondary)
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("清除搜索")
            }
        }
        .padding(.leading, 13)
        .padding(.trailing, searchText.isEmpty ? 13 : 0)
        .padding(.vertical, 2)
        .frame(minHeight: 46)
        .appGlass(in: RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 13).strokeBorder(ThemeHubSurface.border, lineWidth: 0.5))
    }

    private var categoryPicker: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(spacing: 3)) : AnyLayout(HStackLayout(spacing: 3))
        return layout {
            ForEach(GalleryCategory.allCases) { item in
                Button { category = item } label: {
                    Text(item.title)
                        .appFont(.subheadline.weight(category == item ? .semibold : .regular))
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(category == item ? ThemeHubSurface.card : .clear,
                                    in: RoundedRectangle(cornerRadius: 9))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("theme.template.filter.\(item.rawValue)")
                .accessibilityAddTraits(category == item ? .isSelected : [])
            }
        }
        .padding(3)
        .appGlass(in: RoundedRectangle(cornerRadius: 20))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("模板分类")
    }
}
