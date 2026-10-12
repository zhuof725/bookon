import Foundation

var checks = 0
var failures = 0
func expect(_ condition: @autoclosure () -> Bool, _ label: String) {
    checks += 1
    if condition() { print("PASS \(label)") }
    else { failures += 1; print("FAIL \(label)") }
}
func rule(_ pattern: String, _ replacement: String, regex: Bool = false,
          enabled: Bool = true, id: String = UUID().uuidString) -> BodyReplaceRule {
    BodyReplaceRule(id: id, name: "Regression", pattern: pattern,
                    replacement: replacement, isRegex: regex, enabled: enabled)
}
func apply(_ text: String, _ rules: [BodyReplaceRule]) -> String {
    BodyReplaceEngine(rules: rules).apply(text)
}
func rejects(_ repository: BodyReplaceRepository, _ rules: [BodyReplaceRule], _ label: String) {
    do { try repository.save(rules); expect(false, label) }
    catch { expect(true, label) }
}

expect(apply("中文🙂中文🙂", [rule("中文🙂", "阅读🚀")]) == "阅读🚀阅读🚀", "literal Chinese and emoji")
expect(apply("a.b aXb", [rule("a.b", "ok")]) == "ok aXb", "literal regex metacharacters")
expect(apply("x x", [rule("x", "$1\\tail")]) == "$1\\tail $1\\tail", "literal dollar and backslash")
expect(apply("$1 costs $1", [rule("$1", "$2")]) == "$2 costs $2", "literal dollar pattern")
expect(apply("章节12🙂", [rule("章节([0-9]+)", "第$1章", regex: true)]) == "第12章🙂", "regex capture $1 UTF16 ranges")
expect(apply("前广告后广告", [rule("广告", "")]) == "前后", "empty replacement deletes all matches")
expect(apply("abc", [rule("abc", "")]) == "", "deletion may produce empty output")
expect(apply("abc", [rule("a", "x", enabled: false)]) == "abc", "disabled rule ignored")
let ordered = [rule("a", "b"), rule("b", "c")]
expect(apply("a", ordered) == "c", "rules apply in stored order")
expect(apply("a", Array(ordered.reversed())) == "b", "reversed order changes output")
let original = "原文🙂广告"
let originalBytes = Data(original.utf8)
expect(apply(original, [rule("广告", "")]) == "原文🙂", "display copy transformed")
expect(Data(original.utf8) == originalBytes, "original bytes remain unchanged")
expect(apply("abc", []) == "abc", "empty rules identity")
expect(apply("", [rule("x", "y")]) == "", "empty input identity")
expect(apply("abc", [rule("z", "y")]) == "abc", "no match identity")
let invalid = rule("(", "bad", regex: true)
let empty = rule("", "bad")
expect(invalid.validationMessage != nil, "invalid regex validates")
expect(empty.validationMessage != nil, "empty pattern validates")
expect(apply("abc", [invalid, empty]) == "abc", "invalid rules safely skipped")
expect(apply("abc", [invalid, rule("a", "z")]) == "zbc", "valid rule survives invalid neighbor")

let suite = "io.legado.body-replace-regression." + UUID().uuidString
let otherSuite = suite + ".other"
guard let defaults = UserDefaults(suiteName: suite),
      let otherDefaults = UserDefaults(suiteName: otherSuite) else {
    fatalError("Cannot create isolated defaults suites")
}
defaults.removePersistentDomain(forName: suite)
otherDefaults.removePersistentDomain(forName: otherSuite)
defer {
    defaults.removePersistentDomain(forName: suite)
    otherDefaults.removePersistentDomain(forName: otherSuite)
}
let repository = BodyReplaceRepository(defaults: defaults)
let other = BodyReplaceRepository(defaults: otherDefaults)
expect(repository.rules().isEmpty, "new isolated repository empty")
do {
    let stored = [rule("🙂", "$1", id: "unicode"), rule("(广告)", "", regex: true, enabled: false, id: "regex")]
    try repository.save(stored)
    expect(repository.rules() == stored, "roundtrip every field and order")
    let reopened = BodyReplaceRepository(defaults: UserDefaults(suiteName: suite)!)
    expect(reopened.rules() == stored, "new repository reopens saved data")
    expect(other.rules().isEmpty, "second suite untouched")
    var edited = reopened.rules()
    edited[0].enabled = false
    edited[1].enabled = true
    try repository.save(edited)
    expect(reopened.rules() == edited, "enable and disable persist")
    edited[0].name = "编辑后的规则"
    edited[0].pattern = "原文"
    edited[0].replacement = "正文"
    edited[0].isRegex = true
    try repository.save(edited)
    expect(reopened.rules() == edited, "edit persists with stable identity")
    rejects(repository, [invalid], "save rejects invalid regex")
    expect(repository.rules() == edited, "invalid regex does not clobber saved data")
    rejects(repository, [empty], "save rejects empty pattern")
    expect(repository.rules() == edited, "empty pattern does not clobber saved data")
    rejects(repository, [edited[0], edited[0]], "save rejects duplicate identifiers")
    expect(repository.rules() == edited, "duplicate save is atomic")
    edited.removeFirst()
    try repository.save(edited)
    expect(reopened.rules() == edited, "delete persists and preserves remaining rule")
    try repository.save([])
    expect(reopened.rules().isEmpty, "delete last rule persists empty array")
    expect(other.rules().isEmpty, "all mutations isolated from other suite")
} catch {
    expect(false, "unexpected repository error: \(error)")
}
print("Body replacement regression: \(checks - failures)/\(checks) passed")
if failures > 0 { fatalError("\(failures) body replacement regression failures") }
