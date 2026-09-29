#!/usr/bin/env python3
"""
字段覆盖校验（自动提取，不手打字段清单）。

做法：
  1. 用正则从 legado 的 Kotlin 实体源码里提取每个类/接口的「数据字段」。
     - data class 主构造器里的 `var/val name: Type` 参数；
     - interface 里的 `var/val name: Type` 属性；
     - 排除 @Ignore / @IgnoredOnParcel 修饰的运行时字段（这些不持久化，
       Swift 里作为非 Codable 属性存在，不纳入「持久化字段」对照）；
     - 排除方法、companion object 常量、内部 object。
  2. 在对应的 Swift 源文件里查找同名字段（词边界匹配，含反引号形式）。
  3. 输出「Kotlin 有但 Swift 没实现的字段」清单，为空则通过。

Kotlin 源码路径：默认相对本仓库的 reference/kotlin/entities，
也可用第一个命令行参数覆盖为外部 legado-E-main 的 entities 目录。
"""
import re, sys, os

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(HERE)

# Kotlin 源码目录（相对路径优先）
DEFAULT_KOTLIN_DIR = os.path.join(REPO, "reference", "kotlin", "entities")
kotlin_dir = sys.argv[1] if len(sys.argv) > 1 else DEFAULT_KOTLIN_DIR

# Kotlin 文件 -> 需要提取的顶层类型名（None 表示取文件里首个 data class / interface）
# 以及 -> 对应的 Swift 源文件（相对 repo）
MAPPING = {
    "BookSource.kt":  ("BookSource",  "Sources/LegadoBookSource/BookSource.swift"),
    "BaseSource.kt":  ("BaseSource",  "Sources/LegadoBookSource/BaseSource.swift"),
    "BaseBook.kt":    ("BaseBook",    "Sources/LegadoBookSource/BaseBook.swift"),
    "Book.kt":        ("Book",        "Sources/LegadoBookSource/Book.swift"),
    "BookChapter.kt": ("BookChapter", "Sources/LegadoBookSource/BookChapter.swift"),
    "SearchBook.kt":  ("SearchBook",  "Sources/LegadoBookSource/SearchBook.swift"),
    "rule/BookListRule.kt": ("BookListRule", "Sources/LegadoBookSource/Rule/BookListRule.swift"),
    "rule/SearchRule.kt":   ("SearchRule",   "Sources/LegadoBookSource/Rule/SearchRule.swift"),
    "rule/ExploreRule.kt":  ("ExploreRule",  "Sources/LegadoBookSource/Rule/ExploreRule.swift"),
    "rule/BookInfoRule.kt": ("BookInfoRule", "Sources/LegadoBookSource/Rule/BookInfoRule.swift"),
    "rule/TocRule.kt":      ("TocRule",      "Sources/LegadoBookSource/Rule/TocRule.swift"),
    "rule/ContentRule.kt":  ("ContentRule",  "Sources/LegadoBookSource/Rule/ContentRule.swift"),
    "rule/ReviewRule.kt":   ("ReviewRule",   "Sources/LegadoBookSource/Rule/ReviewRule.swift"),
    "rule/ExploreKind.kt":  ("ExploreKind",  "Sources/LegadoBookSource/Rule/ExploreKind.swift"),
    "rule/FlexChildStyle.kt": ("FlexChildStyle", "Sources/LegadoBookSource/Rule/FlexChildStyle.swift"),
    "rule/RowUi.kt":        ("RowUi",        "Sources/LegadoBookSource/Rule/RowUi.swift"),
}

# 内嵌 data class（在某个 Kotlin 文件里）单独对照到同一个 Swift 文件
NESTED = {
    # (kotlin文件, 内嵌类名)  ->  swift文件
    ("Book.kt", "ReadConfig"): "Sources/LegadoBookSource/Book.swift",
}

# 提取一个「构造器/类体」文本块里的字段名
FIELD_RE = re.compile(
    r'(?:^|\n)\s*'
    r'(?:@[\w.]+(?:\([^)]*\))?\s*)*'        # 前置注解（@ColumnInfo(...) 等）
    r'(?:override\s+)?'                       # override
    r'var\s+([A-Za-z_]\w*)\s*:',             # var name :
)
# interface 里也可能是 val
FIELD_RE_VAL = re.compile(
    r'(?:^|\n)\s*'
    r'(?:@[\w.]+(?:\([^)]*\))?\s*)*'
    r'(?:override\s+)?'
    r'(?:var|val)\s+([A-Za-z_]\w*)\s*:',
)

