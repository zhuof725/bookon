#!/usr/bin/env python3
"""JDK 11 字符集解码表的解析 + 按 JDK 11 规则的解码器（供用例生成时做安全校验）。

数据来源：/tmp/jdk11/（jdk11u 标签 jdk-11.0.24+8，与 CI golden 的 temurin JDK 11 一致）。
仅用于开发期校验：生成 golden 用例时，确保 Python codec 编码出的字节串
用「JDK 规则」解码后与原文一致（避开 JDK 与 Python 有出入的个别码位）。
"""
import re

# ---------------- 解析 JDK 源码/映射表 ----------------

def parse_java_short_array(text):
    m = re.search(r"=\s*\{(.*?)\}\s*;", text, re.S)
    return [int(v.strip()) for v in m.group(1).split(",") if v.strip()]

def parse_java_string_literals(text):
    parts = re.findall(r'"((?:[^"\\]|\\.)*)"', text)
    out = []
    for p in parts:
        s = []
        i = 0
        while i < len(p):
            c = p[i]
            if c == "\\":
                n = p[i + 1]
                if n == "u":
                    s.append(chr(int(p[i+2:i+6], 16))); i += 6
                elif n == "n": s.append("\n"); i += 2
                elif n == "t": s.append("\t"); i += 2
                elif n == "r": s.append("\r"); i += 2
                elif n == '"': s.append('"'); i += 2
                elif n == "\\": s.append("\\"); i += 2
                else: s.append(n); i += 2
            else:
                s.append(c); i += 1
        out.append("".join(s))
    return "".join(out)

def _var_text(text, name):
    m = re.search(r"static\s+(?:final\s+)?String\s+" + name + r"\s*=(.*?)(?=;\s*(?:private|static|protected|public|\}))", text, re.S)
    if not m:
        m = re.search(r"static\s+(?:final\s+)?String\s+" + name + r"\s*=(.*?);", text, re.S)
    return m.group(1)

def _var_names(text, prefix):
    seen = []
    for n in re.findall(r"static\s+(?:final\s+)?String\s+(" + prefix + r"\d+)", text):
        if n not in seen:
            seen.append(n)
    return seen

def parse_map(path):
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

