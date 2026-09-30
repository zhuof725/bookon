//
//  JSONPathEvaluator.swift
//  LegadoBookSource
//
//  JSONPath 求值抽象。AnalyzeByJSonPath 只依赖本协议，便于以后替换底层引擎。
//
//  Kotlin 原用 Jayway JsonPath（com.jayway.jsonpath）。本移植自实现一个覆盖书源
//  常用语法子集的引擎（DefaultJSONPathEvaluator），语义尽量贴近 Jayway。
//  已支持 / 不支持 的语法见 README 的对照表。
//

import Foundation

/// JSON 值模型（供 JSONPath 引擎在内部传递，避免 Any 到处飞）。
///
/// 数字拆成 int(Int64) 与 double(Double) 两种，保留「整数字面量 / 小数字面量」的区别，
/// 对齐 Kotlin 侧 Jayway 默认的 json-smart provider（整数解析为 Long、小数解析为 Double）。
///
/// ⚠️ 对象用「保序」结构 OrderedObject 承载，保留 JSON 文本里的键顺序
/// （Jayway/json-smart 用 LinkedHashMap，是有序的）。
public enum JSONValue: Equatable {
    case object(OrderedObject)
    case array([JSONValue])
    case string(String)
    case int(Int64)
    /// 超过 Int64 范围的纯整数：保留原始数字文本，getString 原样输出，不丢精度。
    /// 对齐 Jayway/json-smart 用 BigInteger 保留精度的行为（这里用文本表示更简单可靠）。
    case bigInteger(String)
    case double(Double)
    case bool(Bool)
    case null

    /// 保序 JSON 对象：既能按键取值，又保留插入（=JSON 文本）顺序。
    public struct OrderedObject: Equatable {
        public private(set) var keys: [String]
        private var map: [String: JSONValue]

        public init() { keys = []; map = [:] }
        public init(_ pairs: [(String, JSONValue)]) {
            keys = []; map = [:]
            for (k, v) in pairs { self[k] = v }
        }

        public subscript(_ key: String) -> JSONValue? {
            get { map[key] }
            set {
                if let nv = newValue {
                    if map[key] == nil { keys.append(key) }
                    map[key] = nv
                } else {
                    if map[key] != nil { keys.removeAll { $0 == key } }
                    map[key] = nil
                }
            }
        }

        /// 按 JSON 文本顺序遍历的 (键, 值) 序列。
        public var orderedPairs: [(String, JSONValue)] {
            keys.compactMap { k in map[k].map { (k, $0) } }
        }
        /// 按顺序的值序列。
        public var orderedValues: [JSONValue] { keys.compactMap { map[$0] } }
        public var count: Int { keys.count }
    }

    /// 从 Foundation 的 JSONSerialization 结果构造（数字精度处理见下）。
    public init(fromFoundation any: Any) {
        switch any {
        case let s as String:
            self = .string(s)
        case let n as NSNumber:
            // 用 objCType 区分布尔 / 整数 / 小数，避免统一走 doubleValue 丢精度：
            //  - "c"（char/BOOL）-> 布尔
            //  - 浮点（"f"/"d"）-> double
            //  - 其它（整数 "q"/"l"/"i"/"s"...）-> int(Int64)，Int64 范围内精确（如 19 位整数）
            let t = String(cString: n.objCType)
            if t == "c" {
                self = .bool(n.boolValue)
            } else if t == "f" || t == "d" {
                self = .double(n.doubleValue)
            } else {
                // 整数：优先 Int64；若 NSNumber 承载的整数超出 Int64（罕见，JSONSerialization
                // 会用 NSDecimalNumber），用其字符串表示保留精度。注：主解析路径是 OrderedJSONParser，
                // 本 fromFoundation 仅为兼容 Foundation 值时使用。
                let str = n.stringValue
                if let iv = Int64(str) {
                    self = .int(iv)
                } else {
                    self = .bigInteger(str)
                }
            }
        case let d as [String: Any]:
            // 普通字典无序；用 OrderedObject 承载（顺序由 orderedInit 负责，见 parse）。
            var o = OrderedObject()
            for (k, v) in d { o[k] = JSONValue(fromFoundation: v) }
            self = .object(o)
        case let a as [Any]:
            self = .array(a.map { JSONValue(fromFoundation: $0) })
        case is NSNull:
            self = .null
        default:
            self = .null
        }
    }

