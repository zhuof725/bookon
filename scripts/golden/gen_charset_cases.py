#!/usr/bin/env python3
"""生成 scripts/golden/cases/charset_cases.json（≥80 条合成样本）。

所有样本均为「合成样本（synthetic）」，由本脚本按确定性规则生成，
并做双重校验：
  1) Python codec 编码 → JDK 11 规则解码（scripts/golden/jdk_tables.py）回读 == 原文；
  2) Python codec 自身解码 == 原文。
校验失败即中止（说明样本落在了 Python 与 JDK 有出入的码位上）。

用法: python3 scripts/golden/gen_charset_cases.py <jdk11_源码目录>
"""
import json, sys, os

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from jdk_tables import JdkTables

JDK_DIR = sys.argv[1] if len(sys.argv) > 1 else "/tmp/jdk11"
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "cases", "charset_cases.json")

t = JdkTables(JDK_DIR)

def oracle_decode(data, charset):
    cs = charset.lower().replace("_", "-").replace(" ", "")
    if cs in ("utf-8", "utf8"):
        return t.decode_utf8(data)
    if cs in ("gbk", "cp936", "windows-936", "ms936"):
        return t.decode_gbk(data)
    if cs in ("gb2312", "euc-cn", "euccn", "x-euc-cn"):
        return t.decode_gb2312(data)
    if cs == "gb18030":
        return t.decode_gb18030(data)
    if cs in ("big5", "big-5"):
        return t.decode_big5(data)
    if cs in ("utf-16le", "utf16le"):
        return t.decode_utf16(data, True)
    if cs in ("utf-16be", "utf16be"):
        return t.decode_utf16(data, False)
    if cs in ("iso-8859-1", "iso8859-1", "latin1", "l1"):
        return t.decode_iso88591(data)
    if cs in ("windows-1252", "cp1252"):
        return t.decode_windows1252(data)
    raise ValueError("unknown charset " + charset)

PY_CODEC = {
    "utf-8": "utf-8", "gbk": "gbk", "gb2312": "gb2312", "gb18030": "gb18030",
    "big5": "big5", "utf-16le": "utf-16le", "utf-16be": "utf-16be",
    "iso-8859-1": "latin-1", "windows-1252": "cp1252",
}

cases = []

def add(name, category, hexbytes=None, text=None, codec=None, explicit=None, header=None,
        expected_charset=None):
    """text+codec → 编码并校验回读；hexbytes → 原样使用（expected_charset 指定解码校验）。"""
    if text is not None:
        data = text.encode(PY_CODEC[codec])
        dec = oracle_decode(data, codec)
        assert dec == text, f"[{name}] JDK规则回读不一致: {dec!r} != {text!r}"
        assert data.decode(PY_CODEC[codec]) == text, f"[{name}] python回读不一致"
    else:
        data = bytes.fromhex(hexbytes)
        if expected_charset:
            dec = oracle_decode(data, expected_charset)
            # 只打印，不断言（raw 样本常用于乱码/边界）
            print(f"[{name}] raw {len(data)}B 按 {expected_charset} 解码: {dec!r}")
    c = {"name": name, "category": category, "hex": data.hex().upper()}
    if explicit:
        c["explicitCharset"] = explicit
    if header:
        c["contentTypeHeader"] = header
    cases.append(c)

# ---------------- UTF-8 ----------------
zh = "第一章 你好世界，这是字符集检测测试。"
add("utf8_chinese_bom", "utf8", text="\ufeff" + zh, codec="utf-8")
add("utf8_chinese", "utf8", text=zh, codec="utf-8")
add("utf8_emoji", "utf8", text="Hello 😀 世界 🌍", codec="utf-8")
add("utf8_mixed", "utf8", text="Hello 世界 123, test.", codec="utf-8")
add("utf8_latin", "utf8", text="café déjà vu — naïve", codec="utf-8")
add("utf8_punct", "utf8", text="《》「」『』（）——……！？", codec="utf-8")
# 乱码/边界
add("utf8_garbage_1", "garbage", hexbytes="E228A1")
add("utf8_truncated_3byte", "garbage", hexbytes="E282")
add("utf8_overlong_c0", "garbage", hexbytes="C0AF")
add("utf8_ff", "garbage", hexbytes="FF")
add("utf8_lone_continuation", "garbage", hexbytes="8041")
add("utf8_surrogate_encoded", "garbage", hexbytes="EDA080")
add("utf8_4byte_overlong", "garbage", hexbytes="F0808080")
add("utf8_4byte_too_high", "garbage", hexbytes="F4908080")
add("utf8_lead_at_end", "garbage", hexbytes="E2")
add("utf8_4byte_truncated", "garbage", hexbytes="F180")
add("utf8_4byte_bad3rd", "garbage", hexbytes="F18028")
add("utf8_e0_9f", "garbage", hexbytes="E09F80")
add("utf8_mixed_valid_invalid", "garbage", hexbytes="41E228A142E282AC43")

