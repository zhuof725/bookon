import Foundation

/// 离线回归：书源脚本变量磁盘存储。对应书山聚合「段评开关」这类
/// 通过 source.setVariable / java.put 保存、重启后应仍保留的设置。
/// 输入均为合成数据，失败信息不含真实值。
enum VariableStoreRegression {
    static func run(_ check: (Bool, String) -> Void) {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("var-store-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("sub/vars.json")

        let a = PersistentVariableStore(fileURL: file)
        check(a.get("k") == nil, "变量存储：初始为空")
        a.set("k", "v1")
        a.set("k2", "v2")
        a.set("empty", "")
        a.flush()
        check(FileManager.default.fileExists(atPath: file.path), "变量存储：写盘时自动建目录")

        let b = PersistentVariableStore(fileURL: file)
        check(b.get("k") == "v1" && b.get("k2") == "v2", "变量存储：重启后读回")
        check(b.get("empty") == "", "变量存储：空值原样保留")

        b.remove("k")
        b.flush()
        let c = PersistentVariableStore(fileURL: file)
        check(c.get("k") == nil && c.get("k2") == "v2", "变量存储：删除后重启不再出现")

        try? Data("not json".utf8).write(to: file)
        let d = PersistentVariableStore(fileURL: file)
        check(d.get("k2") == nil, "变量存储：文件损坏视为空")
        d.set("recover", "1")
        d.flush()
        check(PersistentVariableStore(fileURL: file).get("recover") == "1", "变量存储：损坏后可重新写入")

        // JS 面：书源脚本写变量（书山聚合段评开关就是 setConfigs → source.setVariable）后，
        // 立即落盘，并由全新实例读回，等价于重启应用。
        let key = "https://vars-\(UUID().uuidString.lowercased()).test#1"
        guard let source = try? JSONDecoder().decode(BookSource.self,
            from: Data("{\"bookSourceUrl\":\"\(key)\",\"bookSourceName\":\"vars\"}".utf8)) else {
            check(false, "变量存储：构造书源失败"); return
        }
        _ = JSEngine.shared.evalString("source.setVariable(JSON.stringify([{yunpara:'on'}]))",
                                       context: RuleContext(source: source))
        JavaBridge.store.flush()
        let reloaded = PersistentVariableStore(fileURL: PersistentVariableStore.defaultFileURL())
        check((reloaded.get("__var_" + key) ?? "").contains("yunpara"),
              "变量存储：书源设置经 JS 写入后重启可读回")
        _ = JSEngine.shared.evalString("source.setVariable('')", context: RuleContext(source: source))
        JavaBridge.store.flush()
        check((PersistentVariableStore(fileURL: PersistentVariableStore.defaultFileURL())
            .get("__var_" + key) ?? "") == "", "变量存储：清空后重启读到空值")
        JavaBridge.store.remove("__var_" + key)
        JavaBridge.store.flush()
    }
}
