//
//  RuleAnalyzer.swift
//  LegadoBookSource
//
//  对应 Kotlin: model/analyzeRule/RuleAnalyzer.kt（377 行，逐行对照移植）
//
//  作用：通用的规则切分处理器。解决 jsonPath 自带的 "&&"/"||" 与阅读规则的冲突，
//  以及规则的正则/字符串中包含 "&&"/"||"/"%%"/"@" 导致的冲突。
//
//  ⚠️ 下标语义：Kotlin 的 String 按 UTF-16 code unit 下标（queue[pos]、indexOf、
//  substring、regionMatches 全是 UTF-16 单位）。为保证含中文/emoji 时位置不错位，
//  本移植内部完全在 UTF-16 code unit 数组（[UInt16]）上操作，切片时再从 UTF-16
//  范围重建 String，与 Kotlin 行为一致。分隔符（&&、||、%%、{$.、[]、()、@、引号、\）
//  都是 BMP ASCII，单个 UTF-16 单位，因此比较与 Kotlin 完全对齐。
//
//  ⚠️ 崩溃收敛：原先用 fatalError 表达的「括号不平衡」、以及可能的下标越界，
//  统一改为抛 RuleEngineError（对齐 Kotlin 会向上传播的异常）。因此 splitRule /
//  splitRuleNext / innerRule / trim 均标 throws。
//

import Foundation

/// 通用规则切分处理器。
public final class RuleAnalyzer {

    // 被处理字符串（以 UTF-16 code unit 数组承载，等价 Kotlin 的 String queue）
    private let queue: [UInt16]
    private var pos = 0        // 当前处理到的位置
    private var start = 0      // 当前处理字段的开始
    private var startX = 0     // 当前规则的开始

    private var rule: [String] = []   // 分割出的规则列表
    private var step: Int = 0         // 分割字符的长度
    /// 当前分割字符串（组合类型："&&" / "||" / "%%" 之一或空）
    public var elementsType = ""

    /// 转义字符
    private static let ESC: UInt16 = 0x5C   // '\\'

    /// - Parameters:
    ///   - data: 被处理字符串
    ///   - code: 是否为 json/JavaScript（决定平衡组函数用 chompCodeBalanced 还是 chompRuleBalanced）
    public init(_ data: String, code: Bool = false) {
        self.queue = Array(data.utf16)
        self.isCode = code
    }

    private let isCode: Bool

    // MARK: - UTF-16 辅助

    private var queueLength: Int { queue.count }

    /// 安全读取 queue[i]；越界抛错（对齐 Kotlin queue[pos] 越界抛异常）。
    private func charAt(_ i: Int) throws -> UInt16 {
        guard i >= 0 && i < queueLength else {
            throw RuleEngineError.indexOutOfBounds("charAt(\(i)), length=\(queueLength)")
        }
        return queue[i]
    }

    /// 把 UTF-16 范围 [from, to) 重建为 String（等价 Kotlin queue.substring(from, to)）。
    /// 起点>终点或越界时抛错（对齐 Kotlin substring 抛 StringIndexOutOfBounds）。
    private func substring(_ from: Int, _ to: Int) throws -> String {
        guard from >= 0, to <= queueLength, from <= to else {
            throw RuleEngineError.indexOutOfBounds("substring(\(from), \(to)), length=\(queueLength)")
        }
        if from == to { return "" }
        return String(utf16CodeUnits: Array(queue[from..<to]), count: to - from)
    }

    /// 等价 Kotlin queue.substring(from)。越界抛错。
    private func substring(_ from: Int) throws -> String {
        guard from >= 0, from <= queueLength else {
            throw RuleEngineError.indexOutOfBounds("substring(\(from)), length=\(queueLength)")
        }
        if from == queueLength { return "" }
        return String(utf16CodeUnits: Array(queue[from..<queueLength]), count: queueLength - from)
    }

    /// 等价 Kotlin queue.indexOf(seq, from)，UTF-16 单位。找不到返回 -1。
    private func indexOf(_ seq: [UInt16], _ from: Int) -> Int {
        if seq.isEmpty { return from <= queueLength ? from : -1 }
        let n = queueLength
        let m = seq.count
        if m > n { return -1 }
        var i = max(from, 0)
        while i <= n - m {
            var j = 0
            while j < m && queue[i + j] == seq[j] { j += 1 }
            if j == m { return i }
            i += 1
        }
        return -1
    }

