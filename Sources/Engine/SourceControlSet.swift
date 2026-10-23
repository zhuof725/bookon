import Foundation

/// 书源发现控件（text / select / button）的读写与执行，两个页面共用。
///
/// 书源脚本把控件和分类混在同一个数组里返回，控件项靠 `type` 区分；
/// 改控件时要先执行它的 `action`（脚本会把配置写回书源变量），
/// 再重新读一遍分类，页面才会变成新的一组。
struct SourceControlSet {
    /// 下拉控件（有选项才算）
    var selects: [SourceDiagnostics.ExploreKind] = []
    /// 输入控件
    var texts: [SourceDiagnostics.ExploreKind] = []
    /// 按钮控件
    var buttons: [SourceDiagnostics.ExploreKind] = []
    /// 各控件的当前值（下拉的当前项、输入框的内容）
    var values: [String: String] = [:]

    var isEmpty: Bool { selects.isEmpty && texts.isEmpty && buttons.isEmpty }

    init(kinds: [SourceDiagnostics.ExploreKind] = []) {
        selects = []
        texts = []
        buttons = []
        values = [:]
        var seen = Set<String>()
        for kind in kinds {
            let type = (kind.type ?? "").lowercased()
            guard !type.isEmpty else { continue }
            guard !DiscoverCatalog.isDecorativeControlTitle(kind.title) else { continue }
            // 书源脚本可能把同一组控件拼两次
            guard seen.insert("\(type)#\(kind.title)").inserted else { continue }
            switch type {
            case "select":
                guard !(kind.chars ?? []).isEmpty else { continue }
                selects.append(kind)
                values[kind.title] = kind.defaultValue
                    ?? kind.chars?.first
                    ?? ""
            case "text":
                texts.append(kind)
                values[kind.title] = kind.defaultValue ?? ""
            case "button":
                buttons.append(kind)
            default:
                break
            }
        }
    }

    /// 关键词输入框的内容（按钮触发搜索时用得上）。
    var keyword: String {
        guard let first = texts.first else { return "" }
        return values[first.title] ?? ""
    }

    /// 执行一个控件的 action。返回脚本想打开的界面（登录 / 书源内搜索）。
    static func apply(_ control: SourceDiagnostics.ExploreKind,
                      value: String,
                      allValues: [String: String],
                      source: BookSource) -> SourceUiAction? {
        guard let action = control.action, !action.isEmpty else { return nil }
        var info = allValues
        info[control.title] = value
        return SourceDiagnostics.applyExploreControl(source: source, action: action, info: info)
    }

    /// 控件是不是「刷新分类」这类不需要重拉配置的操作。
    static func isRefreshOnly(_ control: SourceDiagnostics.ExploreKind) -> Bool {
        guard let action = control.action else { return false }
        return action.contains("refreshExplore") && !action.contains("setConfigs")
    }
}
