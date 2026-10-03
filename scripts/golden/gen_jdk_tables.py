#!/usr/bin/env python3
"""从 JDK 11 (jdk11u 标签 jdk-11.0.24+8) 的字符集源码/映射文件生成 Swift 解码表。

数据来源（与 CI golden job 的 temurin JDK 11 一致）：
  - sun/nio/cs/GB18030.java        —— GB18030 解码算法 + index1/index2 + decoderIndex1/2
  - sun/nio/cs/DoubleByte.java     —— 双字节解码规则（GBK/GB2312/Big5 共用）
  - make/data/charsetmapping/GBK.map / EUC_CN.map / Big5.map / MS1252.map

用法: python3 scripts/golden/gen_jdk_tables.py <jdk11_源码目录> <输出swift文件>
"""
import re, sys, os

def parse_java_short_array(text):
    """解析 'static final short x[] = { 12, 13, ... };' 的数值数组。"""
    m = re.search(r"=\s*\{(.*?)\}\s*;", text, re.S)
    return [int(v.strip()) for v in m.group(1).split(",") if v.strip()]

def parse_java_string_literals(text):
    """取 Java 源码里所有字符串字面量拼接（支持 \\uXXXX 转义与相邻字符串 + 连接）。"""
    parts = re.findall(r'"((?:[^"\\]|\\.)*)"', text)
    out = []
    for p in parts:
        s = []
        i = 0
        while i < len(p):
            c = p[i]
            if c == "\\":
                n = p[i+1]
                if n == "u":
                    s.append(chr(int(p[i+2:i+6], 16)))
                    i += 6
                elif n == "n": s.append("\n"); i += 2
                elif n == "t": s.append("\t"); i += 2
                elif n == "r": s.append("\r"); i += 2
                elif n == "\"": s.append("\""); i += 2
                elif n == "\\": s.append("\\"); i += 2
                else: s.append(n); i += 2
            else:
                s.append(c); i += 1
        out.append("".join(s))
    return "".join(out)

def parse_map(path, single_max=0x7F):
    """解析 .map 文件 → (singles: {byte: cp}, pairs: {(b1,b2): cp})。"""
    singles, pairs = {}, {}
    for line in open(path, encoding="utf-8"):
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        parts = line.split()
        if len(parts) < 2:
            continue
        b = int(parts[0], 16)
        u = int(parts[1].replace("U+", ""), 16)
        if b <= 0xFF:
            singles[b] = u
        else:
            pairs[(b >> 8, b & 0xFF)] = u
    return singles, pairs

def build_db_table(singles, pairs, b1_min, b1_max, b2_min, b2_max, fffd=0xFFFD):
    """双字节表 → (single[256], flat[(b1-min)*(b2max-b2min+1)] or None per lead)。
    返回: singles[256], leads{lead: [trail...]}（无映射的 lead 不在 dict 中）。"""
    s = [fffd] * 256
    for b, u in singles.items():
        s[b] = u
    leads = {}
    for (b1, b2), u in pairs.items():
        leads.setdefault(b1, {})[b2] = u
    return s, leads

def fmt_swift_u16(name, values, per_line=16):
    lines = [f"    static let {name}: [UInt16] = ["]
    for i in range(0, len(values), per_line):
        chunk = values[i:i+per_line]
        lines.append("        " + ", ".join(f"0x{v:04X}" for v in chunk) + ",")
    lines.append("    ]")
    return "\n".join(lines)