    /// 等价 Kotlin queue.regionMatches(pos, s, 0, s.length)（区分大小写），UTF-16 单位。
    private func regionMatches(_ atPos: Int, _ s: [UInt16]) -> Bool {
        let len = s.count
        if atPos < 0 || atPos + len > queueLength { return false }
        var j = 0
        while j < len {
            if queue[atPos + j] != s[j] { return false }
            j += 1
        }
        return true
    }

    // MARK: - trim / reSetPos

    /// 修剪当前规则之前的 "@" 或者空白符。
    /// Kotlin 里 `queue[pos]` 越界会抛异常；这里对齐为抛 RuleEngineError。
    public func trim() throws {
        // 在 while 里重复设置 start 和 startX 会拖慢执行速度，所以先判断是否存在需要修剪的字段，最后再一次性设置
        if try charAt(pos) == chAt || (try charAt(pos)) < chBang {
            pos += 1
            while try charAt(pos) == chAt || (try charAt(pos)) < chBang { pos += 1 }
            start = pos   // 开始点推移
            startX = pos  // 规则起始点推移
        }
    }

    /// 将 pos 重置为 0，方便复用。
    public func reSetPos() {
        pos = 0
        startX = 0
    }

    // MARK: - consumeTo / consumeToAny / findToAny

    /// 从剩余字串中拉出一个字符串，直到但不包括匹配序列（区分大小写）。
    /// - Returns: 是否找到相应字段。
    private func consumeTo(_ seq: [UInt16]) -> Bool {
        start = pos  // 将处理到的位置设置为规则起点
        let offset = indexOf(seq, pos)
        if offset != -1 {
            pos = offset
            return true
        }
        return false
    }

    /// 从剩余字串中拉出一个字符串，直到但不包括匹配序列（匹配参数列表中一项即为匹配），或剩余字串用完。
    private func consumeToAny(_ seq: [[UInt16]]) -> Bool {
        var p = pos  // 声明新变量记录匹配位置，不更改类本身的位置
        while p != queueLength {
            for s in seq {
                if regionMatches(p, s) {
                    step = s.count   // 间隔数
                    self.pos = p     // 匹配成功, 同步处理位置到类
                    return true      // 匹配就返回 true
                }
            }
            p += 1  // 逐个试探
        }
        return false
    }

    /// 从剩余字串中拉出一个字符串，直到但不包括匹配序列（字符列表），或剩余字串用完。
    /// - Returns: 返回匹配位置。
    private func findToAny(_ seq: [UInt16]) -> Int {
        var p = pos  // 声明新变量记录匹配位置，不更改类本身的位置
        while p != queueLength {
            for s in seq where queue[p] == s { return p }  // 匹配则返回位置
            p += 1  // 逐个试探
        }
        return -1
    }

    // MARK: - chompCodeBalanced / chompRuleBalanced

    /// 拉出一个非内嵌代码平衡组，存在转义文本。
    private func chompCodeBalanced(_ open: UInt16, _ close: UInt16) -> Bool {
        var p = pos  // 声明临时变量记录匹配位置，匹配成功后才同步到类的 pos

        var depth = 0       // 嵌套深度
        var otherDepth = 0  // 其他对称符合嵌套深度

        var inSingleQuote = false  // 单引号
        var inDoubleQuote = false  // 双引号

        repeat {
            if p == queueLength { break }
            let c = queue[p]; p += 1
            if c != RuleAnalyzer.ESC {  // 非转义字符
                if c == chSingleQuote && !inDoubleQuote { inSingleQuote.toggle() }       // 匹配具有语法功能的单引号
                else if c == chDoubleQuote && !inSingleQuote { inDoubleQuote.toggle() }  // 匹配具有语法功能的双引号

                if inSingleQuote || inDoubleQuote { continue }  // 语法单元未匹配结束，直接进入下个循环

                if c == chBracketOpen { depth += 1 }         // 开始嵌套一层
                else if c == chBracketClose { depth -= 1 }   // 闭合一层嵌套
                else if depth == 0 {
                    // 处于默认嵌套中的非默认字符不需要平衡，仅 depth 为 0 时默认嵌套全部闭合，此字符才进行嵌套
                    if c == open { otherDepth += 1 }
                    else if c == close { otherDepth -= 1 }
                }
            } else { p += 1 }
        } while depth > 0 || otherDepth > 0  // 拉出一个平衡字串

        if depth > 0 || otherDepth > 0 {
            return false
        } else {
            self.pos = p  // 同步位置
            return true
        }
    }

