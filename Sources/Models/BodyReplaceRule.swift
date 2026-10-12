import Foundation

struct BodyReplaceRule: Codable, Identifiable, Equatable {
    let id: String
    var name: String
    var pattern: String
    var replacement: String
    var isRegex: Bool
    var enabled: Bool

    var validationMessage: String? {
        do { _ = try compiledExpression(); return nil }
        catch { return error.localizedDescription }
    }

    fileprivate func compiledExpression() throws -> NSRegularExpression {
        func invalid(_ message: String) -> BodyReplaceRepository.RuleError { .invalid(message) }
        guard !id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw invalid("规则标识不能为空") }
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw invalid("请输入规则名称") }
        guard name.count <= 60 else { throw invalid("名称不能超过 60 字") }
        guard !pattern.isEmpty else { throw invalid("请输入查找内容") }
        guard pattern.utf16.count <= 512 else { throw invalid("查找内容不能超过 512 个 UTF-16 单位") }
        guard replacement.utf16.count <= 2000 else { throw invalid("替换内容不能超过 2000 个 UTF-16 单位") }
        do { return try NSRegularExpression(pattern: isRegex ? pattern : NSRegularExpression.escapedPattern(for: pattern)) }
        catch { throw invalid("正则表达式无效：\(error.localizedDescription)") }
    }
}

struct BodyReplaceRepository {
    static let storageKey = "bodyReplaceRules.v1"
    let defaults: UserDefaults
    init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    func rules() -> [BodyReplaceRule] {
        guard let data = defaults.data(forKey: Self.storageKey),
              let decoded = try? JSONDecoder().decode([BodyReplaceRule].self, from: data) else { return [] }
        var ids = Set<String>()
        return Array(decoded.prefix(50)).filter { $0.validationMessage == nil && ids.insert($0.id).inserted }
    }

    func save(_ rules: [BodyReplaceRule]) throws {
        guard rules.count <= 50 else { throw RuleError.invalid("正文替换规则最多 50 条") }
        var ids = Set<String>()
        for rule in rules {
            if let message = rule.validationMessage { throw RuleError.invalid(message) }
            guard ids.insert(rule.id).inserted else { throw RuleError.invalid("规则标识不能重复") }
        }
        defaults.set(try JSONEncoder().encode(rules), forKey: Self.storageKey)
    }

    enum RuleError: LocalizedError {
        case invalid(String)
        var errorDescription: String? { if case .invalid(let message) = self { return message }; return nil }
    }
}

/// Immutable reader-session snapshot. Caller supplies only a single body paragraph,
/// never titles, image/URL blocks, originals or cached content. No persistence here.
struct BodyReplaceEngine {
    private struct Compiled {
        let expression: NSRegularExpression
        let template: String
        let references: [Int]
        let templateLength: Int
    }
    private let compiled: [Compiled]

    init(rules: [BodyReplaceRule]) {
        compiled = rules.prefix(50).compactMap { rule in
            guard rule.enabled, let expression = try? rule.compiledExpression() else { return nil }
            let template = rule.isRegex ? rule.replacement : NSRegularExpression.escapedTemplate(for: rule.replacement)
            // Preflight capture expansion before Foundation allocates the replacement.
            let units = Array(template.utf16)
            var references: [Int] = [], index = 0
            while index < units.count {
                if units[index] == 92 { index += 2; continue }
                if units[index] == 36, index + 1 < units.count,
                   (48...57).contains(units[index + 1]) {
                    var group = Int(units[index + 1] - 48)
                    index += 2
                    if group <= expression.numberOfCaptureGroups {
                        while index < units.count, (48...57).contains(units[index]),
                              group * 10 + Int(units[index] - 48) <= expression.numberOfCaptureGroups {
                            group = group * 10 + Int(units[index] - 48); index += 1
                        }
                        references.append(group)
                    }
                } else { index += 1 }
            }
            return Compiled(expression: expression, template: template, references: references, templateLength: units.count)
        }
    }

    func apply(_ text: String) -> String {
        let length = text.utf16.count
        guard length <= 1_000_000 else { return text }
        // One budget for the entire chain prevents successive rules multiplying it.
        let limit = min(1_000_000, max(65_536, length * 4))
        return compiled.reduce(text) { apply($1, to: $0, limit: limit) }
    }

    private func apply(_ rule: Compiled, to text: String, limit: Int) -> String {
        let source = text as NSString
        let full = NSRange(location: 0, length: source.length)
        let output = NSMutableString(capacity: min(source.length, limit))
        let started = ProcessInfo.processInfo.systemUptime
        var cursor = 0, aborted = false
        // Cooperative ICU progress callbacks, not a preemptive hard deadline.
        rule.expression.enumerateMatches(in: text, options: [.reportProgress, .reportCompletion], range: full) { result, flags, stop in
            if ProcessInfo.processInfo.systemUptime - started >= 0.05 || flags.contains(.internalError) {
                aborted = true; stop.pointee = true; return
            }
            guard let result else { return }
            let gap = result.range.location - cursor
            var bound = rule.templateLength
            for group in rule.references {
                let range = result.range(at: group)
                if range.location != NSNotFound { bound += range.length }
            }
            guard gap >= 0, output.length + gap + bound <= limit else {
                aborted = true; stop.pointee = true; return
            }
            let replacement = rule.expression.replacementString(for: result, in: text, offset: 0, template: rule.template)
            guard output.length + gap + replacement.utf16.count <= limit else {
                aborted = true; stop.pointee = true; return
            }
            output.append(source.substring(with: NSRange(location: cursor, length: gap)))
            output.append(replacement)
            cursor = NSMaxRange(result.range)
        }
        guard !aborted, ProcessInfo.processInfo.systemUptime - started < 0.05,
              output.length + source.length - cursor <= limit else { return text }
        output.append(source.substring(from: cursor))
        return output as String
    }
}
