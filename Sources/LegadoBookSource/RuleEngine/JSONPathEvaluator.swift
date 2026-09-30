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
public enum JSONValue: Equatable {
    case object([String: JSONValue])
    case array([JSONValue])
    case string(String)
    case number(Double)
    case bool(Bool)
    case null

    /// 从 Foundation 的 JSONSerialization 结果构造。
    public init(fromFoundation any: Any) {
        switch any {
        case let s as String:
            self = .string(s)
        case let n as NSNumber:
            // 区分布尔与数字：NSNumber 的布尔用 CFBoolean。
            if CFGetTypeID(n) == CFBooleanGetTypeID() {
                self = .bool(n.boolValue)
            } else {
                self = .number(n.doubleValue)
            }
        case let b as Bool:
            self = .bool(b)
        case let d as [String: Any]:
            var o: [String: JSONValue] = [:]
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

    /// 解析 JSON 文本。
    public static func parse(_ jsonString: String) -> JSONValue? {
        guard let data = jsonString.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
        else { return nil }
        return JSONValue(fromFoundation: obj)
    }

    /// 对应 Kotlin/Jayway 里把读到的对象 toString() 的效果：
    /// 标量转成其字符串表示；对象/数组转成紧凑 JSON。
    public var stringValue: String {
        switch self {
        case .string(let s): return s
        case .bool(let b): return b ? "true" : "false"
        case .number(let n):
            // 整数值不带小数点（贴近 Jayway 对整型的 toString）。
            if n == n.rounded() && abs(n) < 9.007e15 {
                return String(Int64(n))
            }
            return String(n)
        case .null: return "null"
        case .object, .array:
            return JSONValue.compactJSONString(self)
        }
    }

    /// 生成紧凑 JSON 字符串（用于对象/数组 toString）。
    static func compactJSONString(_ v: JSONValue) -> String {
        let foundation = v.toFoundation()
        if let data = try? JSONSerialization.data(withJSONObject: wrapForSerialization(foundation), options: []),
           let s = String(data: data, encoding: .utf8) {
            // 去掉包裹层
            return unwrapSerialized(s)
        }
        return "\(foundation)"
    }

    // JSONSerialization 顶层必须是数组/字典；标量需包裹。这里对象/数组可直接序列化。
    private static func wrapForSerialization(_ any: Any) -> Any {
        if any is [Any] || any is [String: Any] { return any }
        return [any]
    }
    private static func unwrapSerialized(_ s: String) -> String { s }

    /// 转回 Foundation 对象（供序列化）。
    public func toFoundation() -> Any {
        switch self {
        case .string(let s): return s
        case .number(let n):
            if n == n.rounded() && abs(n) < 9.007e15 { return Int64(n) }
            return n
        case .bool(let b): return b
        case .null: return NSNull()
        case .object(let o):
            var d: [String: Any] = [:]
            for (k, v) in o { d[k] = v.toFoundation() }
            return d
        case .array(let a):
            return a.map { $0.toFoundation() }
        }
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
