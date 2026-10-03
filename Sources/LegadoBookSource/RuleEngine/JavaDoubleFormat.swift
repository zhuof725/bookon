//
//  JavaDoubleFormat.swift
//  LegadoBookSource
//
//  把 JavaScriptCore 的 Double 按 Java `Double.toString` 的常见格式输出。
//  legado 的 AnalyzeRule.evalJS 返回 Rhino 原始 Number；getString 最终调用 Java
//  `toString()`。Swift Double.description 虽同样使用最短往返数字，但 NaN/Infinity
//  的拼写、科学计数阈值与指数格式不同。本格式器保留 Swift 的最短有效数字，
//  仅按 Java 规则重新排版：[-3, 7) 使用普通十进制，其余使用 `D.DDEn`。
//
//  极端相邻值的小数选取仍由 Swift Double.description 提供；第 4 步 Rhino 1.8.1
//  golden 覆盖本项目实际关心的整数/小数/大数/NaN/Infinity 边界。
//

import Foundation

enum JavaDoubleFormat {
    static func string(_ value: Double) -> String {
        if value.isNaN { return "NaN" }
        if value == .infinity { return "Infinity" }
        if value == -.infinity { return "-Infinity" }
        if value == 0 {
            return value.sign == .minus ? "-0.0" : "0.0"
        }

        let negative = value < 0
        let magnitude = negative ? -value : value
        let raw = String(magnitude)

        let exponentSplit = raw.split(separator: "e", maxSplits: 1, omittingEmptySubsequences: false)
        let mantissa = String(exponentSplit[0])
        let explicitExponent: Int
        if exponentSplit.count == 2 {
            let exp = String(exponentSplit[1])
            explicitExponent = Int(exp) ?? 0
        } else {
            explicitExponent = 0
        }

        let pointSplit = mantissa.split(separator: ".", maxSplits: 1, omittingEmptySubsequences: false)
        let integerPart = String(pointSplit[0])
        let fractionalPart = pointSplit.count == 2 ? String(pointSplit[1]) : ""
        let combined = Array(integerPart + fractionalPart)

        guard let first = combined.firstIndex(where: { $0 != "0" }) else {
            return negative ? "-0.0" : "0.0"
        }
        guard let last = combined.lastIndex(where: { $0 != "0" }) else {
            return negative ? "-0.0" : "0.0"
        }

        let significant = String(combined[first...last])
        let trailingZeros = combined.distance(from: last, to: combined.endIndex) - 1
        let pointPower = explicitExponent - fractionalPart.count + trailingZeros
        let decimalExponent = pointPower + significant.count - 1
        let sign = negative ? "-" : ""

        if decimalExponent >= -3 && decimalExponent < 7 {
            let beforePoint = decimalExponent + 1
            if beforePoint <= 0 {
                return sign + "0." + String(repeating: "0", count: -beforePoint) + significant
            }
            if beforePoint >= significant.count {
                return sign + significant
                    + String(repeating: "0", count: beforePoint - significant.count)
                    + ".0"
            }
            let chars = Array(significant)
            let lhs = String(chars[0..<beforePoint])
            let rhs = String(chars[beforePoint...])
            return sign + lhs + "." + rhs
        }

        let chars = Array(significant)
        let firstDigit = String(chars[0])
        let rest = chars.count > 1 ? String(chars[1...]) : "0"
        return sign + firstDigit + "." + rest + "E" + String(decimalExponent)
    }
}
