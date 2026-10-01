//
//  AnalyzeByJSonPath.swift
//  LegadoBookSource
//
//  对应 Kotlin: model/analyzeRule/AnalyzeByJSonPath.kt（172 行）
//
//  依赖 RuleAnalyzer 的 splitRule / innerRule / reSetPos / elementsType。
//  JSONPath 底层通过 JSONPathEvaluator 协议注入，默认用 DefaultJSONPathEvaluator。
//
//  语义对齐 Kotlin（异常被吞掉后返回空字符串/空数组/nil，行为不变）：
//   - getString：内嵌 {$.rule} 优先；无内嵌则 ctx.read；List 用 "\n" 拼接；否则 toString；
//     组合 && / ||（|| 短路），textList 用 "\n" 拼接。
//   - getStringList：内嵌 {$.rule} 优先；List 逐个 toString；组合 && / || / %%（%% 交错）。
//   - getObject：ctx.read（Kotlin 直接返回 Any，不吞异常）。
//   - getList：ctx.read<ArrayList<Any>>；组合 && / || / %%。异常被吞，返回累积结果。
//
//  异常语义（本轮收尾修正）：
//   - Kotlin 里 splitRule 不在 try 内，其异常（括号不平衡 / 越界）会向上传播；因此
//     getString / getStringList / getList / getObject 均标 throws，把 RuleAnalyzer 的
//     RuleEngineError 向上传播（不再崩溃）。
//   - Kotlin 里被 catch 吞掉的地方（ctx.read 读取失败）保持吞掉，并记入可选的
//     RuleEngineDiagnostics（默认关闭），不影响返回值。
//

import Foundation

public final class AnalyzeByJSonPath {

    private let ctx: JSONPathEvaluator
    private let diagnostics: RuleEngineDiagnostics?

    /// 对应 Kotlin: companion object fun parse(json: Any): ReadContext
    /// 这里接受 JSONValue 或 JSON 字符串。
    public static func parse(_ json: JSONValue) -> JSONValue { json }
    public static func parse(_ json: String) -> JSONValue { JSONValue.parse(json) ?? .null }

    /// 用 JSONValue 构造。
    public init(_ json: JSONValue,
                evaluatorType: JSONPathEvaluator.Type = DefaultJSONPathEvaluator.self,
                diagnostics: RuleEngineDiagnostics? = nil) {
        self.ctx = evaluatorType.init(root: json)
        self.diagnostics = diagnostics
    }

    /// 用 JSON 字符串构造（对应 Kotlin AnalyzeByJSonPath(json: String)）。
    /// 容错版：JSON 解析失败时不再静默变 null，而是**记录到 diagnostics**（若提供）后
    /// 以空根（.null）继续，后续读取返回空值。若要「解析失败即抛异常」（对齐 Jayway），
    /// 请改用 `init(validatingJSON:)`。
    public convenience init(_ jsonString: String,
                            evaluatorType: JSONPathEvaluator.Type = DefaultJSONPathEvaluator.self,
                            diagnostics: RuleEngineDiagnostics? = nil) {
        let parsed = JSONValue.parse(jsonString)
        if parsed == nil {
            diagnostics?.record(source: "AnalyzeByJSonPath.init",
                                rule: String(jsonString.prefix(200)),
                                message: "JSON 解析失败，已按空根处理")
        }
        self.init(parsed ?? .null, evaluatorType: evaluatorType, diagnostics: diagnostics)
    }

    /// 严格版：JSON 解析失败时抛 `RuleEngineError.invalidJSON`（对齐 Jayway 解析失败抛异常）。
    /// - Throws: RuleEngineError.invalidJSON
    public convenience init(validatingJSON jsonString: String,
                            evaluatorType: JSONPathEvaluator.Type = DefaultJSONPathEvaluator.self,
                            diagnostics: RuleEngineDiagnostics? = nil) throws {
        guard let parsed = JSONValue.parse(jsonString) else {
            diagnostics?.record(source: "AnalyzeByJSonPath.init(validatingJSON:)",
                                rule: String(jsonString.prefix(200)),
                                message: "JSON 解析失败")
            throw RuleEngineError.invalidJSON(String(jsonString.prefix(200)))
        }
        self.init(parsed, evaluatorType: evaluatorType, diagnostics: diagnostics)
    }

    // MARK: - getString

    /// 对应 Kotlin: fun getString(rule: String): String?
    /// - Throws: RuleEngineError（切分器括号不平衡/越界，对齐 Kotlin 向上传播）。
    public func getString(_ rule: String) throws -> String? {
        if rule.isEmpty { return nil }
        var result: String
        let ruleAnalyzes = RuleAnalyzer(rule, code: true)  // 设置平衡组为代码平衡
        let rules = try ruleAnalyzes.splitRule("&&", "||")

        if rules.count == 1 {
            ruleAnalyzes.reSetPos()  // 将 pos 重置为 0，复用解析器
            // 回调直接 try 递归 getString：抛错会立即中断 innerRule 并向上传播（对齐 Kotlin）。
            result = try ruleAnalyzes.innerRule("{$.") { try self.getString($0) }

            if result.isEmpty {  // st 为空，表明无成功替换的内嵌规则
                do {
                    let ob = try ctx.read(rule)
                    switch ob {
                    case .list(let list):
                        result = list.map { $0.jaywayStringValue }.joined(separator: "\n")
                    case .single(let v):
                        switch v {
                        case .array(let a):
                            // Jayway definite 也可能命中一个数组值；对齐 "is List -> joinToString"
                            result = a.map { $0.jaywayStringValue }.joined(separator: "\n")
                        default:
                            result = v.jaywayStringValue
                        }
                    }
                } catch {
                    diagnostics?.record(source: "AnalyzeByJSonPath.getString", rule: rule, error: error)
                }
            }
            return result
        } else {
            var textList: [String] = []
            for rl in rules {
                let temp = try getString(rl)
                if let temp = temp, !temp.isEmpty {
                    textList.append(temp)
                    if ruleAnalyzes.elementsType == "||" {
                        break
                    }
                }
            }
            return textList.joined(separator: "\n")
        }
    }

