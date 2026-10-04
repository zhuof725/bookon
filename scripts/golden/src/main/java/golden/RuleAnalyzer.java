package golden;

import java.util.ArrayList;
import java.util.HashSet;
import java.util.Set;

/**
 * 逐行对照 legado 的 RuleAnalyzer.kt 移植到 Java，供 golden 生成器使用。
 * 与仓库里 Swift 版 RuleAnalyzer 的移植同源（reference/kotlin/analyzeRule/RuleAnalyzer.kt）。
 * 这是 golden 对照的"参考实现"之一，保证 && / || / %% 切分、@ 链式切分与 legado 原版一致。
 */
public class RuleAnalyzer {

    private final String queue;
    private int pos = 0;
    private int start = 0;
    private int startX = 0;

    private ArrayList<String> rule = new ArrayList<>();
    private int step = 0;
    public String elementsType = "";

    private final boolean code;
    private static final char ESC = '\\';

    public RuleAnalyzer(String data, boolean code) {
        this.queue = data;
        this.code = code;
    }

    public RuleAnalyzer(String data) {
        this(data, false);
    }

    public void trim() {
        if (queue.charAt(pos) == '@' || queue.charAt(pos) < '!') {
            pos++;
            while (queue.charAt(pos) == '@' || queue.charAt(pos) < '!') pos++;
            start = pos;
            startX = pos;
        }
    }

    public void reSetPos() {
        pos = 0;
        startX = 0;
    }

    private boolean consumeTo(String seq) {
        start = pos;
        int offset = queue.indexOf(seq, pos);
        if (offset != -1) {
            pos = offset;
            return true;
        }
        return false;
    }

    private boolean consumeToAny(String... seq) {
        int p = pos;
        while (p != queue.length()) {
            for (String s : seq) {
                if (queue.regionMatches(p, s, 0, s.length())) {
                    step = s.length();
                    this.pos = p;
                    return true;
                }
            }
            p++;
        }
        return false;
    }

    private int findToAny(char... seq) {
        int p = pos;
        while (p != queue.length()) {
            for (char s : seq) if (queue.charAt(p) == s) return p;
            p++;
        }
        return -1;
    }

    private boolean chompCodeBalanced(char open, char close) {
        int p = pos;
        int depth = 0;
        int otherDepth = 0;
        boolean inSingleQuote = false;
        boolean inDoubleQuote = false;
        do {
            if (p == queue.length()) break;
            char c = queue.charAt(p++);
            if (c != ESC) {
                if (c == '\'' && !inDoubleQuote) inSingleQuote = !inSingleQuote;
                else if (c == '"' && !inSingleQuote) inDoubleQuote = !inDoubleQuote;
                if (inSingleQuote || inDoubleQuote) continue;
                if (c == '[') depth++;
                else if (c == ']') depth--;
                else if (depth == 0) {
                    if (c == open) otherDepth++;
                    else if (c == close) otherDepth--;
                }
            } else p++;
        } while (depth > 0 || otherDepth > 0);
        if (depth > 0 || otherDepth > 0) return false;
        this.pos = p;
        return true;
    }

    private boolean chompRuleBalanced(char open, char close) {
        int p = pos;
        int depth = 0;
        boolean inSingleQuote = false;
        boolean inDoubleQuote = false;
        do {
            if (p == queue.length()) break;
            char c = queue.charAt(p++);
            if (c == '\'' && !inDoubleQuote) inSingleQuote = !inSingleQuote;
            else if (c == '"' && !inSingleQuote) inDoubleQuote = !inDoubleQuote;
            if (inSingleQuote || inDoubleQuote) continue;
            else if (c == '\\') { p++; continue; }
            if (c == open) depth++;
            else if (c == close) depth--;
        } while (depth > 0);
        if (depth > 0) return false;
        this.pos = p;
        return true;
    }

    private boolean chompBalanced(char open, char close) {
        return code ? chompCodeBalanced(open, close) : chompRuleBalanced(open, close);
    }

    public ArrayList<String> splitRule(String... split) {
        while (true) {
            if (split.length == 1) {
                elementsType = split[0];
                if (!consumeTo(elementsType)) {
                    rule.add(queue.substring(startX));
                    return rule;
                } else {
                    step = elementsType.length();
                    return splitRuleNext();
                }
            } else if (!consumeToAny(split)) {
                rule.add(queue.substring(startX));
                return rule;
            }

            int end = pos;
            pos = start;

            while (true) {
                int st = findToAny('[', '(');

                if (st == -1) {
                    rule = new ArrayList<>();
                    rule.add(queue.substring(startX, end));
                    elementsType = queue.substring(end, end + step);
                    pos = end + step;
                    while (consumeTo(elementsType)) {
                        rule.add(queue.substring(start, pos));
                        pos += step;
                    }
                    rule.add(queue.substring(pos));
                    return rule;
                }

                if (st > end) {
                    rule = new ArrayList<>();
                    rule.add(queue.substring(startX, end));
                    elementsType = queue.substring(end, end + step);
                    pos = end + step;
                    while (consumeTo(elementsType) && pos < st) {
                        rule.add(queue.substring(start, pos));
                        pos += step;
                    }
                    if (pos > st) {
                        startX = start;
                        return splitRuleNext();
                    } else {
                        rule.add(queue.substring(pos));
                        return rule;
                    }
                }

                pos = st;
                char next = queue.charAt(pos) == '[' ? ']' : ')';
                if (!chompBalanced(queue.charAt(pos), next)) {
                    throw new RuntimeException(queue.substring(0, start) + "后未平衡");
                }

                if (!(end > pos)) break;
            }

            start = pos;
        }
    }

    private ArrayList<String> splitRuleNext() {
        outer:
        while (true) {
            int end = pos;
            pos = start;

            while (true) {
                int st = findToAny('[', '(');

                if (st == -1) {
                    rule.add(queue.substring(startX, end));
                    pos = end + step;
                    while (consumeTo(elementsType)) {
                        rule.add(queue.substring(start, pos));
                        pos += step;
                    }
                    rule.add(queue.substring(pos));
                    return rule;
                }

                if (st > end) {
                    rule.add(queue.substring(startX, end));
                    pos = end + step;
                    while (consumeTo(elementsType) && pos < st) {
                        rule.add(queue.substring(start, pos));
                        pos += step;
                    }
                    if (pos > st) {
                        startX = start;
                        continue outer;
                    } else {
                        rule.add(queue.substring(pos));
                        return rule;
                    }
                }

                pos = st;
                char next = queue.charAt(pos) == '[' ? ']' : ')';
                if (!chompBalanced(queue.charAt(pos), next)) {
                    throw new RuntimeException(queue.substring(0, start) + "后未平衡");
                }

                if (!(end > pos)) break;
            }

            start = pos;

            if (!consumeTo(elementsType)) {
                rule.add(queue.substring(startX));
                return rule;
            } else {
                continue outer;
            }
        }
    }

    public interface StringFunc {
        String apply(String s);
    }

    public String innerRule(String inner, int startStep, int endStep, StringFunc fr) {
        StringBuilder st = new StringBuilder();
        while (consumeTo(inner)) {
            int posPre = pos;
            if (chompCodeBalanced('{', '}')) {
                String frv = fr.apply(queue.substring(posPre + startStep, pos - endStep));
                if (frv != null && !frv.isEmpty()) {
                    st.append(queue, startX, posPre).append(frv);
                    startX = pos;
                    continue;
                }
            }
            pos += inner.length();
        }
        return startX == 0 ? "" : st.append(queue.substring(startX)).toString();
    }
}
