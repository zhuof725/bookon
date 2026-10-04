//
//  CharsetRecog2022.swift
//  LegadoBookSource
//
//  第 6 步 6B：ICU4J CharsetRecog_2022（ISO-2022-JP/KR/CN）的 Swift 移植。
//
//  对应 Java：app/src/main/java/io/legado/app/lib/icu4j/CharsetRecog_2022.java
//

import Foundation

/// ISO-2022 家族的公共匹配逻辑（Java `CharsetRecog_2022.match(text, textLen, escapeSequences)`）。
///
/// 统计合法/未识别转义序列数量并据此打分：全部命中为 100，一半及以下为 0，
/// 中间线性；转义序列过少（含移位符 < 5 个）时按每个扣 10 分。
/// 注意：本函数在**剥离标记后的输入**（fInputBytes/fInputLen）上运行，与 Java 一致。
func match2022Sequences(text: [UInt8], textLen: Int, escapeSequences: [[UInt8]]) -> Int {
    var hits = 0
    var misses = 0
    var shifts = 0
    var quality = 0

    var i = 0
    scanInput: while i < textLen {
        if text[i] == 0x1B { // ESC
            var matched = false
            checkEscapes: for seq in escapeSequences {
                if textLen - i < seq.count {
                    continue
                }
                var j = 1
                while j < seq.count {
                    if seq[j] != text[i + j] {
                        continue checkEscapes
                    }
                    j += 1
                }
                hits += 1
                // 与 Java 逐行对齐：Java `i += seq.length - 1` 后 `continue scanInput`，
                // 但带标签的 continue 会执行 for 的更新表达式 i++（JLS 14.16），
                // 即循环末尾还会自增一次。这里不 continue，直接落到下方的移位符检查与
                // i += 1，执行顺序与 Java 完全一致（命中后 i 指向序列末字节；
                // 各转义序列末字节均非 0x0E/0x0F，移位符检查结果与 Java 相同）。
                i += seq.count - 1
                matched = true
                break checkEscapes
            }
            if !matched {
                misses += 1
            }
        }
        if text[i] == 0x0E || text[i] == 0x0F {
            // Shift in/out
            shifts += 1
        }
        i += 1
    }

    if hits == 0 {
        return 0
    }

    // 初始质量基于已识别/未识别转义序列的相对比例
    quality = (100 * hits - 100 * misses) / (hits + misses)

    // 转义序列太少时回退质量（把移位符计入，避免 KR 只有一个转义序列却有很多移位符时受罚）
    if hits + shifts < 5 {
        quality -= (5 - (hits + shifts)) * 10
    }

    if quality < 0 {
        quality = 0
    }
    return quality
}

/// ISO-2022-JP 识别器（ICU4J `CharsetRecog_2022JP`）。
final class CharsetRecog2022JP: CharsetRecognizer {
    var name: String { "ISO-2022-JP" }

    func match(_ det: CharsetDetectorEngine, index: Int) -> CharsetMatch? {
        let confidence = match2022Sequences(
            text: det.inputBytes, textLen: det.inputLen, escapeSequences: CharsetTables.escape2022JP)
        return confidence == 0
            ? nil
            : CharsetMatch(confidence: confidence, name: name, language: language, index: index)
    }
}

/// ISO-2022-KR 识别器（ICU4J `CharsetRecog_2022KR`）。
final class CharsetRecog2022KR: CharsetRecognizer {
    var name: String { "ISO-2022-KR" }

    func match(_ det: CharsetDetectorEngine, index: Int) -> CharsetMatch? {
        let confidence = match2022Sequences(
            text: det.inputBytes, textLen: det.inputLen, escapeSequences: CharsetTables.escape2022KR)
        return confidence == 0
            ? nil
            : CharsetMatch(confidence: confidence, name: name, language: language, index: index)
    }
}

/// ISO-2022-CN 识别器（ICU4J `CharsetRecog_2022CN`）。
final class CharsetRecog2022CN: CharsetRecognizer {
    var name: String { "ISO-2022-CN" }

    func match(_ det: CharsetDetectorEngine, index: Int) -> CharsetMatch? {
        let confidence = match2022Sequences(
            text: det.inputBytes, textLen: det.inputLen, escapeSequences: CharsetTables.escape2022CN)
        return confidence == 0
            ? nil
            : CharsetMatch(confidence: confidence, name: name, language: language, index: index)
    }
}