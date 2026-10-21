import Foundation

/// Rhino 兼容层回归：原版用 Rhino，很多书源脚本的写法在 JavaScriptCore 上会直接报
/// SyntaxError 或语义不同。归一化 + Java List 语义 + JSON 结果重入都要有断言。
enum RhinoCompatRegression {
    static func run(_ check: (Bool, String) -> Void) {
        // 1) let/const result → var result（Rhino 把它当可变的规则全局）
        let n1 = RuleScriptCompat.normalize("let result = 1; result + 'x'")
        check(n1.contains("var result = 1"), "let result 归一化成 var result")
        let n2 = RuleScriptCompat.normalize("const result = 2;")
        check(n2.contains("var result = 2"), "const result 归一化成 var result")

        // 字符串/注释里的同形文本不能被改写
        let n3 = RuleScriptCompat.normalize("var s = 'let result = 1';")
        check(n3 == "var s = 'let result = 1';", "字符串里的 let result 不改写")
        let n4 = RuleScriptCompat.normalize("// let result = 1\nvar x = 2;")
        check(!n4.contains("var result"), "注释里的 let result 不改写")

        // 2) 解构箭头参数补括号（JSC 要求 ([a,b]) => …）
        let n5 = RuleScriptCompat.normalize("all.map([title, Id] => push(title, Id))")
        check(n5.contains("(([title, Id]) =>"), "解构箭头参数补括号（实际 \(n5)）")
        let n6 = RuleScriptCompat.normalize("all.map(x => x + 1)")
        check(n6 == "all.map(x => x + 1)", "普通箭头参数不受影响")

        // 3) 形参在函数体顶层被重新声明 → var
        let n7 = RuleScriptCompat.normalize("function f(a){ let a = 1; return a; }")
        check(n7.contains("var a = 1"), "形参重声明归一化成 var（实际 \(n7)）")

        // 4) java.util.List 语义：result.add / addAll / set / contains
        let listScript = """
        var a=[]; a.add('x'); a.addAll(['y']); a.set(0,'z');
        a.contains('y') + '|' + a.size() + '|' + a.toArray().join(',') + '|' + a.isEmpty()
        """
        check(JSEngine.shared.evalString(listScript) == "true|2|z,y|false",
              "Array.prototype 具备 java.util.List 语义（add/addAll/set/contains/size/toArray/isEmpty）")

        // 5) java.* 高频工具
        check(JSEngine.shared.evalString("java.encodeURIComponent('a b')") == "a%20b",
              "java.encodeURIComponent 可用")
        check(JSEngine.shared.evalString("java.encodeURI('a b')") == "a%20b",
              "java.encodeURI 可用")
        check(JSEngine.shared.evalString("java.base64Encode('中文')") == "5Lit5paH",
              "java.base64Encode 可用")
        check(JSEngine.shared.evalString("java.base64Decode('5Lit5paH')") == "中文",
              "java.base64Decode 可用")

        // 6) JSON 结果重入 JS：result 要是原生数组（能拿到 List 方法）
        let json = "{\"list\":[{\"t\":\"甲\"},{\"t\":\"乙\"}]}"
        let ar = AnalyzeRule(content: json, baseUrl: "https://example.invalid/", context: RuleContext())
        check(ar.getStringList("$.list[*].t\n<js>result.toArray().length + '|' + result.size()</js>").first == "2|2",
              "JSON 规则结果在 JS 里是原生数组（可 toArray/size）")
    }
}
