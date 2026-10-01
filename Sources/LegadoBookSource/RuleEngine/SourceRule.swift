//
//  SourceRule.swift
//  LegadoBookSource
//
//  对应 Kotlin AnalyzeRule.SourceRule inner class。规则类：承载单条规则的 mode、rule、
//  replaceRegex/replacement/replaceFirst、putMap，以及 {{ }}/@get/$1~$99 的参数切分与 makeUpRule 重组。
//
//  由于 Kotlin 是 inner class（持有外部 AnalyzeRule 的隐式引用，调用 evalJS/getString/get），
//  Swift 用显式 weak owner 引用表达。
//

import Foundation

public final class SourceRule {
    public internal(set) var mode: Mode
    public internal(set) var rule: String
    internal(set) var replaceRegex = ""
    internal(set) var replacement = ""
    internal(set) var replaceFirst = false
    let putMap: [String: String]

    // 参数切分（对应 Kotlin ruleParam/ruleType）
    private var ruleParam: [String] = []
    private var ruleType: [Int] = []
    private let getRuleType = -2
    private let jsRuleType = -1
    private let defaultRuleType = 0

    private weak var owner: AnalyzeRule?

    /// 对应 Kotlin: SourceRule(ruleStr, mode=Default)
    init(_ ruleStr: String, mode: Mode = .default, owner: AnalyzeRule) throws {
        self.mode = mode
        self.owner = owner
        var putMapLocal: [String: String] = [:]

        // 1. 前缀 / 模式判定（对齐 Kotlin init 的 when）
        var rule0: String
        let isJSON = owner.isJSONFlag
        if mode == .js || mode == .regex {
            rule0 = ruleStr
        } else if ruleStr.lowercased().hasPrefix("@css:") {
            self.mode = .default
            rule0 = ruleStr
        } else if ruleStr.hasPrefix("@@") {
            self.mode = .default
            rule0 = String(ruleStr.dropFirst(2))
        } else if ruleStr.lowercased().hasPrefix("@xpath:") {
            self.mode = .xPath
            rule0 = String(ruleStr.dropFirst(7))
        } else if ruleStr.lowercased().hasPrefix("@json:") {
            self.mode = .json
            rule0 = String(ruleStr.dropFirst(6))
        } else if isJSON || ruleStr.hasPrefix("$.") || ruleStr.hasPrefix("$[") {
            self.mode = .json
            rule0 = ruleStr
        } else if ruleStr.hasPrefix("/") {
            self.mode = .xPath
            rule0 = ruleStr
        } else {
            rule0 = ruleStr
        }

        // 2. 分离 put
        rule0 = owner.splitPutRule(rule0, into: &putMapLocal)
        self.putMap = putMapLocal
        self.rule = rule0

        // 3. @get / {{ }} 切分（对应 evalPattern 循环）
        try splitEval(rule0)
    }

    private func splitEval(_ rule0: String) throws {
        let ns = rule0 as NSString
        let evalMatches = AnalyzeRule.evalPattern.matches(in: rule0, range: NSRange(location: 0, length: ns.length))
        var start = 0
        if !evalMatches.isEmpty {
            let first = evalMatches[0]
            var tmp = ns.substring(with: NSRange(location: start, length: first.range.location - start))
            // 对齐 Kotlin: if (mode != Js && mode != Regex && (start==0 || !tmp.contains("##"))) mode = Regex
            if mode != .js && mode != .regex && (first.range.location == 0 || !tmp.contains("##")) {
                mode = .regex
            }
            for m in evalMatches {
                if m.range.location > start {
                    tmp = ns.substring(with: NSRange(location: start, length: m.range.location - start))
                    splitRegex(tmp)
                }
                let token = ns.substring(with: m.range)
                if token.lowercased().hasPrefix("@get:") {
                    ruleType.append(getRuleType)
                    // Kotlin: tmp.substring(6, tmp.lastIndex) —— @get:{ 后、} 前
                    let inner = String(token.dropFirst(6).dropLast())
                    ruleParam.append(inner)
                } else if token.hasPrefix("{{") {
                    ruleType.append(jsRuleType)
                    // tmp.substring(2, length-2)
                    let inner = String(token.dropFirst(2).dropLast(2))
                    ruleParam.append(inner)
                } else {
                    splitRegex(token)
                }
                start = m.range.location + m.range.length
            }
        }
        if ns.length > start {
            let tmp = ns.substring(from: start)
            splitRegex(tmp)
        }
    }