    /// 拉出一个规则平衡组，经过仔细测试 xpath 和 jsoup 中，引号内转义字符无效。
    private func chompRuleBalanced(_ open: UInt16, _ close: UInt16) -> Bool {
        var p = pos  // 声明临时变量记录匹配位置，匹配成功后才同步到类的 pos
        var depth = 0             // 嵌套深度
        var inSingleQuote = false // 单引号
        var inDoubleQuote = false // 双引号

        repeat {
            if p == queueLength { break }
            let c = queue[p]; p += 1
            if c == chSingleQuote && !inDoubleQuote { inSingleQuote.toggle() }        // 匹配具有语法功能的单引号
            else if c == chDoubleQuote && !inSingleQuote { inDoubleQuote.toggle() }   // 匹配具有语法功能的双引号

            if inSingleQuote || inDoubleQuote { continue }  // 语法单元未匹配结束，直接进入下个循环
            else if c == chBackslash {  // 不在引号中的转义字符才将下个字符转义
                p += 1
                continue
            }

            if c == open { depth += 1 }        // 开始嵌套一层
            else if c == close { depth -= 1 }  // 闭合一层嵌套

        } while depth > 0  // 拉出一个平衡字串

        if depth > 0 {
            return false
        } else {
            self.pos = p  // 同步位置
            return true
        }
    }

    /// 设置平衡组函数，json 或 JavaScript 时用 chompCodeBalanced，否则为 chompRuleBalanced。
    /// 对应 Kotlin: val chompBalanced = if (code) ::chompCodeBalanced else ::chompRuleBalanced
    private func chompBalanced(_ open: UInt16, _ close: UInt16) -> Bool {
        isCode ? chompCodeBalanced(open, close) : chompRuleBalanced(open, close)
    }

    // MARK: - splitRule（首段匹配）

    /// 不用正则，不到最后不切片也不用中间变量存储，只在序列中标记当前查找字段的开头结尾，
    /// 到返回时才切片，高效快速准确切割规则。
    /// 首段匹配，elementsType 为空。
    ///
    /// 对应 Kotlin: tailrec fun splitRule(vararg split: String): ArrayList<String>
    /// - Throws: RuleEngineError.unbalanced（括号不平衡）/ .indexOutOfBounds。
    @discardableResult
    public func splitRule(_ split: String...) throws -> [String] {
        return try splitRule(split)
    }