class JdkTables:
    """JDK 11 解码表。"""

    def __init__(self, jdk_dir):
        self.dir = jdk_dir
        gb = open(f"{jdk_dir}/GB18030.java", encoding="utf-8").read()
        self.index1 = parse_java_short_array(
            re.search(r"static\s+(?:final\s+)?short\s+index1\[\]\s*=\s*\{(.*?)\}\s*;", gb, re.S).group(0))
        self.decoder_index1 = parse_java_short_array(
            re.search(r"static\s+(?:final\s+)?short\s+decoderIndex1\[\]\s*=\s*\{(.*?)\}\s*;", gb, re.S).group(0))
        self.index2 = {n: parse_java_string_literals(_var_text(gb, n)) for n in _var_names(gb, "innerIndex")}
        self.decoder_index2 = {n: parse_java_string_literals(_var_text(gb, n)) for n in _var_names(gb, "innerDecoderIndex")}
        # 双字节表
        self.gb18030_2 = {}
        for b1 in range(0x81, 0xFF):
            for b2 in range(0x40, 0xFF):
                i1 = self.index1[b1]
                n = (i1 & 0xF) * 191 + (b2 - 0x40)
                self.gb18030_2[(b1, b2)] = ord(self.index2["innerIndex%d" % (i1 >> 4)][n])
        # 四字节 BMP 表
        self.gb18030_4bmp = []
        for off in range(0x10000):
            b1, b2 = off >> 8, off & 0xFF
            i1 = self.decoder_index1[b1]
            n = (i1 & 0xF) * 256 + b2
            self.gb18030_4bmp.append(ord(self.decoder_index2["innerDecoderIndex%d" % (i1 >> 4)][n]))
        # GBK / GB2312 / Big5 / MS1252
        self.gbk_s, self.gbk_p = parse_map(f"{jdk_dir}/GBK.map")
        self.euc_s, self.euc_p = parse_map(f"{jdk_dir}/EUC_CN.map")
        self.b5_s, self.b5_p = parse_map(f"{jdk_dir}/Big5.map")
        self.ms_s, _ = parse_map(f"{jdk_dir}/MS1252.map")
        self.gbk_lead = {}
        for (b1, b2), u in self.gbk_p.items():
            self.gbk_lead.setdefault(b1, {})[b2] = u
        self.euc_lead = {}
        for (b1, b2), u in self.euc_p.items():
            self.euc_lead.setdefault(b1, {})[b2] = u
        self.b5_lead = {}
        for (b1, b2), u in self.b5_p.items():
            self.b5_lead.setdefault(b1, {})[b2] = u

    # ---------------- JDK 11 规则解码器 ----------------
    # 语义对应 sun.nio.cs 各 Decoder + String(byte[],cs) 的 REPLACE 行为。

    def decode_gb18030(self, data):
        out = []
        i, n = 0, len(data)
        while i < n:
            b1 = data[i]
            if (b1 & 0x80) == 0:
                out.append(chr(b1)); i += 1; continue
            if b1 < 0x81 or b1 > 0xFE:
                out.append("\uFFFD"); i += 1; continue
            if i + 1 >= n:
                out.append("\uFFFD"); i += 1; continue
            b2 = data[i + 1]
            if b2 < 0x30:
                out.append("\uFFFD"); i += 1; continue
            if 0x30 <= b2 <= 0x39:
                # 4 字节
                if i + 3 >= n:
                    out.append("\uFFFD"); i += 1; continue
                b3, b4 = data[i + 2], data[i + 3]
                if not (0x81 <= b3 <= 0xFE):
                    out.append("\uFFFD"); i += 3; continue
                if not (0x30 <= b4 <= 0x39):
                    out.append("\uFFFD"); i += 4; continue
                offset = (((b1 - 0x81) * 10 + (b2 - 0x30)) * 126 + b3 - 0x81) * 10 + b4 - 0x30
                if offset <= 0x4A62:
                    c = self.gb18030_4bmp[offset]
                    out.append(chr(c)); i += 4; continue
                if offset <= 0x82BC:
                    if 0x4A71 <= offset <= 0x4A78:
                        out.append(chr(self.gb18030_4bmp[offset]))
                    else:
                        out.append(chr(offset + 0x5543))
                    i += 4; continue
                if offset <= 0x830D:
                    out.append(chr(self.gb18030_4bmp[offset])); i += 4; continue
                if offset <= 0x93A8:
                    out.append(chr(offset + 0x6557)); i += 4; continue
                if offset <= 0x99FB:
                    out.append(chr(self.gb18030_4bmp[offset])); i += 4; continue
                if 0x2E248 <= offset < 0x12E248:
                    cp = offset - 0x1E248
                    out.append(chr(cp)); i += 4; continue
                out.append("\uFFFD"); i += 4; continue
            if b2 == 0x7F or b2 == 0xFF or b2 < 0x40:
                out.append("\uFFFD"); i += 2; continue
            out.append(chr(self.gb18030_2.get((b1, b2), 0xFFFD))); i += 2; continue
        return "".join(out)

    @staticmethod
    def _db_decode(data, singles, leads, b2_min, b2_max, fffd="\uFFFD"):
        """DoubleByte.Decoder 的 REPLACE 语义。"""
        out = []
        i, n = 0, len(data)
        while i < n:
            b1 = data[i]
            c = singles.get(b1, fffd)
            if c != fffd:
                out.append(chr(c)); i += 1; continue
            if i + 1 >= n:
                out.append(fffd); i += 1; continue
            b2 = data[i + 1]
            if b2 < b2_min or b2 > b2_max or (b1 not in leads) or leads[b1].get(b2, fffd) == fffd:
                # crMalformedOrUnmappable: b1 非 lead 或 b2 是 lead 或 b2 是单字节 → malformed(1)
                if b1 not in leads or b2 in leads or b2 in singles:
                    out.append(fffd); i += 1
                else:
                    out.append(fffd); i += 2
                continue
            out.append(chr(leads[b1][b2])); i += 2
        return "".join(out)

    def decode_gbk(self, data):
        return self._db_decode(data, self.gbk_s, self.gbk_lead, 0x40, 0xFE)

    def decode_gb2312(self, data):
        return self._db_decode(data, self.euc_s, self.euc_lead, 0xA1, 0xFE)

    def decode_big5(self, data):
        return self._db_decode(data, self.b5_s, self.b5_lead, 0x40, 0xFE)

    def decode_windows1252(self, data):
        return "".join(chr(self.ms_s.get(b, 0xFFFD)) for b in data)

    @staticmethod
    def decode_iso88591(data):
        return "".join(chr(b) for b in data)

    @staticmethod
    def _utf8_malformed_len3(b1, b2):
        return 1 if (b1 == 0xE0 and (b2 & 0xE0) == 0x80) or (b2 & 0xC0) != 0x80 else 2

    def decode_utf8(self, data):
        """JDK 11 sun.nio.cs.UTF_8 + REPLACE（String 路径）。"""
        out = []
        i, n = 0, len(data)
        while i < n:
            b1 = data[i]
            if b1 <= 0x7F:
                out.append(chr(b1)); i += 1; continue
            if 0xC2 <= b1 <= 0xDF:
                if i + 1 >= n or (data[i + 1] & 0xC0) != 0x80:
                    out.append("\uFFFD"); i += 1; continue
                out.append(chr(((b1 & 0x1F) << 6) | (data[i + 1] & 0x3F))); i += 2; continue
            if 0xE0 <= b1 <= 0xEF:
                rem = n - i
                if rem < 3:
                    if rem > 1 and ((b1 == 0xE0 and (data[i+1] & 0xE0) == 0x80) or (data[i+1] & 0xC0) != 0x80):
                        out.append("\uFFFD"); i += 1; continue
                    out.append("\uFFFD"); i += rem; continue
                b2, b3 = data[i + 1], data[i + 2]
                mal = (b1 == 0xE0 and (b2 & 0xE0) == 0x80) or (b2 & 0xC0) != 0x80 or (b3 & 0xC0) != 0x80
                if mal:
                    out.append("\uFFFD"); i += self._utf8_malformed_len3(b1, b2); continue
                c = ((b1 & 0x0F) << 12) | ((b2 & 0x3F) << 6) | (b3 & 0x3F)
                if 0xD800 <= c <= 0xDFFF:
                    out.append("\uFFFD"); i += 3; continue
                out.append(chr(c)); i += 3; continue
            if 0xF0 <= b1 <= 0xF4:
                rem = n - i
                if rem < 4:
                    if b1 > 0xF4 or (rem > 1 and self._malformed4_2(b1, data[i+1])):
                        out.append("\uFFFD"); i += 1; continue
                    if rem > 2 and (data[i + 2] & 0xC0) != 0x80:
                        out.append("\uFFFD"); i += 2; continue
                    out.append("\uFFFD"); i += rem; continue
                b2, b3, b4 = data[i + 1], data[i + 2], data[i + 3]
                uc = ((b1 & 0x07) << 18) | ((b2 & 0x3F) << 12) | ((b3 & 0x3F) << 6) | (b4 & 0x3F)
                if (b2 & 0xC0) != 0x80 or (b3 & 0xC0) != 0x80 or (b4 & 0xC0) != 0x80 or not (0x10000 <= uc <= 0x10FFFF):
                    ln = 1
                    if not (b1 > 0xF4 or (b1 == 0xF0 and (b2 < 0x90 or b2 > 0xBF)) or (b1 == 0xF4 and (b2 & 0xF0) != 0x80) or (b2 & 0xC0) != 0x80):
                        ln = 2 if (b3 & 0xC0) != 0x80 else 3
                    out.append("\uFFFD"); i += ln; continue
                out.append(chr(uc)); i += 4; continue
            out.append("\uFFFD"); i += 1; continue
        return "".join(out)

    @staticmethod
    def _malformed4_2(b1, b2):
        return (b1 == 0xF0 and (b2 < 0x90 or b2 > 0xBF)) or (b1 == 0xF4 and (b2 & 0xF0) != 0x80) or (b2 & 0xC0) != 0x80

    def decode_utf16(self, data, little):
        """JDK 11 UnicodeDecoder + REPLACE（UTF-16LE/BE；含 0xFFFE 反向 BOM → malformed 规则）。"""
        out = []
        i, n = 0, len(data)
        while i + 1 < n:
            b1, b2 = data[i], data[i + 1]
            c = (b2 << 8 | b1) if little else (b1 << 8 | b2)
            if c == 0xFFFE:
                out.append("\uFFFD"); i += 2; continue
            if 0xD800 <= c <= 0xDBFF:
                if i + 4 > n:
                    # 结尾不完整代理对：JDK decodeLoop UNDERFLOW → end-of-input
                    # malformedForLength(剩余字节) → 一个 FFFD 消费全部剩余
                    out.append("\uFFFD")
                    break
                b3, b4 = data[i + 2], data[i + 3]
                c2 = (b4 << 8 | b3) if little else (b3 << 8 | b4)
                if not (0xDC00 <= c2 <= 0xDFFF):
                    out.append("\uFFFD"); i += 4; continue
                out.append(chr(0x10000 + ((c - 0xD800) << 10) + (c2 - 0xDC00))); i += 4; continue
            if 0xDC00 <= c <= 0xDFFF:
                out.append("\uFFFD"); i += 2; continue
            out.append(chr(c)); i += 2
        if i < n:
            out.append("\uFFFD")
        return "".join(out)