import Foundation

/// 未建模字段的原样保留容器。
/// Legado 的书源 JSON 字段很多，而且不同分支会加新字段；只认识 CodingKeys 里的字段时，
/// 导入 → 编辑 → 导出会把其余字段全部丢掉。这个类型让 BookSource 能原样存取未知字段。
enum JSONValue: Codable, Hashable, Sendable {
    case null
    case bool(Bool)
    case int(Int)
    case double(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() {
            self = .null
        } else if let b = try? c.decode(Bool.self) {
            self = .bool(b)
        } else if let i = try? c.decode(Int.self) {
            self = .int(i)
        } else if let d = try? c.decode(Double.self) {
            self = .double(d)
        } else if let s = try? c.decode(String.self) {
            self = .string(s)
        } else if let a = try? c.decode([JSONValue].self) {
            self = .array(a)
        } else if let o = try? c.decode([String: JSONValue].self) {
            self = .object(o)
        } else {
            throw DecodingError.dataCorruptedError(in: c, debugDescription: "不支持的 JSON 值")
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .null: try c.encodeNil()
        case .bool(let v): try c.encode(v)
        case .int(let v): try c.encode(v)
        case .double(let v): try c.encode(v)
        case .string(let v): try c.encode(v)
        case .array(let v): try c.encode(v)
        case .object(let v): try c.encode(v)
        }
    }

    /// 原样写回 Foundation 对象（JSONSerialization / 字典）。
    var rawValue: Any {
        switch self {
        case .null: return NSNull()
        case .bool(let v): return v
        case .int(let v): return v
        case .double(let v): return v
        case .string(let v): return v
        case .array(let v): return v.map { $0.rawValue }
        case .object(let v): return v.mapValues { $0.rawValue }
        }
    }

    init(rawValue: Any) {
        switch rawValue {
        case is NSNull:
            self = .null
        case let b as Bool:
            self = .bool(b)
        case let i as Int:
            self = .int(i)
        case let n as NSNumber:
            let double = n.doubleValue
            if double.rounded() == double, double >= Double(Int.min), double <= Double(Int.max) {
                self = .int(Int(double))
            } else {
                self = .double(double)
            }
        case let s as String:
            self = .string(s)
        case let a as [Any]:
            self = .array(a.map { JSONValue(rawValue: $0) })
        case let o as [String: Any]:
            self = .object(o.mapValues { JSONValue(rawValue: $0) })
        default:
            self = .string(String(describing: rawValue))
        }
    }

    var stringValue: String? {
        switch self {
        case .string(let v): return v
        case .int(let v): return String(v)
        case .double(let v): return String(v)
        case .bool(let v): return v ? "true" : "false"
        default: return nil
        }
    }
}

/// 编码未识别字段时用的动态键。
struct AnyCodingKey: CodingKey {
    var stringValue: String
    var intValue: Int? { nil }
    init(_ string: String) { self.stringValue = string }
    init?(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { return nil }
}
