//
//  AnalyzeRule+Rules.swift
//  LegadoBookSource
//
//  AnalyzeRule 的规则拆分（splitSourceRule / SourceRule）、put/get、replaceRegex、缓存、
//  evalJS / ajax / webJSResult。对应 Kotlin AnalyzeRule.kt 的 SourceRule inner class、
//  splitSourceRule、companion 正则、put/get、replaceRegex、evalJS。
//

import Foundation

extension AnalyzeRule {

    // Kotlin companion 正则（抄确切定义）：
    //  JS_PATTERN  = <js>([\w\W]*?)</js>|@js:([\w\W]*)   CASE_INSENSITIVE
    //  WebJS_PATTERN = @webjs:([\w\W]{5,})               CASE_INSENSITIVE
    //  putPattern  = @put:(\{[^}]+?\})                   CASE_INSENSITIVE
    //  evalPattern = @get:\{[^}]+?\}|\{\{[\w\W]*?\}\}    CASE_INSENSITIVE
    //  regexPattern = \$\d{1,2}
    /// 安全编译常量正则：失败返回一个永不匹配的正则（不崩溃；这些模式为已知合法常量，不会失败）。
    static func compileConst(_ pattern: String, _ opts: NSRegularExpression.Options = []) -> NSRegularExpression {
        if let r = try? NSRegularExpression(pattern: pattern, options: opts) { return r }
        // 兜底：匹配不可能出现的控制字符序列，等价「永不匹配」。
        return (try? NSRegularExpression(pattern: "(?!)", options: [])) ?? NSRegularExpression()
    }
    static let jsPattern = compileConst("<js>([\\w\\W]*?)</js>|@js:([\\w\\W]*)", [.caseInsensitive])
    static let webJsPattern = compileConst("@webjs:([\\w\\W]{5,})", [.caseInsensitive])
    static let putPattern = compileConst("@put:(\\{[^}]+?\\})", [.caseInsensitive])
    static let evalPattern = compileConst("@get:\\{[^}]+?\\}|\\{\\{[\\w\\W]*?\\}\\}", [.caseInsensitive])
    static let regexPattern = compileConst("\\$\\d{1,2}", [])

    // MARK: - put / get（四层回退链）

    /// 对应 Kotlin: fun put(key, value): String —— chapter→book→ruleData→source
    @discardableResult
    public func put(_ key: String, _ value: String) -> String {
        if let c = chapterStore {
            c.putVariable(key, value)
        } else if let b = bookStore {
            b.putVariable(key, value)
        } else if let r = ruleDataStore {
            r.putVariable(key, value)
        } else if let s = sourceStore {
            _ = s.put(key, value)
        }
        return value
    }

    /// 对应 Kotlin: fun get(key): String —— bookName/title 特判 + 四层回退（takeIf isNotEmpty）
    public func get(_ key: String) -> String {
        if key == "bookName", let b = bookStore { return b.name }
        if key == "title", let c = chapterStore { return c.title }
        if let c = chapterStore { let v = c.getVariable(key); if !v.isEmpty { return v } }
        if let b = bookStore { let v = b.getVariable(key); if !v.isEmpty { return v } }
        if let r = ruleDataStore { let v = r.getVariable(key); if !v.isEmpty { return v } }
        if let s = sourceStore { let v = s.get(key); if !v.isEmpty { return v } }
        return ""
    }

    /// 对应 Kotlin: private fun putRule(map) { for ((k,v) in map) put(k, getString(v)) }
    func putRule(_ map: [String: String]) throws {
        for (key, value) in map {
            _ = put(key, try getString(value))
        }
    }

    // MARK: - replaceRegex（对应 Kotlin replaceRegex）

    /// 对应 Kotlin: private fun replaceRegex(result, rule): String
    func replaceRegex(_ result: String, _ rule: SourceRule) -> String {
        if rule.replaceRegex.isEmpty { return result }
        let replaceRegexStr = rule.replaceRegex
        let replacement = rule.replacement
        let regex = compileRegexCache(replaceRegexStr)
        if rule.replaceFirst {
            // ##match##replace### 取第一个匹配并替换
            if let regex = regex {
                let ns = result as NSString
                if let m = regex.firstMatch(in: result, range: NSRange(location: 0, length: ns.length)) {
                    let g0 = ns.substring(with: m.range)
                    // Kotlin: matcher.group(0)!!.replaceFirst(regex, replacement)
                    let g0ns = g0 as NSString
                    let template = RegexTemplate.javaToICU(replacement, pattern: replaceRegexStr)
                    if let m2 = regex.firstMatch(in: g0, range: NSRange(location: 0, length: g0ns.length)) {
                        let replaced = regex.replacementString(for: m2, in: g0, offset: 0, template: template)
                        let full = (g0ns.replacingCharacters(in: m2.range, with: replaced))
                        return full
                    }
                    return g0
                } else {
                    return ""
                }
            }
            return replacement
        } else {
            // ##match##replace 全部替换
            if let regex = regex {
                let ns = result as NSString
                let template = RegexTemplate.javaToICU(replacement, pattern: replaceRegexStr)
                return regex.stringByReplacingMatches(in: result, range: NSRange(location: 0, length: ns.length), withTemplate: template)
            }
            // regex 为 nil：Kotlin 退回字面量替换 result.replace(replaceRegex, replacement)
            return result.replacingOccurrences(of: replaceRegexStr, with: replacement)
        }
    }

