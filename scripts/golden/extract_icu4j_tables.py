#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
extract_icu4j_tables.py —— 从 legado 的 icu4j Java 源码中提取全部数据表（byteMap/ngrams/
commonChars/escapeSequences/unshapeMap），生成 Swift 源文件 CharsetTables.swift。
表的数值与 Java 逐字一致（脚本生成，禁止手改；如需重生成：python3 extract_icu4j_tables.py）。
"""
import re
import io
import os

ICU4J_DIR = "/var/minis/workspace/legado2/legado-E-main/app/src/main/java/io/legado/app/lib/icu4j"
OUT = "/var/minis/workspace/bookon/bookon-main/Sources/LegadoBookSource/Network/CharsetDetector/CharsetTables.swift"


def strip_comments(src):
    # 去掉 /* */ 与 // 注释（保留字符串字面量内的内容——本文件无字符串表，lang 名是 "xx" 双引号串，安全）
    src = re.sub(r"/\*.*?\*/", "", src, flags=re.S)
    src = re.sub(r"//[^\n]*", "", src)
    return src


def extract_byte_array(src, name):
    """匹配 static ... byte[] NAME = { ... }; 返回 [int]（无符号值）"""
    m = re.search(r"byte\[\]\s*" + name + r"\s*=\s*\{(.*?)\};", src, flags=re.S)
    if not m:
        return None
    body = m.group(1)
    vals = re.findall(r"\(byte\)\s*0x([0-9A-Fa-f]+)", body)
    return [int(v, 16) for v in vals]


def extract_int_array(src, name):
    m = re.search(r"int\[\]\s*" + name + r"\s*=\s*\{(.*?)\};", src, flags=re.S)
    if not m:
        return None
    body = m.group(1)
    vals = re.findall(r"0x([0-9A-Fa-f]+)", body)
    return [int(v, 16) for v in vals]


def extract_lang_lists(src, cls_name, table_name):
    """提取 static class CLS 内 private static final NGramsPlusLang[] TABLE = {...}"""
    cls_m = re.search(r"static\s+class\s+" + cls_name + r"\b(.*?)(?=\n\s*static\s+class\s+|\n\s*abstract\s+static\s+class\s+)", src, flags=re.S)
    if not cls_m:
        return []
    body = cls_m.group(1)
    m = re.search(re.escape(table_name) + r"\s*=\s*new\s+NGramsPlusLang\[\]\s*\{(.*?)\};", body, flags=re.S)
    if not m:
        return []
    block = m.group(1)
    out = []
    for lm in re.finditer(r'new\s+NGramsPlusLang\(\s*"([^"]*)"\s*,\s*new\s+int\[\]\s*\{(.*?)\}\s*\)', block, flags=re.S):
        lang = lm.group(1)
        vals = [int(v, 16) for v in re.findall(r"0x([0-9A-Fa-f]+)", lm.group(2))]
        out.append((lang, vals))
    return out


def extract_class_body(src, cls_name):
    """提取整个 static/abstract static class 的文本"""
    m = re.search(r"(?:abstract\s+)?static\s+class\s+" + cls_name + r"\b(.*?)(?=\n\s*(?:abstract\s+)?static\s+class\s+|\Z)", src, flags=re.S)
    return m.group(1) if m else None


def fmt_bytes(values):
    """256 字节数组 → Swift 8 个一行的字面量"""
    lines = []
    for i in range(0, len(values), 8):
        chunk = ", ".join("0x%02X" % v for v in values[i:i + 8])
        lines.append("        " + chunk + ",")
    return "\n".join(lines)


def fmt_ints(values, per_line=8):
    lines = []
    for i in range(0, len(values), per_line):
        chunk = ", ".join("0x%X" % v for v in values[i:i + per_line])
        lines.append("        " + chunk + ",")
    return "\n".join(lines)


def main():
    sbcs = open(os.path.join(ICU4J_DIR, "CharsetRecog_sbcs.java"), encoding="utf-8").read()
    mbcs = open(os.path.join(ICU4J_DIR, "CharsetRecog_mbcs.java"), encoding="utf-8").read()
    p2022 = open(os.path.join(ICU4J_DIR, "CharsetRecog_2022.java"), encoding="utf-8").read()

    sbcs_s = strip_comments(sbcs)
    mbcs_s = strip_comments(mbcs)
    p2022_s = strip_comments(p2022)

    buf = io.StringIO()
    w = buf.write

    w("""// 本文件由 scripts/golden/extract_icu4j_tables.py 从 legado icu4j Java 源码自动生成。