    // MARK: - getStringList

    /// 对应 Kotlin: internal fun getStringList(rule: String): List<String>
    /// - Throws: RuleEngineError（切分器错误，对齐 Kotlin 向上传播）。
    public func getStringList(_ rule: String) throws -> [String] {
        var result: [String] = []
        if rule.isEmpty { return result }
        let ruleAnalyzes = RuleAnalyzer(rule, code: true)  // 设置平衡组为代码平衡
        let rules = try ruleAnalyzes.splitRule("&&", "||", "%%")

        if rules.count == 1 {
            ruleAnalyzes.reSetPos()  // 将 pos 重置为 0，复用解析器
            // 回调直接 try 递归 getString：抛错立即中断并向上传播（对齐 Kotlin）。
            let st = try ruleAnalyzes.innerRule("{$.") { try self.getString($0) }
            if st.isEmpty {  // st 为空，表明无成功替换的内嵌规则
                do {
                    let obj = try ctx.read(rule)
                    switch obj {
                    case .list(let list):
                        for o in list { result.append(o.jaywayStringValue) }
                    case .single(let v):
                        switch v {
                        case .array(let a):
                            for o in a { result.append(o.jaywayStringValue) }
                        default:
                            result.append(v.jaywayStringValue)
                        }
                    }
                } catch {
                    diagnostics?.record(source: "AnalyzeByJSonPath.getStringList", rule: rule, error: error)
                }
            } else {
                result.append(st)
            }
            return result
        } else {
            var results: [[String]] = []
            for rl in rules {
                let temp = try getStringList(rl)
                if !temp.isEmpty {
                    results.append(temp)
                    if !temp.isEmpty && ruleAnalyzes.elementsType == "||" {
                        break
                    }
                }
            }
            if results.count > 0 {
                if ruleAnalyzes.elementsType == "%%" {
                    for i in results[0].indices {
                        for temp in results {
                            if i < temp.count {
                                result.append(temp[i])
                            }
                        }
                    }
                } else {
                    for temp in results {
                        result.append(contentsOf: temp)
                    }
                }
            }
            return result
        }
    }

    // MARK: - getObject

    /// 对应 Kotlin: internal fun getObject(rule: String): Any
    /// Kotlin 直接 ctx.read(rule)（不吞异常）。返回 JSONValue（对应 Any）。
    /// - Throws: 路径不存在等（对齐 Jayway/Kotlin 不捕获的语义）。
    public func getObject(_ rule: String) throws -> JSONValue {
        switch try ctx.read(rule) {
        case .single(let v): return v
        case .list(let l): return .array(l)
        }
    }

    // MARK: - getList

    /// 对应 Kotlin: internal fun getList(rule: String): ArrayList<Any>?
    /// - Throws: RuleEngineError（切分器错误，对齐 Kotlin 向上传播）。
    public func getList(_ rule: String) throws -> [JSONValue]? {
        var result: [JSONValue] = []
        if rule.isEmpty { return result }
        let ruleAnalyzes = RuleAnalyzer(rule, code: true)  // 设置平衡组为代码平衡
        let rules = try ruleAnalyzes.splitRule("&&", "||", "%%")
        if rules.count == 1 {
            do {
                // 对应 Kotlin: return it.read<ArrayList<Any>>(rules[0])
                switch try ctx.read(rules[0]) {
                case .list(let l):
                    return l
                case .single(let v):
                    if case .array(let a) = v {
                        return a
                    }
                    // 非数组 -> Kotlin 的 ClassCastException 会被 catch 吞掉，落到函数末尾返回累积的空 result。
                    throw JSONPathError.invalidPath("非列表结果: \(rule)")
                }
            } catch {
                diagnostics?.record(source: "AnalyzeByJSonPath.getList", rule: rule, error: error)
            }
        } else {
            var results: [[JSONValue]] = []
            for rl in rules {
                let temp = try getList(rl)
                if let temp = temp, !temp.isEmpty {
                    results.append(temp)
                    if !temp.isEmpty && ruleAnalyzes.elementsType == "||" {
                        break
                    }
                }
            }
            if results.count > 0 {
                if ruleAnalyzes.elementsType == "%%" {
                    for i in 0..<results[0].count {
                        for temp in results {
                            if i < temp.count {
                                result.append(temp[i])
                            }
                        }
                    }
                } else {
                    for temp in results {
                        result.append(contentsOf: temp)
                    }
                }
            }
        }
        return result
    }
}