def main():
    src = sys.argv[1]
    out = sys.argv[2]

    # ---------- GB18030: 从 GB18030.java 解析 ----------
    gb = open(os.path.join(src, "GB18030.java"), encoding="utf-8").read()
    # 找到 innerIndexN / innerDecoderIndexN 各 String 变量
    def extract_strings(gbtext, prefix):
        names = sorted(set(re.findall(r"static\s+String\s+(" + prefix + r"\d+)", gbtext)))
        # 按出现顺序（保证与 index2 数组顺序一致）
        order = re.findall(r"static\s+(?:final\s+)?String\s+(" + prefix + r"\d+)", gbtext)
        seen, ordered = [], set()
        for n in order:
            if n not in seen:
                seen.append(n)
        return seen

    def var_text(gbtext, name):
        m = re.search(r"static\s+(?:final\s+)?String\s+" + name + r"\s*=(.*?)(?=;\s*(?:private|static|protected|public|\}))", gbtext, re.S)
        if not m:
            m = re.search(r"static\s+(?:final\s+)?String\s+" + name + r"\s*=(.*?);", gbtext, re.S)
        return m.group(1) if m else None

    # index1 / decoderIndex1
    index1 = parse_java_short_array(re.search(r"static\s+(?:final\s+)?short\s+index1\[\]\s*=\s*\{(.*?)\}\s*;", gb, re.S).group(0))
    decoder_index1 = parse_java_short_array(re.search(r"static\s+(?:final\s+)?short\s+decoderIndex1\[\]\s*=\s*\{(.*?)\}\s*;", gb, re.S).group(0))

    index2_names = extract_strings(gb, "innerIndex")
    decoder_index2_names = extract_strings(gb, "innerDecoderIndex")
    index2 = [parse_java_string_literals(var_text(gb, n)) for n in index2_names]
    decoder_index2 = [parse_java_string_literals(var_text(gb, n)) for n in decoder_index2_names]

    # 2 字节表: decodeDouble(b1,b2): n=(index1[b1]&0xf)*191+(b2-0x40); index2[index1[b1]>>4]
    db2 = []
    for b1 in range(0x81, 0xFF):
        row = []
        for b2 in range(0x40, 0xFF):
            i1 = index1[b1]
            n = (i1 & 0xF) * 191 + (b2 - 0x40)
            row.append(ord(index2[i1 >> 4][n]))
        db2.extend(row)
    # 4 字节 BMP 表 getChar(offset): byte1=offset>>8, byte2=offset&0xFF
    dc = []
    for off in range(0x10000):
        b1, b2 = off >> 8, off & 0xFF
        i1 = decoder_index1[b1]
        n = (i1 & 0xF) * 256 + b2
        dc.append(ord(decoder_index2[i1 >> 4][n]))

    # ---------- GBK / GB2312 / Big5 / MS1252 ----------
    gbk_s, gbk_pairs = parse_map(os.path.join(src, "GBK.map"))
    euc_s, euc_pairs = parse_map(os.path.join(src, "EUC_CN.map"))
    b5_s, b5_pairs = parse_map(os.path.join(src, "Big5.map"))
    ms_s, ms_pairs = parse_map(os.path.join(src, "MS1252.map"))

    gbk_singles, gbk_leads = build_db_table(gbk_s, gbk_pairs, 0x81, 0xFE, 0x40, 0xFE)
    euc_singles, euc_leads = build_db_table(euc_s, euc_pairs, 0xA1, 0xF7, 0xA1, 0xFE)
    b5_singles, b5_leads = build_db_table(b5_s, b5_pairs, 0xA1, 0xF9, 0x40, 0xFE)

    def flat(leads, b1_min, b1_max, b2_min, b2_max, fffd=0xFFFD):
        """lead 有映射 → 全 trail 范围数组；无映射 → None。"""
        table = []
        for b1 in range(b1_min, b1_max + 1):
            if b1 in leads:
                row = []
                for b2 in range(b2_min, b2_max + 1):
                    row.append(leads[b1].get(b2, fffd))
                table.append(row)
            else:
                table.append(None)  # 非 lead
        return table

    gbk_t = flat(gbk_leads, 0x81, 0xFE, 0x40, 0xFE)
    euc_t = flat(euc_leads, 0xA1, 0xF7, 0xA1, 0xFE)
    b5_t = flat(b5_leads, 0xA1, 0xF9, 0x40, 0xFE)

    def pack(singles, t, b2_min, b2_max):
        """→ (single[256], flat 数组（每行 b2max-b2min+1 值, 行内 FFFD by row 不存在）, lead_mask[256])"""
        single = [0xFFFD] * 256
        for b, u in singles.items():
            single[b] = u
        flat_rows, mask = [], [0] * 256
        for i, row in enumerate(t):
            b1 = i  # 调用方注意: flat() 按 b1_min 起步
            pass
        return single

    # 直接生成: 每表给出 singles 数组 + (b1_min) 起点 + 行数组 + 有效 lead 掩码
    def emit(rows, b1_min, b1_max):
        r = []
        for b1 in range(b1_min, b1_max + 1):
            row = rows[b1 - b1_min]
            if row is None:
                continue
            r.extend(row)
        return r

    gbk_flat = emit(gbk_t, 0x81, 0xFE)
    euc_flat = emit(euc_t, 0xA1, 0xF7)
    b5_flat = emit(b5_t, 0xA1, 0xF9)
    # lead 存在性掩码（含 trail 全 FFFD 但 lead 存在的行 — 这里 lead 存在即行非 None）
    gbk_lead = [1 if gbk_t[b1 - 0x81] is not None else 0 for b1 in range(0x81, 0xFF)]
    euc_lead = [1 if euc_t[b1 - 0xA1] is not None else 0 for b1 in range(0xA1, 0xF8)]
    b5_lead = [1 if b5_t[b1 - 0xA1] is not None else 0 for b1 in range(0xA1, 0xFA)]

    ms_single = [0xFFFD] * 256
    for b, u in ms_s.items():
        ms_single[b] = u

    lines = []
    lines.append("// 本文件由 scripts/golden/gen_jdk_tables.py 自动生成，禁止手改。")
    lines.append("// 数据源：OpenJDK jdk11u（标签 jdk-11.0.24+8，与 CI golden 的 temurin JDK 11 相同）：")
    lines.append("//   sun/nio/cs/GB18030.java（index1/index2、decoderIndex1/decoderIndex2）")
    lines.append("//   make/data/charsetmapping/{GBK,EUC_CN,Big5,MS1252}.map（DoubleByte/SingleByte 表）")
    lines.append("import Foundation")
    lines.append("")
    lines.append("/// 文本解码用字符映射表（与 JDK 11 解码表逐字一致）。")
    lines.append("enum TextDecodeTables {")
    lines.append("    /// U+FFFD 替换字符（JDK decoder 的默认 replacement）。")
    lines.append("    static let replacementChar: UInt16 = 0xFFFD")
    lines.append("")

    # GB18030 2字节: 126 个 lead × 191 trails
    lines.append("    /// GB18030 双字节区（JDK GB18030.Decoder.decodeDouble，index1/index2 展平）。")
    lines.append("    /// 索引 = (b1 - 0x81) * 191 + (b2 - 0x40)；值 0xFFFD 表示无映射。")
    lines.append(fmt_swift_u16("gb18030Double", db2))
    lines.append("")
    # GB18030 4字节 BMP
    lines.append("    /// GB18030 四字节区 BMP 查表（JDK GB18030.Decoder.getChar，decoderIndex1/decoderIndex2 展平为 65536 项）。")
    lines.append("    /// 索引 = offset（JDK decodeLoop 中的 offset 公式）；值 0xFFFD 表示无映射。")
    lines.append(fmt_swift_u16("gb18030FourBmp", dc))
    lines.append("")
    # 各双字节表: singles + flat + leadMask
    lines.append("    /// GBK 单字节区（JDK GBK b2cSB：0x00-0x7F 为 ASCII，其余 FFFD）。")
    lines.append(fmt_swift_u16("gbkSingle", gbk_singles))
    lines.append("")
    lines.append("    /// GBK 双字节区（JDK GBK b2c，minmax 0x81-0xFE / 0x40-0xFE）。")
    lines.append("    /// 索引 = (b1 - 0x81) * 191 + (b2 - 0x40)；0xFFFD = 无映射。")
    lines.append(fmt_swift_u16("gbkDouble", gbk_flat))
    lines.append("")
    lines.append("    /// GBK lead 有效掩码（1 = 该 lead 在映射表中有条目）。")
    lines.append(fmt_swift_u16("gbkLead", gbk_lead))
    lines.append("")
    lines.append("    /// GB2312（EUC-CN）单字节区（JDK EUC_CN b2cSB）。")
    lines.append(fmt_swift_u16("gb2312Single", euc_singles))
    lines.append("")
    lines.append("    /// GB2312（EUC-CN）双字节区（JDK EUC_CN b2c，minmax 0xA1-0xF7 / 0xA1-0xFE）。")
    lines.append("    /// 索引 = (b1 - 0xA1) * 94 + (b2 - 0xA1)；0xFFFD = 无映射。")
    lines.append(fmt_swift_u16("gb2312Double", euc_flat))
    lines.append("")
    lines.append("    /// GB2312 lead 有效掩码（0xAA-0xAF 为保留区，非有效 lead）。")
    lines.append(fmt_swift_u16("gb2312Lead", euc_lead))
    lines.append("")
    lines.append("    /// Big5 单字节区（JDK Big5 b2cSB）。")
    lines.append(fmt_swift_u16("big5Single", b5_singles))
    lines.append("")
    lines.append("    /// Big5 双字节区（JDK Big5 b2c，minmax 0xA1-0xF9 / 0x40-0xFE）。")
    lines.append("    /// 索引 = (b1 - 0xA1) * 191 + (b2 - 0x40)；0xFFFD = 无映射。")
    lines.append(fmt_swift_u16("big5Double", b5_flat))
    lines.append("")
    lines.append("    /// Big5 lead 有效掩码（0xC8 为保留区，非有效 lead）。")
    lines.append(fmt_swift_u16("big5Lead", b5_lead))
    lines.append("")
    lines.append("    /// windows-1252 单字节表（JDK MS1252 b2c；0x81/0x8D/0x8F/0x90/0x9D 为 FFFD）。")
    lines.append(fmt_swift_u16("windows1252", ms_single))
    lines.append("")
    lines.append("}")
    lines.append("")
    open(out, "w", encoding="utf-8").write("\n".join(lines))

    # 统计
    print(f"gb18030 2-byte: {len(db2)} entries")
    print(f"gb18030 4-byte BMP: {len(dc)} entries (getChar)")
    print(f"gbk: singles={len(gbk_singles)} double={len(gbk_flat)} leads={sum(gbk_lead)}")
    print(f"gb2312: singles={len(euc_singles)} double={len(euc_flat)} leads={sum(euc_lead)}")
    print(f"big5: singles={len(b5_singles)} double={len(b5_flat)} leads={sum(b5_lead)}")
    print(f"windows1252: {len(ms_single)} bytes")
    print(f"index2 tables: {len(index2)}; decoderIndex2 tables: {len(decoder_index2)}")

if __name__ == "__main__":
    main()