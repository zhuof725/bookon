//
//  AnalyzeRule+Dispatch.swift
//  LegadoBookSource
//
//  AnalyzeRule 的规则调度方法：getString / getStringList / getElement / getElements，
//  以及 put/get/replaceRegex/缓存/evalJS/ajax。对应 Kotlin AnalyzeRule.kt 同名方法。
//

import Foundation
import SwiftSoup

extension AnalyzeRule {

    // MARK: - getString

    /// 对应 Kotlin: fun getString(ruleStr, mContent=null, isUrl=false): String
    public func getString(_ ruleStr: String?, mContent: RuleValue? = nil, isUrl: Bool = false) throws -> String {
        guard let ruleStr = ruleStr, !ruleStr.isEmpty else { return "" }
        let ruleList = splitSourceRuleCacheString(ruleStr)
        return try getString(ruleList: ruleList, mContent: mContent, isUrl: isUrl)
    }

    /// 对应 Kotlin: fun getString(ruleStr, unescape): String
    public func getString(_ ruleStr: String?, unescape: Bool) throws -> String {
        guard let ruleStr = ruleStr, !ruleStr.isEmpty else { return "" }
        let ruleList = splitSourceRuleCacheString(ruleStr)
        return try getString(ruleList: ruleList, unescape: unescape)
    }