    /// 对应 Kotlin: private fun splitRegex(ruleStr) —— 拆 $\d{1,2}
    private func splitRegex(_ ruleStr: String) {
        var start = 0
        let ruleStrArray = ruleStr.components(separatedBy: "##")
        let head = ruleStrArray.first ?? ""
        let headNs = head as NSString
        let ruleStrNs = ruleStr as NSString
        let matches = AnalyzeRule.regexPattern.matches(in: head, range: NSRange(location: 0, length: headNs.length))
        if !matches.isEmpty {
            if mode != .js && mode != .regex {
                mode = .regex
            }
            for m in matches {
                if m.range.location > start {
                    let tmp = ruleStrNs.substring(with: NSRange(location: start, length: m.range.location - start))
                    ruleType.append(defaultRuleType)
                    ruleParam.append(tmp)
                }
                let token = ruleStrNs.substring(with: m.range)
                // tmp.substring(1).toInt() —— $12 -> 12
                let numStr = String(token.dropFirst())
                ruleType.append(Int(numStr) ?? defaultRuleType)
                ruleParam.append(token)
                start = m.range.location + m.range.length
            }
        }
        if ruleStrNs.length > start {
            let tmp = ruleStrNs.substring(from: start)
            ruleType.append(defaultRuleType)
            ruleParam.append(tmp)
        }
    }

    /// 对应 Kotlin: fun makeUpRule(result) —— 替换 @get/{{ }}/$n，并分离 ## 正则部分。
    func makeUpRule(_ result: RuleValue?) throws {
        guard let owner = owner else { return }
        var infoVal = ""
        if !ruleParam.isEmpty {
            var index = ruleParam.count
            while index > 0 {
                index -= 1
                let regType = ruleType[index]
                if regType > defaultRuleType {
                    // $n：从 result 列表取第 n 个
                    if case .stringList(let list)? = result, list.count > regType {
                        infoVal = list[regType] + infoVal
                    } else {
                        infoVal = ruleParam[index] + infoVal
                    }
                } else if regType == jsRuleType {
                    let param = ruleParam[index]
                    if SourceRule.isRule(param) {
                        let ruleList = try owner.getOrCreateSingleSourceRule(param)
                        let s = try owner.getString(ruleList: ruleList)
                        infoVal = s + infoVal
                    } else {
                        let jsEval = try owner.evalJS(param, result: result ?? .null)
                        switch jsEval {
                        case .null:
                            break
                        case .string(let s):
                            infoVal = s + infoVal
                        case .number(let d) where d.truncatingRemainder(dividingBy: 1) == 0:
                            infoVal = String(format: "%.0f", d) + infoVal
                        default:
                            infoVal = jsEval.stringValue + infoVal
                        }
                    }
                } else if regType == getRuleType {
                    infoVal = owner.get(ruleParam[index]) + infoVal
                } else {
                    infoVal = ruleParam[index] + infoVal
                }
            }
            rule = infoVal
        }
        // 分离 ## 正则
        let parts = rule.components(separatedBy: "##")
        rule = (parts.first ?? "").trimmingCharacters(in: .whitespaces)
        if parts.count > 1 { replaceRegex = parts[1] }
        if parts.count > 2 { replacement = parts[2] }
        if parts.count > 3 { replaceFirst = true }
    }

    /// 对应 Kotlin: private fun isRule(ruleStr): Boolean
    private static func isRule(_ ruleStr: String) -> Bool {
        return ruleStr.hasPrefix("@") || ruleStr.hasPrefix("$.") || ruleStr.hasPrefix("$[") || ruleStr.hasPrefix("//")
    }

    public func getParamSize() -> Int { ruleParam.count }
}
