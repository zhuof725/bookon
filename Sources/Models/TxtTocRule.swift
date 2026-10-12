import Foundation

/// TXT headings only; unrelated to website book-source ruleToc or EPUB navigation.
struct TxtTocRule: Codable, Equatable, Identifiable {
    let id: String
    var name: String
    var pattern: String
    var isBuiltIn: Bool

    static let builtIns: [TxtTocRule] = {
        let n = "0-9一二三四五六七八九十百千万零〇○两"
        let c = "一二三四五六七八九十百千万零〇○两"
        let specifications: [(String, String, String)] = [
            ("chapter", "第 X 章 / 节 / 回", "^\\s*第\\s*[\(n)]+\\s*[章节回集卷部篇]\\s*.{0,30}$"),
            ("episode", "第 X 话 / 幕", "^\\s*第\\s*[\(n)]+\\s*[话幕]\\s*.{0,30}$"),
            ("volume-chapter", "卷 + 章组合", "^\\s*第\\s*[\(n)]+\\s*卷\\s*第\\s*[\(n)]+\\s*[章节回]\\s*.{0,30}$"),
            ("preface", "序章 / 楔子 / 尾声", #"^\s*(序章|楔子|引子|前言|后记|尾声|终章|番外)\s*.{0,30}$"#),
            ("chapter-en", "Chapter N", #"^\s*Chapter\s*\d+.*$"#),
            ("chapter-upper", "CHAPTER N", #"^\s*CHAPTER\s*\d+.*$"#),
            ("roman", "罗马数字标题", #"^\s*(Chapter\s*)?[IVXLCDM]{1,8}[.、．:]\s*.+$"#),
            ("number", "数字.标题", #"^\s*\d+[.、．]\s*.+$"#),
            ("chinese-number", "中文数字.标题", "^\\s*[\(c)]{1,8}[.、．]\\s*.+$"),
            ("bracket-chapter", "【第 X 章】", "^\\s*[\\[【（(]第\\s*[\(n)]+\\s*[章节回集卷部篇][\\]】）)]\\s*.{0,30}$"),
            ("bracket-title", "【标题】", #"^\s*【[^】]+】\s*$"#),
            ("volume", "第 X 卷", "^\\s*(?:第\\s*[\(n)]+\\s*卷|卷\\s*[\(n)]+).*$"),
            ("number-space", "序号 + 空格 + 标题", #"^\s*\d+\s+\S.{0,30}$"#),
            ("equals", "===分隔符===", #"^\s*[=＝]{3,}.*$"#),
            ("dashes", "---分隔符---", #"^\s*[-－—]{3,}.*$"#)
        ]
        return specifications.map { TxtTocRule(id: "builtin." + $0.0, name: $0.1, pattern: $0.2, isBuiltIn: true) }
    }()

    static func validationMessage(name: String, pattern: String) -> String? {
        if name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return "请输入规则名称" }
        if name.count > 60 { return "规则名称不能超过 60 字" }
        if pattern.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return "请输入正则表达式" }
        if pattern.count > 512 { return "正则表达式不能超过 512 个字符" }
        do {
            let expression = try NSRegularExpression(pattern: pattern)
            if expression.firstMatch(in: "", range: NSRange(location: 0, length: 0)) != nil {
                return "规则不能匹配空行，请使用能识别标题文字的表达式"
            }
        } catch { return "正则表达式无效：\(error.localizedDescription)" }
        return nil
    }
}

/// Snapshot compiled once per import; all matches are whole candidate lines.
/// No matches cross line boundaries. A heading matched by several rules splits once.
struct TxtTocMatcher {
    private let expressions: [NSRegularExpression]
    init(rules: [TxtTocRule]) {
        expressions = rules.compactMap { try? NSRegularExpression(pattern: $0.pattern) }
    }
    func isHeading(_ line: String) -> Bool {
        let candidate = line.trimmingCharacters(in: .whitespaces)
        guard !candidate.isEmpty, candidate.utf16.count <= 160 else { return false }
        let full = NSRange(location: 0, length: (candidate as NSString).length)
        return expressions.contains { expression in
            var matched = false
            let started = Date.timeIntervalSinceReferenceDate
            expression.enumerateMatches(in: candidate, options: [.reportProgress], range: full) { result, _, stop in
                // Cooperative cancellation bounds pathological custom backtracking.
                if Date.timeIntervalSinceReferenceDate - started > 0.02 { stop.pointee = true; return }
                if let result {
                    matched = result.range == full && result.range.length > 0
                    stop.pointee = true
                }
            }
            return matched
        }
    }
}

/// Persist only custom rules; bundled rules remain read-only and cannot be erased.
struct TxtTocRuleRepository {
    static let storageKey = "txtTocRules.custom.v1"
    let defaults: UserDefaults
    init(defaults: UserDefaults = .standard) { self.defaults = defaults }
    func customRules() -> [TxtTocRule] {
        guard let data = defaults.data(forKey: Self.storageKey),
              let rules = try? JSONDecoder().decode([TxtTocRule].self, from: data) else { return [] }
        var ids = Set<String>()
        return rules.filter {
            !$0.isBuiltIn && !$0.id.hasPrefix("builtin.") && ids.insert($0.id).inserted
                && TxtTocRule.validationMessage(name: $0.name, pattern: $0.pattern) == nil
        }
    }
    var rules: [TxtTocRule] { TxtTocRule.builtIns + customRules() }
    func save(_ custom: [TxtTocRule]) throws {
        let valid = custom.filter { !$0.isBuiltIn && !$0.id.hasPrefix("builtin.") }
        guard valid.count <= 50 else { throw RuleError.invalid("自定义规则最多 50 条") }
        for rule in valid {
            if let message = TxtTocRule.validationMessage(name: rule.name, pattern: rule.pattern) { throw RuleError.invalid(message) }
        }
        let data = try JSONEncoder().encode(valid)
        defaults.set(data, forKey: Self.storageKey)
    }
    enum RuleError: LocalizedError {
        case invalid(String)
        var errorDescription: String? { if case .invalid(let message) = self { return message }; return nil }
    }
}