def strip_ignored(block):
    """删除被 @Ignore / @IgnoredOnParcel 修饰的属性所在的声明片段。
    这些属性在类体（非构造器）里，形如：
        @Ignore
        @IgnoredOnParcel
        var infoHtml: String? = null
    我们逐行扫描，遇到含 @Ignore/@IgnoredOnParcel 的注解块，跳过其后紧跟的
    var/val 声明。
    """
    lines = block.split("\n")
    out = []
    skip_next_decl = False
    for ln in lines:
        s = ln.strip()
        if "@Ignore" in s or "@IgnoredOnParcel" in s or "@delegate:Ignore" in s or "@get:Ignore" in s or "@delegate:Transient" in s:
            skip_next_decl = True
            continue
        if skip_next_decl:
            # 跳过直到出现一个 var/val 声明行（把它也跳过）
            if re.search(r'\b(var|val)\s+\w+', s):
                skip_next_decl = False
                continue
            # 注解与声明之间可能有空行/其它注解
            if s == "" or s.startswith("@"):
                continue
            # 其它情况（例如是方法），停止跳过
            skip_next_decl = False
        out.append(ln)
    return "\n".join(out)

def extract_primary_ctor(text, classname):
    """提取 data class 主构造器括号内的文本。"""
    m = re.search(r'data\s+class\s+' + re.escape(classname) + r'\s*\(', text)
    if not m:
        return None
    start = m.end() - 1  # 指向 '('
    depth = 0
    i = start
    while i < len(text):
        c = text[i]
        if c == '(':
            depth += 1
        elif c == ')':
            depth -= 1
            if depth == 0:
                return text[start+1:i]
        i += 1
    return None

def extract_interface_body(text, name):
    """提取 interface name { ... } 的花括号体（首层）。"""
    m = re.search(r'interface\s+' + re.escape(name) + r'\b[^{]*\{', text)
    if not m:
        return None
    start = m.end() - 1
    depth = 0
    i = start
    while i < len(text):
        c = text[i]
        if c == '{':
            depth += 1
        elif c == '}':
            depth -= 1
            if depth == 0:
                return text[start+1:i]
        i += 1
    return None

def extract_nested_dataclass_ctor(text, name):
    return extract_primary_ctor(text, name)

def kotlin_fields_for(kfile, typename, is_interface_hint=False):
    path = os.path.join(kotlin_dir, kfile)
    text = open(path).read()
    ctor = extract_primary_ctor(text, typename)
    if ctor is not None:
        block = strip_ignored(ctor)
        # data class 主构造器参数可能是 var 或 val，两者都是字段。
        return [m for m in FIELD_RE_VAL.findall(block)]
    body = extract_interface_body(text, typename)
    if body is not None:
        block = strip_ignored(body)
        # 接口里只取「属性声明」，排除方法后跟的东西：FIELD_RE_VAL 已限定 name: 形式
        # 但要排除方法参数等；接口体里 var/val 属性即字段。
        fields = []
        for m in FIELD_RE_VAL.finditer(block):
            fields.append(m.group(1))
        return fields
    return None

def swift_has_field(swift_text, field):
    # init 是 Swift 关键字，在源码里以 `init` 或 initValue 形式出现；用反引号匹配
    pat = re.compile(r'`?' + re.escape(field) + r'`?\b')
    return bool(pat.search(swift_text))

def main():
    missing = {}
    total = 0
    details = {}

    for kfile, (typename, swift_rel) in MAPPING.items():
        fields = kotlin_fields_for(kfile, typename)
        if fields is None:
            print(f"!! 无法从 {kfile} 提取 {typename} 的字段", file=sys.stderr)
            sys.exit(2)
        swift_text = open(os.path.join(REPO, swift_rel)).read()
        miss = [f for f in fields if not swift_has_field(swift_text, f)]
        total += len(fields)
        details[typename] = len(fields)
        if miss:
            missing[typename] = miss

    for (kfile, nested), swift_rel in NESTED.items():
        text = open(os.path.join(kotlin_dir, kfile)).read()
        ctor = extract_nested_dataclass_ctor(text, nested)
        if ctor is None:
            print(f"!! 无法提取内嵌类 {nested}", file=sys.stderr); sys.exit(2)
        fields = FIELD_RE_VAL.findall(strip_ignored(ctor))
        swift_text = open(os.path.join(REPO, swift_rel)).read()
        miss = [f for f in fields if not swift_has_field(swift_text, f)]
        total += len(fields)
        details[f"{nested}(内嵌)"] = len(fields)
        if miss:
            missing[f"{nested}(内嵌)"] = miss

    print("=== 字段覆盖校验（自动从 Kotlin 源码提取）===")
    print(f"Kotlin 源码目录: {os.path.relpath(kotlin_dir, REPO)}")
    for k, n in details.items():
        print(f"  {k}: {n} 字段")
    print(f"Kotlin 数据字段总数: {total}")
    if not missing:
        print("结果: 「Kotlin 有但 Swift 没实现的字段」清单 —— 空。全部覆盖。")
        sys.exit(0)
    else:
        print("结果: 存在未覆盖字段：")
        for t, m in missing.items():
            print(f"  {t}: {m}")
        sys.exit(1)

if __name__ == "__main__":
    main()