# ---------------- 纯 ASCII ----------------
add("ascii_plain", "ascii", text="The quick brown fox jumps over the lazy dog.", codec="utf-8")
add("ascii_short", "ascii", text="hello", codec="utf-8")
add("ascii_with_ws", "ascii", text="line1\nline2\tend\r\n", codec="utf-8")
add("ascii_numbers", "ascii", text="0123456789 123.456 -7e9", codec="utf-8")

# ---------------- 短样本 1-4 字节 ----------------
add("short_1_ascii", "short", hexbytes="41")
add("short_2_gbk_ni", "short", hexbytes="C4E3")
add("short_3_utf8_zhong", "short", hexbytes="E4B8AD")
add("short_4_emoji", "short", hexbytes="F09F9880")
add("short_1_lead", "short", hexbytes="81")
add("short_1_ff", "short", hexbytes="FF")
add("short_2_bom_le", "short", hexbytes="FFFE")
add("short_2_bom_be", "short", hexbytes="FEFF")
add("short_2_null_a", "short", hexbytes="0041")
add("short_3_incomplete_utf16", "short", hexbytes="410042")

# ---------------- GBK / GB2312 / GB18030 / Big5 ----------------
add("gbk_chinese", "gbk", text="中文小说阅读测试，第一章。", codec="gbk")
add("gbk_fullwidth", "gbk", text="ＡＢＣ１２３（全角）测试", codec="gbk")
add("gbk_symbols", "gbk", text="，。！？：；“”『』《》——…·", codec="gbk")
add("gbk_mixed", "gbk", text="Hello 世界 2024 test.", codec="gbk")
add("gbk_common_book", "gbk", text="天行健，君子以自强不息。", codec="gbk")
add("gb2312_chinese", "gb2312", text="中华人民共和国中央人民政府", codec="gb2312")
add("gb2312_pinyin_like", "gb2312", text="新华字典词语解释示例", codec="gb2312")
add("gb18030_chinese", "gb18030", text="简体中文内容，兼容测试。", codec="gb18030")
add("gb18030_ext_a", "gb18030", text="\u3400\u3401\u4DBF 扩展A区", codec="gb18030")
add("gb18030_supp_plane", "gb18030", text="😀 扩展B \U00020000 \U00020001", codec="gb18030")
add("gb18030_last_cp", "gb18030", text="极限码位\U0010FFFF", codec="gb18030")
add("gb18030_euro", "gb18030", text="价格 €100 元", codec="gb18030")
add("big5_chinese", "big5", text="繁體中文小說閱讀測試", codec="big5")
add("big5_common", "big5", text="你好，世界！這是測試。", codec="big5")
add("big5_mixed", "big5", text="Book 小說 123 test", codec="big5")
add("big5_level2", "big5", text="龜鱉鶴鸛鶯鷹", codec="big5")
# raw 边界:GBK 扩展区(PUA)、GB18030-2005 增补（JDK 表与 Python 有出入的区域，显式 charset 规避检测器）
add("gbk_ext_pua", "gbk", hexbytes="A140A141A142", expected_charset="gbk", explicit="GBK")
add("gb18030_2005_a6f6", "gb18030", hexbytes="A6F6A6F7A6F8", expected_charset="gb18030", explicit="gb18030")
add("gb18030_2005_a740", "gb18030", hexbytes="A740A741A742", expected_charset="gb18030", explicit="gb18030")
add("gbk_a2e3_euro", "gbk", hexbytes="A2E3", expected_charset="gbk", explicit="gbk")
add("big5_a440", "big5", hexbytes="A440A441A442", expected_charset="big5", explicit="Big5")

