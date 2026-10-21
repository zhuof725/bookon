import Foundation

/// 书源变量（source.setVariable/getVariable）与登录表单值（result）的传递回归。
///
/// 番茄系「共享 Token」就存在书源变量里：登录页执行 `source.setVariable(token)`，
/// 之后所有请求（段评、章节、正文）都用 `source.getVariable()` 取出来当 token。
/// 段评打不开往往就是这条链路断了。
enum SourceVariableRegression {
    static func run(_ check: (Bool, String) -> Void) {
        guard let data = FileManager.default.contents(atPath: fixturePath()),
              let source = try? JSONDecoder().decode([BookSource].self, from: data).first else {
            check(false, "读取番茄书源夹具")
            return
        }

        let key = "regression-token-\(source.bookSourceUrl)"
        // 1) 登录脚本写入
        let write = JSEngine.shared.runLoginScript(source: source, library: "function saveToken(t){ source.setVariable(t); }",
                                                   call: "saveToken('TOKEN-ABC')")
        if case .failure(let e) = write { check(false, "登录脚本写变量失败：\(e.message)") }

        // 2) 规则脚本读回（跨上下文）
        let read = JSEngine.shared.evalString("source.getVariable()", result: nil, baseUrl: nil,
                                              jsLib: nil, context: RuleContext(source: source))
        check(read == "TOKEN-ABC", "source.setVariable → source.getVariable 往返（实际 \(read ?? "nil")）")

        // 3) 原版语义：put/get 与变量是两份独立存储
        _ = JSEngine.shared.runLoginScript(source: source, library: "function putIt(){ source.put('k','v'); }",
                                           call: "putIt()")
        let v = JSEngine.shared.evalString("source.get('k')", result: nil, baseUrl: nil,
                                           jsLib: nil, context: RuleContext(source: source))
        check(v == "v", "source.put/get 独立存储（实际 \(v ?? "nil")）")
        let still = JSEngine.shared.evalString("source.getVariable()", result: nil, baseUrl: nil,
                                               jsLib: nil, context: RuleContext(source: source))
        check(still == "TOKEN-ABC", "put 不会覆盖变量（实际 \(still ?? "nil")）")

        // 4) 登录表单值：按钮 action 里的 result['源作者']
        let form = JSEngine.shared.runLoginScript(source: source,
                                                  library: "function needAuthor(){ return String(result['源作者'] || 'NONE'); }",
                                                  call: "needAuthor()",
                                                  formValues: ["源作者": "作者甲"])
        if case .success(let s) = form {
            check(s.contains("作者甲"), "登录表单值进入 result（实际 \(s)）")
        } else {
            check(false, "登录表单值进入 result")
        }

        // 5) 清理
        _ = JSEngine.shared.runLoginScript(source: source, library: "function clearToken(){ source.setVariable(''); }",
                                           call: "clearToken()")
    }

    private static func fixturePath() -> String {
        let dir = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures")
        return dir.appendingPathComponent("fanqie-comment-source.json").path
    }
}