    /// 数组入参版本（便于 public 调用方直接传数组，语义与可变参数版一致）。
    @discardableResult
    public func splitRule(_ split: [String]) throws -> [String] {
        // 用循环替代 Kotlin 的 tailrec（尾递归），行为等价。
        let split = split
        while true {
            if split.count == 1 {
                elementsType = split[0]  // 设置分割字串
                let et = Array(elementsType.utf16)
                if !consumeTo(et) {
                    rule.append(try substring(startX))
                    return rule
                } else {
                    step = et.count  // 设置分隔符长度
                    return try splitRuleNext()
                }  // 递归匹配
            } else if !consumeToAny(split.map { Array($0.utf16) }) {  // 未找到分隔符
                rule.append(try substring(startX))
                return rule
            }

            let end = pos      // 记录分隔位置
            pos = start        // 重回开始，启动另一种查找

            repeat {
                let st = findToAny(charsBracketParenOpen)  // 查找筛选器位置

                if st == -1 {
                    rule = [try substring(startX, end)]  // 压入分隔的首段规则到数组

                    elementsType = try substring(end, end + step)  // 设置组合类型
                    pos = end + step  // 跳过分隔符

                    let et = Array(elementsType.utf16)
                    while consumeTo(et) {  // 循环切分规则压入数组
                        rule.append(try substring(start, pos))
                        pos += step  // 跳过分隔符
                    }

                    rule.append(try substring(pos))  // 将剩余字段压入数组末尾
                    return rule
                }

                if st > end {  // 先匹配到 st，表明分隔字串不在选择器中，将选择器前分隔字串分隔的字段依次压入数组
                    rule = [try substring(startX, end)]  // 压入分隔的首段规则到数组

                    elementsType = try substring(end, end + step)  // 设置组合类型
                    pos = end + step  // 跳过分隔符

                    let et = Array(elementsType.utf16)
                    while consumeTo(et) && pos < st {  // 循环切分规则压入数组
                        rule.append(try substring(start, pos))
                        pos += step  // 跳过分隔符
                    }

                    if pos > st {
                        startX = start
                        return try splitRuleNext()  // 首段已匹配,但当前段匹配未完成,调用二段匹配
                    } else {  // 执行到此，证明后面再无分隔字符
                        rule.append(try substring(pos))  // 将剩余字段压入数组末尾
                        return rule
                    }
                }

                pos = st  // 位置推移到筛选器处
                let next: UInt16 = queue[pos] == chBracketOpen ? chBracketClose : chParenClose  // 平衡组末尾字符

                if !chompBalanced(queue[pos], next) {  // 拉出一个筛选器,不平衡则报错
                    throw RuleEngineError.unbalanced(try substring(0, start))
                }

            } while end > pos

            start = pos  // 设置开始查找筛选器位置的起始位置
            // Kotlin: return splitRule(* split) —— 递归调用首段匹配；
            // 这里回到 while 顶部，继续用同样的 split 做首段匹配。
        }
    }

    // MARK: - splitRule（二段匹配）

    /// 二段匹配被调用，elementsType 非空（已在首段赋值），直接按 elementsType 查找，比首段更快。
    /// 对应 Kotlin: @JvmName("splitRuleNext") private tailrec fun splitRule(): ArrayList<String>
    @discardableResult
    private func splitRuleNext() throws -> [String] {
        // 用循环替代 tailrec。continue outer 模拟 Kotlin 的 `return splitRule()` 尾递归重启。
        outer: while true {
            let end = pos    // 记录分隔位置
            pos = start      // 重回开始，启动另一种查找

            repeat {
                let st = findToAny(charsBracketParenOpen)  // 查找筛选器位置

                if st == -1 {
                    rule.append(try substring(startX, end))  // 压入分隔的首段规则到数组
                    pos = end + step  // 跳过分隔符

                    let et = Array(elementsType.utf16)
                    while consumeTo(et) {  // 循环切分规则压入数组
                        rule.append(try substring(start, pos))
                        pos += step  // 跳过分隔符
                    }

                    rule.append(try substring(pos))  // 将剩余字段压入数组末尾
                    return rule
                }

                if st > end {  // 先匹配到 st，表明分隔字串不在选择器中，将选择器前分隔字串分隔的字段依次压入数组
                    rule.append(try substring(startX, end))  // 压入分隔的首段规则到数组
                    pos = end + step  // 跳过分隔符

                    let et = Array(elementsType.utf16)
                    while consumeTo(et) && pos < st {  // 循环切分规则压入数组
                        rule.append(try substring(start, pos))
                        pos += step  // 跳过分隔符
                    }

                    if pos > st {
                        startX = start
                        continue outer  // Kotlin: return splitRule() —— 二段匹配重启
                    } else {  // 执行到此，证明后面再无分隔字符
                        rule.append(try substring(pos))  // 将剩余字段压入数组末尾
                        return rule
                    }
                }

                pos = st  // 位置推移到筛选器处
                let next: UInt16 = queue[pos] == chBracketOpen ? chBracketClose : chParenClose  // 平衡组末尾字符

                if !chompBalanced(queue[pos], next) {  // 拉出一个筛选器,不平衡则报错
                    throw RuleEngineError.unbalanced(try substring(0, start))
                }

            } while end > pos

            start = pos  // 设置开始查找筛选器位置的起始位置

            let et = Array(elementsType.utf16)
            if !consumeTo(et) {
                rule.append(try substring(startX))
                return rule
            } else {
                continue outer  // Kotlin: splitRule() —— 二段匹配重启
            }
        }
    }

