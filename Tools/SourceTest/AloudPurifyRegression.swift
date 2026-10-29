import Foundation

/// 朗读净化的固定断言：只清理与正文无关的文字，不改叙述本身。
enum AloudPurifyRegression {
    static func run(check: (Bool, String) -> Void) {
        check(AloudPurifier.clean("正文 https://a.com/x 结束") == "正文 结束",
              "净化：去掉网址并合并多余空格")
        check(AloudPurifier.clean("他走了。本章完") == "他走了。",
              "净化：去掉句尾「本章完」")
        check(AloudPurifier.clean("他走了。（未完待续）") == "他走了。",
              "净化：去掉括号尾注")
        check(AloudPurifier.clean("请记住本站域名\n正文开始") == "正文开始",
              "净化：丢掉整行广告")
        check(AloudPurifier.clean("什么？？？") == "什么？",
              "净化：合并重复标点")
        check(AloudPurifier.clean("他摸出月票，递了过去。") == "他摸出月票，递了过去。",
              "净化：正常句子里的「月票」不误删")
        check(AloudPurifier.clean("  普通正文。  ") == "普通正文。",
              "净化：去掉首尾空白")
    }
}