# ---------------- UTF-16 ----------------
add("utf16le_bom", "utf16le", text="\ufeff中文测试文本", codec="utf-16le")
add("utf16le_nobom", "utf16le", text="中文测试文本", codec="utf-16le")
add("utf16be_bom", "utf16be", text="\ufeff中文测试文本", codec="utf-16be")
add("utf16be_nobom", "utf16be", text="中文测试文本", codec="utf-16be")
add("utf16le_ascii", "utf16le", text="Hello World", codec="utf-16le")
add("utf16le_emoji", "utf16le", text="😀😁😂", codec="utf-16le")
add("utf16le_unpaired_high", "garbage", hexbytes="00D84100", expected_charset="utf-16le", explicit="UTF-16LE")
add("utf16be_reversed_bom", "garbage", hexbytes="FFFE", expected_charset="utf-16be", explicit="UTF-16BE")
add("utf16le_odd_trailing", "garbage", hexbytes="4100420041", expected_charset="utf-16le", explicit="UTF-16LE")

# ---------------- ISO-8859-1 / windows-1252 ----------------
add("iso_latin1_accent", "iso88591", text="café déjà vu naïve", codec="iso-8859-1")
add("iso_latin1_control", "iso88591", hexbytes="41809F42", expected_charset="iso-8859-1", explicit="ISO-8859-1")
add("cp1252_smart_quotes", "cp1252", text="\u201cquoted\u201d \u2014 dash \u20ac", codec="windows-1252")
add("cp1252_undefined", "cp1252", hexbytes="41818D8F909D42", expected_charset="windows-1252", explicit="windows-1252")
add("cp1252_mixed", "cp1252", text="naïve façade œuvre", codec="windows-1252")

# ---------------- HTML meta ----------------
GBK_HTML_BODY = "第一章 内容正文。"
def html_bytes(charset_attr, body_text, body_codec, head_extra=""):
    head = "<head><meta charset=\"%s\">%s</head>" % (charset_attr, head_extra)
    html = "<!DOCTYPE html><html>%s<body><p>%s</p></body></html>" % (head, body_text)
    return html.encode(body_codec)

cases.append({
    "name": "html_meta_charset_gbk", "category": "html_meta",
    "hex": html_bytes("gbk", GBK_HTML_BODY, "gbk").hex().upper()})
cases.append({
    "name": "html_meta_charset_utf8", "category": "html_meta",
    "hex": html_bytes("UTF-8", "你好 UTF-8 页面", "utf-8").hex().upper()})
cases.append({
    "name": "html_meta_charset_utf8_no_quotes", "category": "html_meta",
    "hex": ("<!DOCTYPE html><html><head><meta charset=utf-8></head><body>"
            "<p>无引号属性</p></body></html>").encode("utf-8").hex().upper()})
cases.append({
    "name": "html_meta_http_equiv", "category": "html_meta",
    "hex": ("<!DOCTYPE html><html><head><meta http-equiv=\"Content-Type\" "
            "content=\"text/html; charset=gb2312\"></head><body><p>新华字典词语解释示例</p></body></html>")
    .encode("gb2312").hex().upper()})
cases.append({
    "name": "html_meta_case_upper", "category": "html_meta",
    "hex": ("<HTML><HEAD><META CHARSET='GBK'></HEAD><BODY><P>大小写变体</P></BODY></HTML>")
    .encode("gbk").hex().upper()})
cases.append({
    "name": "html_meta_equiv_case_upper", "category": "html_meta",
    "hex": ("<html><head><meta HTTP-EQUIV=\"CONTENT-TYPE\" CONTENT=\"text/html; CHARSET=gbk\">"
            "</head><body><p>大写属性</p></body></html>").encode("gbk").hex().upper()})
cases.append({
    "name": "html_meta_second_wins", "category": "html_meta",
    "hex": ("<html><head><meta name=\"description\" content=\"no\">"
            "<meta charset=\"big5\"></head><body><p>繁體中文</p></body></html>")
    .encode("big5").hex().upper()})
cases.append({
    "name": "html_meta_first_charset_wins", "category": "html_meta",
    "hex": ("<html><head><meta charset=\"utf-8\"><meta charset=\"gbk\"></head>"
            "<body><p>第一个生效</p></body></html>").encode("utf-8").hex().upper()})
cases.append({
    "name": "html_meta_content_no_semicolon", "category": "html_meta",
    "hex": ("<html><head><meta http-equiv=\"Content-Type\" content=\"GBK\"></head>"
            "<body><p>没有分号的 content</p></body></html>").encode("gbk").hex().upper()})
