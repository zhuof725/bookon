import Foundation

/// 多角色朗读的纯文本拆段：不依赖 AVFoundation，固定断言说话人与偏移。
enum AloudRoleRegression {
    static func run(check: (Bool, String) -> Void) {
        // 旁白 + 前置提示语
        let first = AloudRoleParser.segments(
            in: "林晚晴笑了笑，轻声道：“你来了。”她转身看向窗外。", baseOffset: 100)
        check(first.count == 3, "多角色：拆成旁白/对话/旁白三段")
        check(first.first?.speaker == AloudSpeaker.narrator, "多角色：第一段是旁白")
        check(first.count > 1 && first[1].text == "你来了。", "多角色：对话去掉外侧引号")
        check(first.count > 1 && first[1].speaker == AloudSpeaker.character(name: "林晚晴", gender: nil),
              "多角色：从「林晚晴笑了笑，轻声道」认出角色")
        check(first.count > 1 && first[1].offset == 100 + 12,
              "多角色：对话偏移按字符位置计算")
        check(first.last?.speaker == AloudSpeaker.narrator, "多角色：结尾旁白保留")

        // 引号后置提示语
        let second = AloudRoleParser.segments(in: "“我等你很久了。”张三说道。")
        check(second.count == 2, "多角色：后置提示语拆两段")
        check(second.first?.speaker == AloudSpeaker.character(name: "张三", gender: nil),
              "多角色：从「张三说道」认出角色")
        check(second.last?.text == "张三说道。", "多角色：提示语归入旁白")

        // 只有代词：按性别提示选声线
        let third = AloudRoleParser.segments(in: "“别动。”她低声说。")
        check(third.first?.speaker == AloudSpeaker.dialogue(gender: .female),
              "多角色：没有名字时按「她」判女声")
        check(AloudRoleParser.segments(in: "「走吧。」他说。").first?.speaker
                == AloudSpeaker.dialogue(gender: .male),
              "多角色：直角引号与「他」判男声")

        // 已知角色名优先，不必依赖说话动词
        let known = AloudRoleParser.segments(in: "“你来了。”林晚晴笑了。",
                                             knownNames: ["林晚晴"])
        check(known.first?.speaker == AloudSpeaker.character(name: "林晚晴", gender: nil),
              "多角色：已知角色名优先匹配")

        // 没有引号：整段都是旁白
        let plain = AloudRoleParser.segments(in: "天黑了，他关上门。")
        check(plain.count == 1 && plain[0].speaker == AloudSpeaker.narrator && plain[0].text == "天黑了，他关上门。",
              "多角色：无引号时保留整段旁白")

        // 换行与空白：旁白偏移跟着前导空白走
        let spaced = AloudRoleParser.segments(in: "  他说：“好。”", baseOffset: 10)
        check(spaced.first?.offset == 12, "多角色：旁白偏移跳过前导空格")
        check(spaced.count == 2, "多角色：前后空白不产生空段")

        // 引号没闭合：整段按旁白处理，不丢字
        let broken = AloudRoleParser.segments(in: "他说：“今天不说了")
        check(broken.count == 1 && broken[0].speaker == AloudSpeaker.narrator,
              "多角色：引号未闭合时退回旁白")
    }
}
