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
                    HStack(alignment: .center, spacing: 8) {
                        categoryPicker
                        previewModePicker
                    }
                    templateGrid
                }
                .padding(.horizontal, 18)
                .padding(.top, 16)
                .padding(.bottom, 34)
            }
            .scrollIndicators(.hidden)
            .background(galleryBackground.ignoresSafeArea())
            .navigationTitle("选择主题")
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
                            Text(item.title)
                                .appFont(.subheadline.weight(.semibold))
                        }
                        .padding(.horizontal, 12)
                        .frame(minHeight: 42)
                        .background(category == item ? Color.primary.opacity(0.10) : .clear, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(category == item ? .isSelected : [])
                }
            }
        }
        .accessibilityLabel("主题类型")
    }

    private var previewModePicker: some View {
        Button {
            selectedScheme = selectedScheme == .light ? .dark : .light
        } label: {
            Image(systemName: selectedScheme == .light ? "sun.max" : "moon")
                .font(.system(size: 17, weight: .medium))
                .frame(width: 44, height: 44)
                .background(Color.primary.opacity(0.05), in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(selectedScheme == .light ? "切换深色预览" : "切换浅色预览")
    }

    private var templateGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 16), GridItem(.flexible(), spacing: 16)], spacing: 18) {
            ForEach(templates) { template in
                Button {
                    onSelect(template.draft())
                } label: {
                    VStack(alignment: .leading, spacing: 9) {
                        ThemePreviewCard(theme: template, scheme: selectedScheme, isSelected: false)
                            .frame(height: 260)
                        HStack(spacing: 6) {
                            Text(template.name)
                                .appFont(.subheadline.weight(.semibold))
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                            Spacer(minLength: 0)
                            Circle().fill(AppThemeColor.color(template.swatches(for: selectedScheme).accent))
                                .frame(width: 10, height: 10)
                                .accessibilityHidden(true)
                        }
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("模板 \(template.name)")
                .accessibilityIdentifier("theme.template.\(template.id)")
            }
        }
    }

    private var reduceMotion: Bool {
        #if os(iOS)
        return UIAccessibility.isReduceMotionEnabled
        #else
        return false
        #endif
    }
}