// 表中数值与 CharsetRecog_sbcs.java / CharsetRecog_mbcs.java / CharsetRecog_2022.java 逐字一致。
// 禁止手改；重新生成：python3 scripts/golden/extract_icu4j_tables.py
//
// 对应 Kotlin/Java 位置：
//   app/src/main/java/io/legado/app/lib/icu4j/CharsetRecog_sbcs.java
//   app/src/main/java/io/legado/app/lib/icu4j/CharsetRecog_mbcs.java
//   app/src/main/java/io/legado/app/lib/icu4j/CharsetRecog_2022.java
import Foundation

/// SBCS/MBCS/2022 识别器所需的数据表（源自 ICU4J，逐字搬运）。
enum CharsetTables {

""")

    # ---- 2022 escape sequences ----
    for cls, var in [("CharsetRecog_2022JP", "escape2022JP"), ("CharsetRecog_2022KR", "escape2022KR"), ("CharsetRecog_2022CN", "escape2022CN")]:
        body = extract_class_body(p2022_s, cls)
        seqs = re.findall(r"\{(0x[0-9A-Fa-f]+(?:,\s*0x[0-9A-Fa-f]+)*)\}", body or "")
        w("    /// ISO-2022 转义序列表（ICU4J %s.escapeSequences）\n" % cls)
        w("    static let %s: [[UInt8]] = [\n" % var)
        for seq in seqs:
            vals = [int(v, 16) for v in re.findall(r"0x([0-9A-Fa-f]+)", seq)]
            w("        [%s],\n" % ", ".join("0x%02X" % v for v in vals))
        w("    ]\n\n")

    # ---- mbcs commonChars ----
    for cls, var in [("CharsetRecog_sjis", "sjisCommonChars"), ("CharsetRecog_big5", "big5CommonChars"),
                     ("CharsetRecog_euc_jp", "eucJPCommonChars"), ("CharsetRecog_euc_kr", "eucKRCommonChars"),
                     ("CharsetRecog_gb_18030", "gb18030CommonChars")]:
        body = extract_class_body(mbcs_s, cls)
        m = re.search(r"int\[\]\s*commonChars\s*=\s*\{(.*?)\};", body or "", flags=re.S)
        vals = [int(v, 16) for v in re.findall(r"0x([0-9A-Fa-f]+)", m.group(1))] if m else []
        w("    /// 常用字符表（ICU4J %s.commonChars）\n" % cls)
        w("    static let %s: [Int] = [\n" % var)
        w(fmt_ints(vals) + "\n")
        w("    ]\n\n")

    # ---- sbcs byteMaps ----
    maps = [
        ("CharsetRecog_8859_1", "byteMap8859_1", 256),
        ("CharsetRecog_8859_2", "byteMap8859_2", 256),
        ("CharsetRecog_8859_5", "byteMap8859_5", 256),
        ("CharsetRecog_8859_6", "byteMap8859_6", 256),
        ("CharsetRecog_8859_7", "byteMap8859_7", 256),
        ("CharsetRecog_8859_8", "byteMap8859_8", 256),
        ("CharsetRecog_8859_9", "byteMap8859_9", 256),
        ("CharsetRecog_windows_1251", "byteMap1251", 256),
        ("CharsetRecog_windows_1256", "byteMap1256", 256),
        ("CharsetRecog_KOI8_R", "byteMapKOI8R", 256),
        ("CharsetRecog_IBM424_he", "byteMapIBM424", 256),
        ("CharsetRecog_IBM420_ar", "byteMapIBM420", 256),
    ]
    for cls, var, expect in maps:
        body = extract_class_body(sbcs_s, cls)
        vals = extract_byte_array(body or "", "byteMap") if body else None
        assert vals and len(vals) == expect, (cls, len(vals) if vals else 0)
        w("    /// byteMap（ICU4J %s.byteMap）\n" % cls)
        w("    static let %s: [UInt8] = [\n" % var)
        w(fmt_bytes(vals) + "\n")
        w("    ]\n\n")

    # ---- sbcs ngrams（每语言表）----
    lang_tables = [
        ("CharsetRecog_8859_1", "ngrams_8859_1", "ngrams8859_1"),
        ("CharsetRecog_8859_2", "ngrams_8859_2", "ngrams8859_2"),
    ]
    for cls, table, var in lang_tables:
        lists = extract_lang_lists(sbcs_s, cls, table)
        w("    /// 语言 ngram 表（ICU4J %s.%s）\n" % (cls, table))
        w("    static let %s: [(lang: String, ngrams: [Int])] = [\n" % var)
        for lang, vals in lists:
            w("        (lang: \"%s\", ngrams: [\n" % lang)
            w(fmt_ints(vals) + "\n")
            w("        ]),\n")
        w("    ]\n\n")

    # ---- 单表 sbcs ngrams ----
    single_ngrams = [
        ("CharsetRecog_8859_5_ru", "ngrams8859_5_ru"),
        ("CharsetRecog_8859_6_ar", "ngrams8859_6_ar"),
        ("CharsetRecog_8859_7_el", "ngrams8859_7_el"),
        ("CharsetRecog_8859_8_I_he", "ngrams8859_8_I_he"),
        ("CharsetRecog_8859_8_he", "ngrams8859_8_he"),
        ("CharsetRecog_8859_9_tr", "ngrams8859_9_tr"),
        ("CharsetRecog_windows_1251", "ngrams1251"),
        ("CharsetRecog_windows_1256", "ngrams1256"),
        ("CharsetRecog_KOI8_R", "ngramsKOI8R"),
        ("CharsetRecog_IBM424_he_rtl", "ngramsIBM424_rtl"),
        ("CharsetRecog_IBM424_he_ltr", "ngramsIBM424_ltr"),
        ("CharsetRecog_IBM420_ar_rtl", "ngramsIBM420_rtl"),
        ("CharsetRecog_IBM420_ar_ltr", "ngramsIBM420_ltr"),
    ]
    for cls, var in single_ngrams:
        body = extract_class_body(sbcs_s, cls)
        vals = extract_int_array(body or "", "ngrams") if body else None
        assert vals and len(vals) == 64, (cls, len(vals) if vals else 0)
        w("    /// ngram 表（ICU4J %s.ngrams）\n" % cls)
        w("    static let %s: [Int] = [\n" % var)
        w(fmt_ints(vals) + "\n")
        w("    ]\n\n")

    # ---- IBM420 unshapeMap ----
    body = extract_class_body(sbcs_s, "NGramParser_IBM420")
    m = re.search(r"byte\[\]\s*unshapeMap\s*=\s*\{(.*?)\};", body or "", flags=re.S)
    vals = [int(v, 16) for v in re.findall(r"\(byte\)\s*0x([0-9A-Fa-f]+)", m.group(1))] if m else []
    assert len(vals) == 256
    w("    /// IBM420 整形还原表（ICU4J NGramParser_IBM420.unshapeMap）\n")
    w("    static let unshapeMap: [UInt8] = [\n")
    w(fmt_bytes(vals) + "\n")
    w("    ]\n")

    w("}\n")

    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    with open(OUT, "w", encoding="utf-8") as f:
        f.write(buf.getvalue())
    print("written:", OUT, len(buf.getvalue()), "bytes")


if __name__ == "__main__":
    main()