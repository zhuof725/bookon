import SwiftUI

/// 书源发现规则里的控件行，两页共用（书源发现页 / 选择分类页）。
///
/// 参考图里这几行是：左边标题、右边「当前值 + 上下箭头」的卡片行；
/// 关键词这类 text 控件是「标题 + 右对齐输入框」；搜索/刷新/登录是胶囊按钮。
/// 三类控件都要显示——书山聚合的脚本把这三种混在同一个数组里返回。
struct SourceControlRow: View {
    @ThemePalette private var palette
    let control: SourceDiagnostics.ExploreKind
    /// 当前值（下拉/输入框共用）
    @Binding var value: String
    /// 值变化后要做什么（执行 action、重取分类）
    var onChange: (String) -> Void
    /// 按钮类控件点一下要做什么；按钮自己不带值。
    var onTap: (() -> Void)? = nil
    /// 输入框是否禁用（比如正在切书源）
    var disabled: Bool = false

    var body: some View {
        switch (control.type ?? "").lowercased() {
        case "select" where !(control.chars ?? []).isEmpty:
            selectRow
        case "text":
            textRow
        case "button":
            buttonRow
        default:
            EmptyView()
        }
    }

    // MARK: 下拉

    private var selectRow: some View {
        Menu {
            ForEach(control.chars ?? [], id: \.self) { option in
                Button {
                    value = option
                    onChange(option)
                } label: {
                    if value == option {
                        Label(option, systemImage: "checkmark")
                    } else {
                        Text(option)
                    }
                }
            }
        } label: {
            HStack(spacing: 8) {
                Text(DiscoverCatalog.controlTitle(control.title))
                    .appFont(.system(size: 15))
                    .foregroundStyle(palette.primary)
                    .lineLimit(1)
                Spacer(minLength: 6)
                Text(value)
                    .appFont(.system(size: 15))
                    .foregroundStyle(palette.secondary)
                    .lineLimit(1)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(palette.secondary)
            }
            .contentShape(Rectangle())
        }
        .accessibilityIdentifier("source.control.select.\(control.title)")
    }

    // MARK: 输入

    private var textRow: some View {
        HStack(spacing: 8) {
            Text(DiscoverCatalog.controlTitle(control.title))
                .appFont(.system(size: 15))
                .foregroundStyle(palette.primary)
                .lineLimit(1)
            Spacer(minLength: 6)
            TextField("", text: $value, prompt: Text(promptText)
                .foregroundColor(palette.secondary))
                .appFont(.system(size: 15))
                .multilineTextAlignment(.trailing)
                .submitLabel(.search)
                .disabled(disabled)
                .onSubmit { onChange(value) }
                .accessibilityIdentifier("source.control.text.\(control.title)")
        }
    }

    /// 输入框的提示语：书源标题常带「书名/作者」，取斜杠后的说明。
    private var promptText: String {
        let raw = control.title
        if let range = raw.range(of: "/") {
            return String(raw[range.upperBound...]).trimmingCharacters(in: .whitespaces)
        }
        return "输入关键词"
    }

    // MARK: 按钮

    private var buttonRow: some View {
        Button {
            onTap?()
        } label: {
            HStack(spacing: 6) {
                Text(DiscoverCatalog.controlTitle(control.title))
                    .appFont(.system(size: 15))
                    .foregroundStyle(palette.primary)
                Spacer(minLength: 6)
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(palette.secondary.opacity(0.6))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .accessibilityIdentifier("source.control.button.\(control.title)")
    }
}