    /// 对应 Kotlin: fun getString(ruleList, mContent=null, isUrl=false, unescape=true): String
    public func getString(ruleList: [SourceRule], mContent: RuleValue? = nil,
                          isUrl: Bool = false, unescape: Bool = true) throws -> String {
        var result: RuleValue? = nil
        let content = mContent ?? self.contentValue
        if let content = content, !ruleList.isEmpty {
            result = content
            if case .jsObject(let obj) = content {
                let sourceRule = ruleList[0]
                try putRule(sourceRule.putMap)
                try sourceRule.makeUpRule(result)
                if sourceRule.getParamSize() > 1 {
                    result = .string(sourceRule.rule)
                } else {
                    result = obj[sourceRule.rule].map { .string($0.stringValue) }
                }
                if let r = result, !sourceRule.replaceRegex.isEmpty {
                    result = .string(replaceRegex(r.stringValue, sourceRule))
                }
            } else if case .jsonObject(let obj) = content {
                result = obj[ruleList[0].rule].map { .string($0.stringValue) }
            } else {
                for sourceRule in ruleList {
                    try putRule(sourceRule.putMap)
                    try sourceRule.makeUpRule(result)
                    guard let r0 = result, !r0.isNull else { continue }
                    let rule = sourceRule.rule
                    if !rule.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || sourceRule.replaceRegex.isEmpty {
                        result = try dispatchString(mode: sourceRule.mode, rule: rule, on: r0, isUrl: isUrl)
                    }
                    if let r = result, !r.isNull, !sourceRule.replaceRegex.isEmpty {
                        result = .string(replaceRegex(r.stringValue, sourceRule))
                    }
                }
            }
        }
        var resultStr = result?.stringValue ?? ""
        if result == nil || result!.isNull { resultStr = "" }
        let str: String
        if unescape && resultStr.contains("&") {
            str = HtmlUnescape.unescapeHtml4(resultStr)
        } else {
            str = resultStr
        }
        if isUrl {
            if str.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return baseUrlValue ?? ""
            }
            return NetworkUtils.getAbsoluteURL(redirectUrlValue, str)
        }
        return str
    }

    private func dispatchString(mode: Mode, rule: String, on result: RuleValue, isUrl: Bool) throws -> RuleValue {
        switch mode {
        case .webJs:
            let s = try webJSResult(rule, result: result)
            return .string(s)
        case .js:
            return try evalJS(rule, result: result)
        case .json:
            let s = try getAnalyzeByJSonPath(result).getString(rule)
            return s.map { .string($0) } ?? .null
        case .xPath:
            let s = try getAnalyzeByXPath(result).getString(rule)
            return s.map { .string($0) } ?? .null
        case .default:
            if isUrl {
                return .string(try getAnalyzeByJSoup(result).getString0(rule))
            } else {
                let s = try getAnalyzeByJSoup(result).getString(rule)
                return s.map { .string($0) } ?? .null
            }
        case .regex:
            return .string(rule)
        }
    }

    // MARK: - getStringList

    /// 对应 Kotlin: fun getStringList(rule, mContent=null, isUrl=false): List<String>?
    public func getStringList(_ rule: String?, mContent: RuleValue? = nil, isUrl: Bool = false) throws -> [String]? {
        guard let rule = rule, !rule.isEmpty else { return nil }
        let ruleList = splitSourceRuleCacheString(rule)
        return try getStringList(ruleList: ruleList, mContent: mContent, isUrl: isUrl)
    }

    public func getStringList(ruleList: [SourceRule], mContent: RuleValue? = nil, isUrl: Bool = false) throws -> [String]? {
        var result: RuleValue? = nil
        let content = mContent ?? self.contentValue
        if let content = content, !ruleList.isEmpty {
            result = content
            if case .jsObject(let obj) = content {
                let sourceRule = ruleList[0]
                try putRule(sourceRule.putMap)
                try sourceRule.makeUpRule(result)
                if sourceRule.getParamSize() > 1 {
                    result = .string(sourceRule.rule)
                } else {
                    result = obj[sourceRule.rule]
                }
                if let r = result, !sourceRule.replaceRegex.isEmpty {
                    if case .stringList(let l) = r {
                        result = .stringList(l.map { replaceRegex($0, sourceRule) })
                    } else {
                        result = .string(replaceRegex(r.stringValue, sourceRule))
                    }
                }
            } else if case .jsonObject(let obj) = content {
                result = obj[ruleList[0].rule]
            } else {
                for sourceRule in ruleList {
                    try putRule(sourceRule.putMap)
                    try sourceRule.makeUpRule(result)
                    guard let r0 = result, !r0.isNull else { continue }
                    let rule = sourceRule.rule
                    if !rule.isEmpty {
                        result = try dispatchStringList(mode: sourceRule.mode, rule: rule, on: r0)
                    }
                    if let r = result, !sourceRule.replaceRegex.isEmpty {
                        if case .stringList(let l) = r {
                            result = .stringList(l.map { replaceRegex($0, sourceRule) })
                        } else {
                            result = .string(replaceRegex(r.stringValue, sourceRule))
                        }
                    }
                }
            }
        }
        guard let res = result, !res.isNull else { return nil }
        var list: [String]
        if case .stringList(let l) = res {
            list = l
        } else if case .string(let s) = res {
            list = s.components(separatedBy: "\n")
        } else {
            list = res.asStringList ?? [res.stringValue]
        }
        if isUrl {
            var urlList: [String] = []
            for u in list {
                let abs = NetworkUtils.getAbsoluteURL(redirectUrlValue, u)
                if !abs.isEmpty && !urlList.contains(abs) { urlList.append(abs) }
            }
            return urlList
        }
        return list
    }

    private func dispatchStringList(mode: Mode, rule: String, on result: RuleValue) throws -> RuleValue {
        switch mode {
        case .webJs:
            let s = try webJSResult(rule, result: result)
            // GSON.fromJsonArray<String>(it).getOrNull() ?: it
            if let arr = JSONValue.parse(s), case .array(let a) = arr {
                return .stringList(a.map { $0.stringValue })
            }
            return .string(s)
        case .js:
            return try evalJS(rule, result: result)
        case .json:
            return .stringList(try getAnalyzeByJSonPath(result).getStringList(rule))
        case .xPath:
            return .stringList(try getAnalyzeByXPath(result).getStringList(rule))
        case .default:
            return .stringList(try getAnalyzeByJSoup(result).getStringList(rule))
        case .regex:
            return .string(rule)
        }
    }

    // MARK: - getElement

    /// 对应 Kotlin: fun getElement(ruleStr): Any?
    public func getElement(_ ruleStr: String) throws -> RuleValue? {
        if ruleStr.isEmpty { return nil }
        var result: RuleValue? = nil
        let content = self.contentValue
        let ruleList = try splitSourceRule(ruleStr, allInOne: true)
        if let content = content, !ruleList.isEmpty {
            result = content
            for sourceRule in ruleList {
                try putRule(sourceRule.putMap)
                try sourceRule.makeUpRule(result)
                guard let r0 = result, !r0.isNull else { continue }
                let rule = sourceRule.rule
                switch sourceRule.mode {
                case .regex:
                    let els = try AnalyzeByRegex.getElement(r0.stringValue, LegadoStringUtils.splitNotBlank(rule, ["&&"]))
                    result = els.map { .stringList($0) } ?? .null
                case .webJs:
                    let s = try webJSResult(rule, result: r0)
                    result = parseJSONObject(s)
                case .js:
                    result = try evalJS(rule, result: r0)
                case .json:
                    result = .json(try getAnalyzeByJSonPath(r0).getObject(rule))
                case .xPath:
                    let nodes = try getAnalyzeByXPath(r0).getElements(rule)
                    result = nodes.map { .xpathNodes($0) } ?? .null
                default:
                    let els = try getAnalyzeByJSoup(r0).getElements(rule)
                    result = .elements(els.array())
                }
                if !sourceRule.replaceRegex.isEmpty, let r = result {
                    result = .string(replaceRegex(r.stringValue, sourceRule))
                }
            }
        }
        return result
    }

    // MARK: - getElements

    /// 对应 Kotlin: fun getElements(ruleStr): List<Any>
    public func getElements(_ ruleStr: String) throws -> [RuleValue] {
        var result: RuleValue? = nil
        let content = self.contentValue
        let ruleList = try splitSourceRule(ruleStr, allInOne: true)
        if let content = content, !ruleList.isEmpty {
            result = content
            for sourceRule in ruleList {
                try putRule(sourceRule.putMap)
                guard let r0 = result, !r0.isNull else { continue }
                let rule = sourceRule.rule
                switch sourceRule.mode {
                case .regex:
                    let els = try AnalyzeByRegex.getElements(r0.stringValue, LegadoStringUtils.splitNotBlank(rule, ["&&"]))
                    result = .stringList(els.map { $0.joined(separator: "\u{1}") })
                case .webJs:
                    let s = try webJSResult(rule, result: r0)
                    result = parseJSONArray(s)
                case .js:
                    result = try evalJS(rule, result: r0)
                case .json:
                    let list = try getAnalyzeByJSonPath(r0).getList(rule)
                    result = list.map { .stringList($0.map { $0.stringValue }) } ?? .null
                case .xPath:
                    let nodes = try getAnalyzeByXPath(r0).getElements(rule)
                    result = nodes.map { .xpathNodes($0) } ?? .null
                default:
                    let els = try getAnalyzeByJSoup(r0).getElements(rule)
                    result = .elements(els.array())
                }
            }
        }
        guard let res = result, !res.isNull else { return [] }
        switch res {
        case .elements(let es): return es.map { .element($0) }
        case .xpathNodes(let ns): return ns.map { .xpathNodes([$0]) }
        case .stringList(let l): return l.map { .string($0) }
        default: return [res]
        }
    }

    private func parseJSONObject(_ s: String) -> RuleValue {
        if let j = JSONValue.parse(s), case .object = j { return .json(j) }
        return .null
    }
    private func parseJSONArray(_ s: String) -> RuleValue {
        if let j = JSONValue.parse(s), case .array(let a) = j { return .stringList(a.map { $0.stringValue }) }
        return .null
    }
}
