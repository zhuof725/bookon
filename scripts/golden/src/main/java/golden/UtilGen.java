package golden;

import org.apache.commons.text.StringEscapeUtils;

import java.util.ArrayList;
import java.util.List;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

/**
 * 工具函数 golden 生成器：
 *  - unescapeHtml4：真实 commons-text 1.13.1 StringEscapeUtils.unescapeHtml4。
 *  - replaceRegex：Kotlin AnalyzeRule.replaceRegex 语义（手工移植调度，java.util.regex 为真实库）。
 *  - AnalyzeByRegex.getElement/getElements：从 legado 源码原样复刻（真实 Java 正则）。
 */
public final class UtilGen {

    // ---------------- unescapeHtml4 ----------------
    public static String unescapeHtml4(String input) {
        return StringEscapeUtils.unescapeHtml4(input);
    }

    // ---------------- replaceRegex（对应 Kotlin AnalyzeRule.replaceRegex）----------------
    // Kotlin:
    //   if (rule.replaceFirst) {
    //       val regex = replaceRegex.toRegex()  (非法返回 null)
    //       if (regex != null) runCatching {
    //           val matcher = regex.toPattern().matcher(result)
    //           return if (matcher.find()) matcher.group(0)!!.replaceFirst(regex, replacement) else ""
    //       }
    //       return replacement
    //   } else {
    //       if (regex != null) runCatching { return result.replace(regex, replacement) }
    //       return result.replace(replaceRegex, replacement)   // 字面量替换
    //   }
    // Kotlin String.replace(Regex, String) == Matcher.replaceAll（$n/\ 语义）。
    // Kotlin String.replaceFirst(Regex, String) == Matcher.replaceFirst。
    public static String replaceRegex(String result, String replaceRegex, String replacement, boolean replaceFirst) {
        if (replaceRegex.isEmpty()) return result;
        Pattern regex;
        try {
            regex = Pattern.compile(replaceRegex);
        } catch (Exception e) {
            regex = null;
        }
        if (replaceFirst) {
            if (regex != null) {
                try {
                    Matcher matcher = regex.matcher(result);
                    if (matcher.find()) {
                        // Kotlin: matcher.group(0)!!.replaceFirst(regex, replacement)
                        String g0 = matcher.group(0);
                        return regex.matcher(g0).replaceFirst(replacement);
                    } else {
                        return "";
                    }
                } catch (Exception e) {
                    // runCatching 吞错后落到 return replacement
                }
            }
            return replacement;
        } else {
            if (regex != null) {
                try {
                    return regex.matcher(result).replaceAll(replacement);
                } catch (Exception e) {
                    // runCatching 吞错后落到字面量替换
                }
            }
            // 字面量替换（String.replace(CharSequence, CharSequence)）
            return result.replace(replaceRegex, replacement);
        }
    }

    // ---------------- AnalyzeByRegex（从 legado 源码原样复刻）----------------
    public static List<String> getElement(String res, String[] regs, int index) {
        int vIndex = index;
        Matcher resM = Pattern.compile(regs[vIndex]).matcher(res);
        if (!resM.find()) {
            return null;
        }
        if (vIndex + 1 == regs.length) {
            List<String> info = new ArrayList<>();
            for (int groupIndex = 0; groupIndex <= resM.groupCount(); groupIndex++) {
                // Kotlin resM.group(i)!!：未参与的组为 null 会 NPE；此处保留 null 以如实对照
                info.add(resM.group(groupIndex));
            }
            return info;
        } else {
            StringBuilder result = new StringBuilder();
            do {
                result.append(resM.group());
            } while (resM.find());
            return getElement(result.toString(), regs, vIndex + 1);
        }
    }

    public static List<List<String>> getElements(String res, String[] regs, int index) {
        int vIndex = index;
        Matcher resM = Pattern.compile(regs[vIndex]).matcher(res);
        if (!resM.find()) {
            return new ArrayList<>();
        }
        if (vIndex + 1 == regs.length) {
            List<List<String>> books = new ArrayList<>();
            do {
                List<String> info = new ArrayList<>();
                for (int groupIndex = 0; groupIndex <= resM.groupCount(); groupIndex++) {
                    String g = resM.group(groupIndex);
                    info.add(g == null ? "" : g);
                }
                books.add(info);
            } while (resM.find());
            return books;
        } else {
            StringBuilder result = new StringBuilder();
            do {
                result.append(resM.group());
            } while (resM.find());
            return getElements(result.toString(), regs, vIndex + 1);
        }
    }
}