    /// 对应 Kotlin: compileRegexCache(regex) = regexCache.getOrPutLimit(regex, 16) { regex.toRegex() 失败 null }
    func compileRegexCache(_ pattern: String) -> NSRegularExpression? {
        if let cached = regexCache[pattern] { return cached }
        let compiled = try? NSRegularExpression(pattern: pattern)
        if regexCache.count < regexCacheLimit {
            regexCache[pattern] = compiled
        }
        return compiled
    }

    // MARK: - splitSourceRule 缓存

    /// 对应 Kotlin: splitSourceRuleCacheString —— stringRuleCache.getOrPut（无容量上限，Kotlin 用 getOrPut）
    func splitSourceRuleCacheString(_ ruleStr: String?) -> [SourceRule] {
        guard let ruleStr = ruleStr, !ruleStr.isEmpty else { return [] }
        if let cached = stringRuleCache[ruleStr] { return cached }
        let list = (try? splitSourceRule(ruleStr)) ?? []
        stringRuleCache[ruleStr] = list
        return list
    }

    /// 对应 Kotlin: fun splitSourceRule(ruleStr, allInOne=false): List<SourceRule>
    public func splitSourceRule(_ ruleStr: String?, allInOne: Bool = false) throws -> [SourceRule] {
        guard let ruleStr = ruleStr, !ruleStr.isEmpty else { return [] }
        var ruleList: [SourceRule] = []
        var mMode: Mode = .default
        var start = 0
        let ns = ruleStr as NSString
        let fullRange = NSRange(location: 0, length: ns.length)
        if allInOne && ruleStr.hasPrefix(":") {
            mMode = .regex
            isRegexFlag = true
            start = 1
        } else if isRegexFlag {
            mMode = .regex
        }

        // JS_PATTERN
        for m in AnalyzeRule.jsPattern.matches(in: ruleStr, range: fullRange) {
            if m.range.location > start {
                let tmp = ns.substring(with: NSRange(location: start, length: m.range.location - start))
                    .trimmingCharacters(in: .whitespaces)
                if !tmp.isEmpty { ruleList.append(try SourceRule(tmp, mode: mMode, owner: self)) }
            }
            // group(2) ?: group(1)
            let g2 = m.range(at: 2)
            let g1 = m.range(at: 1)
            let jsCode: String
            if g2.location != NSNotFound { jsCode = ns.substring(with: g2) }
            else if g1.location != NSNotFound { jsCode = ns.substring(with: g1) }
            else { jsCode = "" }
            ruleList.append(try SourceRule(jsCode, mode: .js, owner: self))
            start = m.range.location + m.range.length
        }

        // WebJS_PATTERN
        for m in AnalyzeRule.webJsPattern.matches(in: ruleStr, range: fullRange) {
            if m.range.location > start {
                let tmp = ns.substring(with: NSRange(location: start, length: m.range.location - start))
                    .trimmingCharacters(in: .whitespaces)
                if !tmp.isEmpty { ruleList.append(try SourceRule(tmp, mode: mMode, owner: self)) }
            }
            let g1 = m.range(at: 1)
            let code = g1.location != NSNotFound ? ns.substring(with: g1) : ""
            ruleList.append(try SourceRule(code, mode: .webJs, owner: self))
            start = m.range.location + m.range.length
        }

        if ns.length > start {
            let tmp = ns.substring(from: start).trimmingCharacters(in: .whitespaces)
            if !tmp.isEmpty { ruleList.append(try SourceRule(tmp, mode: mMode, owner: self)) }
        }
        return ruleList
    }

    /// 对应 Kotlin: getOrCreateSingleSourceRule —— stringRuleCache.getOrPutLimit(rule, 16) { listOf(SourceRule(rule)) }
    func getOrCreateSingleSourceRule(_ rule: String) throws -> [SourceRule] {
        if let cached = stringRuleCache[rule] { return cached }
        let list = [try SourceRule(rule, mode: .default, owner: self)]
        if stringRuleCache.count < 16 {
            stringRuleCache[rule] = list
        }
        return list
    }

    // MARK: - splitPutRule（对应 Kotlin splitPutRule）

    /// 对应 Kotlin: splitPutRule(ruleStr, putMap) —— 抽取 @put:{...} JSON 合并进 putMap，去掉原文。
    func splitPutRule(_ ruleStr: String, into putMap: inout [String: String]) -> String {
        var vRuleStr = ruleStr
        let ns0 = ruleStr as NSString
        let matches = AnalyzeRule.putPattern.matches(in: ruleStr, range: NSRange(location: 0, length: ns0.length))
        for m in matches {
            let full = (ruleStr as NSString).substring(with: m.range)
            vRuleStr = vRuleStr.replacingOccurrences(of: full, with: "")
            let g1 = m.range(at: 1)
            if g1.location == NSNotFound { continue }
            let putJsonStr = (ruleStr as NSString).substring(with: g1)
            if let parsed = parseStringMap(putJsonStr) {
                for (k, v) in parsed { putMap[k] = v }
            }
        }
        return vRuleStr
    }

    /// 解析 {"k":"v"} 为 [String:String]（对齐 Kotlin GSON.fromJsonObject<Map<String,String>>）。
    func parseStringMap(_ json: String) -> [String: String]? {
        guard let j = JSONValue.parse(json), case .object(let obj) = j else { return nil }
        var map: [String: String] = [:]
        for (k, v) in obj.orderedPairs { map[k] = v.stringValue }
        return map
    }
}