    // MARK: - innerRule（两个重载）

    /// 替换内嵌规则。
    /// - Parameters:
    ///   - inner: 起始标志,如 "{$."
    ///   - startStep: 不属于规则部分的前置字符长度，如 "{$." 中 "{" 不属于规则，故 startStep 为 1
    ///   - endStep: 不属于规则部分的后置字符长度
    ///   - fr: 查找到内嵌规则时，用于解析的函数
    /// - Throws: RuleEngineError.indexOutOfBounds（substring 越界，对齐 Kotlin）。
    public func innerRule(
        _ inner: String,
        startStep: Int = 1,
        endStep: Int = 1,
        fr: (String) -> String?
    ) throws -> String {
        var st = ""
        let innerU = Array(inner.utf16)

        while consumeTo(innerU) {  // 拉取成功返回 true，pos 后移相应位置，否则返回 false
            let posPre = pos  // 记录 consumeTo 匹配位置
            if chompCodeBalanced(chBraceOpen, chBraceClose) {
                let frv = fr(try substring(posPre + startStep, pos - endStep))
                if let frv = frv, !frv.isEmpty {
                    st += try substring(startX, posPre) + frv  // 压入内嵌规则前的内容，及内嵌规则解析得到的字符串
                    startX = pos  // 记录下次规则起点
                    continue      // 获取内容成功，继续选择下个内嵌规则
                }
            }
            pos += innerU.count  // 拉出字段不平衡，inner 只是个普通字串，跳到此 inner 后继续匹配
        }

        return startX == 0 ? "" : (st + (try substring(startX)))
    }

    /// 替换内嵌规则（起止字符串版）。
    /// - Parameter fr: 查找到内嵌规则时，用于解析的函数
    ///
    /// ⚠️ 已知行为（对齐 Kotlin）：Kotlin 里此重载在 fr 返回 null 时，会把字符串 "null"
    /// 拼接进结果（`st.append(... + frv)`，frv 为 null 时 Kotlin 字符串拼接得到 "null"）。
    /// 本移植用 `frv ?? "null"` 精确对齐该行为（不是 `?? ""`）。
    public func innerRule(
        _ startStr: String,
        _ endStr: String,
        fr: (String) -> String?
    ) throws -> String {
        var st = ""
        let startU = Array(startStr.utf16)
        let endU = Array(endStr.utf16)

        while consumeTo(startU) {  // 拉取成功返回 true，pos 后移相应位置，否则返回 false
            pos += startU.count  // 跳过开始字符串
            let posPre = pos     // 记录 consumeTo 匹配位置
            if consumeTo(endU) {
                let frv = fr(try substring(posPre, pos))
                // 压入内嵌规则前的内容，及内嵌规则解析得到的字符串。
                // Kotlin: st.append(queue.substring(startX, posPre - startStr.length) + frv)
                // frv 为 null 时 Kotlin 拼接得到字面量 "null"，此处对齐。
                st += try substring(startX, posPre - startU.count) + (frv ?? "null")
                pos += endU.count  // 跳过结束字符串
                startX = pos       // 记录下次规则起点
            }
        }

        return startX == 0 ? (try substring(0)) : (st + (try substring(startX)))
    }

    // MARK: - 字符常量（UTF-16 单位，均为 BMP ASCII）

    private let chAt: UInt16 = 0x40           // '@'
    private let chBang: UInt16 = 0x21         // '!'（queue[pos] < '!' 即空白/控制符）
    private let chSingleQuote: UInt16 = 0x27  // '\''
    private let chDoubleQuote: UInt16 = 0x22  // '"'
    private let chBackslash: UInt16 = 0x5C    // '\\'
    private let chBracketOpen: UInt16 = 0x5B  // '['
    private let chBracketClose: UInt16 = 0x5D // ']'
    private let chParenOpen: UInt16 = 0x28    // '('
    private let chParenClose: UInt16 = 0x29   // ')'
    private let chBraceOpen: UInt16 = 0x7B    // '{'
    private let chBraceClose: UInt16 = 0x7D   // '}'
    private var charsBracketParenOpen: [UInt16] { [0x5B, 0x28] }  // '[', '('
}