cases.append({
    "name": "html_meta_content_charset_tail", "category": "html_meta",
    "hex": ("<html><head><meta http-equiv=\"content-type\" content=\"text/html;charset=gb18030\">"
            "</head><body><p>简体中文内容</p></body></html>").encode("gb18030").hex().upper()})
cases.append({
    "name": "html_meta_no_head_tag", "category": "html_meta",
    "hex": ("<html><body><meta charset=\"gbk\"><p>没有 head 标签</p></body></html>")
    .encode("gbk").hex().upper()})
cases.append({
    "name": "html_no_meta_gbk", "category": "html_meta",
    "hex": ("<!DOCTYPE html><html><head><title>标题</title></head><body><p>没有 meta 的 GBK 页面</p></body></html>")
    .encode("gbk").hex().upper()})
cases.append({
    "name": "html_no_meta_utf8", "category": "html_meta",
    "hex": ("<!DOCTYPE html><html><head><title>标题</title></head><body><p>没有 meta 的 UTF-8 页面</p></body></html>")
    .encode("utf-8").hex().upper()})
cases.append({
    "name": "html_bom_utf8_meta", "category": "html_meta",
    "hex": ("\ufeff<!DOCTYPE html><html><head><meta charset=\"utf-8\"></head>"
            "<body><p>带 BOM 页面</p></body></html>").encode("utf-8").hex().upper()})
cases.append({
    "name": "html_meta_space_around_eq", "category": "html_meta",
    "hex": ("<html><head><meta charset = \"gbk\" ></head><body><p>等号两侧有空格</p></body></html>")
    .encode("gbk").hex().upper()})

# ---------------- 无 meta、中英混排、乱码 ----------------
add("mixed_cn_en_no_meta", "mixed", text="Chapter 1 第一章 Hello 世界。", codec="gbk")
add("garbage_random_mb", "garbage", hexbytes="8A9B8C9D8E9F8A8B")
add("garbage_random_text", "garbage", hexbytes="C8CB D6D0 CEC4 B2E2 CAD4")
add("garbage_high_bytes", "garbage", hexbytes="A1A2A3A4A5A6A7A8A9AA")

# ---------------- 显式 charset 直通（不经过检测器） ----------------
add("explicit_utf8_alias", "explicit", text="显式 utf8 别名", codec="utf-8", explicit="utf8")
add("explicit_gb2312_alias", "explicit", text="显式 GB2312", codec="gb2312", explicit="euc-cn")
add("explicit_latin1_alias", "explicit", text="café", codec="iso-8859-1", explicit="latin1")
add("explicit_cp1252_alias", "explicit", text="\u201cquoted\u201d", codec="windows-1252", explicit="cp1252")
add("explicit_gbk_header_first", "explicit", text="头部 GBK 优先于显式?", codec="gbk",
    explicit="utf-8", header="text/html; charset=gbk")

# ---------------- Content-Type 头 charset ----------------
add("header_charset_gbk", "header", text="头部声明 GBK 页面", codec="gbk",
    header="text/html; charset=GBK")
add("header_charset_utf16le", "header", text="头部声明 UTF-16LE", codec="utf-16le",
    header="application/octet-stream;charset=utf-16le")
add("header_quoted_charset", "header", text="带引号的头部", codec="gb18030",
    header="text/html; charset=\"gb18030\"")
add("header_no_charset", "header", text="头部无 charset 的 GBK 页面", codec="gbk",
    header="text/html")

# ---------------- 校验 & 写出 ----------------
assert len(cases) >= 80, f"用例数不足: {len(cases)}"
assert len({c["name"] for c in cases}) == len(cases), "name 重复"
doc = {
    "_comment": "⚠️ 合成样本（synthetic），非真实数据。第 6 步 6B golden：字符集检测/响应解码。"
                "由 scripts/golden/gen_charset_cases.py 生成（确定性规则 + Python codec 编码 + "
                "JDK 11 规则解码回读校验）。Java 侧 CharsetGen.java 输出 "
                "{name, hex, detected, htmlEncode, decoded} 供 Swift 测试比对。",
    "_SAMPLE_KIND": "合成样本（synthetic）",
    "charsetCases": cases,
}
with open(OUT, "w", encoding="utf-8") as f:
    json.dump(doc, f, ensure_ascii=False, indent=1)
print(f"已生成 {len(cases)} 条用例 -> {OUT}")
print("分类统计:", {})
from collections import Counter
print(dict(Counter(c["category"] for c in cases)))