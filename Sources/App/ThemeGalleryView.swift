import SwiftUI

/// Full-screen template picker. Choosing a template only creates an in-memory
/// draft; persistence is deliberately owned by ThemeEditorView's save action.
struct ThemeGalleryView: View {
    let onCancel: () -> Void
    let onSelect: (AppTheme) -> Void

    @Environment(\.colorScheme) private var colorScheme
    @State private var category: GalleryCategory = .all
    @State private var selectedScheme: ColorScheme = .light

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
        let style = category.style
        return AppTheme.templates.filter { style == nil || $0.backgroundStyle == style }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    intro
                    categoryPicker
                    previewModePicker
                    templateGrid
                }
                .padding(.horizontal, 18)
                .padding(.top, 16)
                .padding(.bottom, 34)
            }
            .scrollIndicators(.hidden)
            .background(galleryBackground.ignoresSafeArea())
            .navigationTitle("添加新主题")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        onCancel()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .bold))
                            .frame(width: 44, height: 44)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("关闭")
                    .accessibilityIdentifier("theme.editor.cancel")
                }
            }
        }
        .onAppear { selectedScheme = colorScheme }
        .modifier(AppTypographyRoot())
    }

    private var galleryBackground: some View {
        Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(white: 0.055, alpha: 1)
                : UIColor(white: 0.965, alpha: 1)
        })
    }

    private var intro: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("从一套气质开始")
                .appFont(.title2.weight(.bold))
            Text("选一个喜欢的基础配色，下一步可以调整名称、明暗和颜色。")
                .appFont(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var categoryPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 9) {
                ForEach(GalleryCategory.allCases) { item in
                    Button {
                        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) {
                            category = item
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Circle()
                                .fill(categoryColor(item))
                                .frame(width: 8, height: 8)
                            Text(item.title)
                                .appFont(.subheadline.weight(.semibold))
                        }
                        .padding(.horizontal, 15)
                        .frame(minHeight: 42)
                        .background(category == item ? categoryColor(item).opacity(0.18) : Color.primary.opacity(0.06), in: Capsule())
                        .overlay(Capsule().stroke(category == item ? categoryColor(item).opacity(0.72) : Color.primary.opacity(0.12), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(category == item ? .isSelected : [])
                }
            }
        }
        .accessibilityLabel("主题类型")
    }

    private var previewModePicker: some View {
        HStack(spacing: 10) {
            Text("预览")
                .appFont(.subheadline.weight(.semibold))
            Spacer()
            ForEach([ColorScheme.light, ColorScheme.dark], id: \.self) { scheme in
                Button {
                    selectedScheme = scheme
                } label: {
                    Image(systemName: scheme == .light ? "sun.max.fill" : "moon.fill")
                        .font(.system(size: 15, weight: .semibold))
                        .frame(width: 42, height: 38)
                        .background(selectedScheme == scheme ? Color.primary.opacity(0.13) : .clear, in: Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(scheme == .light ? "浅色预览" : "深色预览")
            }
        }
    }

    private var templateGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 13), GridItem(.flexible(), spacing: 13)], spacing: 18) {
            ForEach(templates) { template in
                Button {
                    onSelect(template.draft())
                } label: {
                    VStack(alignment: .leading, spacing: 9) {
                        ThemePreviewCard(theme: template, scheme: selectedScheme, isSelected: false)
                            .frame(height: 278)
                        HStack(spacing: 6) {
                            Text(template.name)
                                .appFont(.subheadline.weight(.semibold))
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                            Spacer(minLength: 0)
                            Image(systemName: template.backgroundStyle == .gradient ? "circle.lefthalf.filled" : "circle.fill")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(categoryColor(template.backgroundStyle))
                        }
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("模板 \(template.name)")
                .accessibilityIdentifier("theme.template.\(template.id)")
            }
        }
    }

    private func categoryColor(_ item: GalleryCategory) -> Color {
        switch item {
        case .all: return .blue
        case .solid: return .orange
        case .gradient: return .purple
        }
    }

    private func categoryColor(_ style: AppThemeBackgroundStyle) -> Color {
        style == .solid ? .orange : .purple
    }

    private var reduceMotion: Bool {
        #if os(iOS)
        return UIAccessibility.isReduceMotionEnabled
        #else
        return false
        #endif
    }
}