    /// 解析 JSON 文本。用自实现的保序解析器（保留对象键顺序 + 整数/小数区别 + 大整数精度），
    /// 不经过 JSONSerialization → NSNumber.doubleValue，避免丢精度与丢顺序。
    public static func parse(_ jsonString: String) -> JSONValue? {
        var parser = OrderedJSONParser(jsonString)
        return parser.parse()
    }

    /// 对应 Kotlin/Jayway 里把读到的对象 toString() 的效果：
    /// 标量转成其字符串表示；对象/数组转成紧凑 JSON（json-smart 风格）。
    public var stringValue: String {
        switch self {
        case .string(let s): return s
        case .bool(let b): return b ? "true" : "false"
        case .int(let i):
            // 整数字面量输出整数（19 位大整数原样、负数原样）。
            return String(i)
        case .bigInteger(let s):
            // 超 Int64 整数：原样输出保留精度。
            return s
        case .double(let d):
            return JSONValue.formatDouble(d)
        case .null: return "null"
        case .object, .array:
            return JSONValue.compactJSONString(self)
        }
    }

    /// 浮点格式化，对齐 Java Double.toString 的常见情形：整数值的浮点输出带 ".0"
    /// （如 1.0 -> "1.0"，1000.0 -> "1000.0"），非整数输出其十进制表示（如 1.5 -> "1.5"）。
    static func formatDouble(_ d: Double) -> String {
        if d.isNaN { return "NaN" }
        if d.isInfinite { return d > 0 ? "Infinity" : "-Infinity" }
        if d == d.rounded() && abs(d) < 1e16 {
            // 整数值的浮点：Java 输出 "x.0"
            return String(format: "%.1f", d)
        }
        // 非整数：用 Swift 默认最短往返表示（与 Java 的最短表示在常见小数上一致）。
        return String(d)
    }

    /// 生成紧凑 JSON 字符串（用于对象/数组 toString），保序、自控数字格式（不经 JSONSerialization）。
    static func compactJSONString(_ v: JSONValue) -> String {
        switch v {
        case .string(let s):
            return "\"\(escapeJSONString(s))\""
        case .int(let i):
            return String(i)
        case .bigInteger(let s):
            return s
        case .double(let d):
            return formatDouble(d)
        case .bool(let b):
            return b ? "true" : "false"
        case .null:
            return "null"
        case .array(let a):
            return "[" + a.map { compactJSONString($0) }.joined(separator: ",") + "]"
        case .object(let o):
            let body = o.orderedPairs
                .map { "\"\(escapeJSONString($0.0))\":\(compactJSONString($0.1))" }
                .joined(separator: ",")
            return "{" + body + "}"
        }
    }

    /// JSON 字符串转义（紧凑输出用）。
    static func escapeJSONString(_ s: String) -> String {
        var out = ""
        for ch in s.unicodeScalars {
            switch ch {
            case "\"": out += "\\\""
            case "\\": out += "\\\\"
            case "\n": out += "\\n"
            case "\r": out += "\\r"
            case "\t": out += "\\t"
            default:
                if ch.value < 0x20 {
                    out += String(format: "\\u%04x", ch.value)
                } else {
                    out.unicodeScalars.append(ch)
                }
            }
        }
        return out
    }
}

/// JSONPath 求值结果。
/// - single：definite path（确定路径）返回单个值；
/// - list：indefinite path（含 `..`/`[*]`/过滤器/多下标）返回列表（即使只命中一个）。
public enum JSONPathResult: Equatable {
    case single(JSONValue)
    case list([JSONValue])
}

/// JSONPath 求值器抽象。
public protocol JSONPathEvaluator {
    /// 用给定的 JSON 根值创建一个可复用的读取上下文。
    init(root: JSONValue)

    /// 读取一个 JSONPath 表达式。
    /// - Throws: 路径不存在 / 语法不支持等错误（对应 Jayway 的 PathNotFoundException 等）。
    ///           上层 AnalyzeByJSonPath 会捕获并吞掉，保持返回空值。
    func read(_ path: String) throws -> JSONPathResult
}

/// JSONPath 求值错误。
public enum JSONPathError: Error, LocalizedError {
    case pathNotFound(String)
    case unsupportedSyntax(String)
    case invalidPath(String)

    public var errorDescription: String? {
        switch self {
        case .pathNotFound(let p): return "JSONPath 未命中: \(p)"
        case .unsupportedSyntax(let s): return "不支持的 JSONPath 语法: \(s)"
        case .invalidPath(let p): return "非法 JSONPath: \(p)"
        }
    }
}
