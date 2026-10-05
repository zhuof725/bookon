package golden;

import com.google.gson.JsonObject;

import java.util.regex.Matcher;
import java.util.regex.Pattern;

/**
 * 第 7 步 A 段：HtmlFormatter.format / formatKeepImg 的手工 Java 移植（golden 对照）。
 *
 * <p>源文件：{@code app/src/main/java/io/legado/app/utils/HtmlFormatter.kt}（object）。
 * 逐行对照移植正则与替换顺序，唯一目的是用「独立于 Swift 的 Java 实现」产出期望值，
 * 供 Swift 侧 {@code HtmlFormatter} 单元测试逐条比对（只校验库行为，不校验 Swift 内部实现）。
 */
public final class HtmlFormatterGen {

    private HtmlFormatterGen() {}

    private static final Pattern nbspRegex = Pattern.compile("(&nbsp;)+");
    private static final Pattern espRegex = Pattern.compile("(&ensp;|&emsp;)");
    private static final Pattern noPrintRegex = Pattern.compile("(&thinsp;|&zwnj;|&zwj;|\u2009|\u200C|\u200D)");
    private static final Pattern wrapHtmlRegex = Pattern.compile("</?(?:div|p|br|hr|h\\d|article|dd|dl)[^>]*>");
    private static final Pattern commentRegex = Pattern.compile("<!--[^>]*-->");
    private static final Pattern notImgHtmlRegex = Pattern.compile("</?(?!img)[a-zA-Z]+(?=[ >])[^<>]*>");
    private static final Pattern otherHtmlRegex = Pattern.compile("</?[a-zA-Z]+(?=[ >])[^<>]*>");
    private static final Pattern indent1Regex = Pattern.compile("\\s*\\n+\\s*");
    private static final Pattern indent2Regex = Pattern.compile("^[\\n\\s]+");
    private static final Pattern lastRegex = Pattern.compile("[\\n\\s]+$");

    private static final Pattern formatImagePattern = Pattern.compile(
            "<img[^>]*\\ssrc\\s*=\\s*['\"]([^'\"{>]*\\{(?:[^{}]|\\{[^}>]+\\})+\\})['\"][^>]*>"
                    + "|<img[^>]*\\sdata-(?:src|original|srcset)\\s*=\\s*['\"]([^'\">]+)['\"][^>]*>"
                    + "|<img[^>]*\\ssrc\\s*=\\s*\"([^\">]+)\"[^>]*>"
                    + "|<img[^>]*\\s(?:data-[^=>]*|src)=\\s*['\"]([^'\">]*)['\"][^>]*>",
            Pattern.CASE_INSENSITIVE);

    private static final Pattern paramPattern = Pattern.compile("\\s*,\\s*(?=\\{)");

    /** 对应 Kotlin {@code fun format(html: String?, otherRegex: Regex = otherHtmlRegex): String}. */
    public static String format(String html) {
        return format(html, otherHtmlRegex);
    }

    public static String format(String html, Pattern otherRegex) {
        if (html == null) return "";
        String s = nbspRegex.matcher(html).replaceAll(" ");
        s = espRegex.matcher(s).replaceAll(" ");
        s = noPrintRegex.matcher(s).replaceAll("");
        s = wrapHtmlRegex.matcher(s).replaceAll("\n");
        s = commentRegex.matcher(s).replaceAll("");
        s = otherRegex.matcher(s).replaceAll("");
        s = indent1Regex.matcher(s).replaceAll("\n　　");
        s = indent2Regex.matcher(s).replaceAll("　　");
        s = lastRegex.matcher(s).replaceAll("");
        return s;
    }

    /** 对应 Kotlin {@code fun formatKeepImg(html: String?, redirectUrl: URL? = null): String}. */
    public static String formatKeepImg(String html, String redirectUrl) {
        if (html == null) return "";
        String keepImgHtml = format(html, notImgHtmlRegex);

        Matcher matcher = formatImagePattern.matcher(keepImgHtml);
        int appendPos = 0;
        StringBuilder sb = new StringBuilder();
        while (matcher.find()) {
            String param = "";
            String src;
            String g1 = matcher.group(1);
            if (g1 != null) {
                Matcher urlMatcher = paramPattern.matcher(g1);
                if (urlMatcher.find()) {
                    param = "," + g1.substring(urlMatcher.end());
                    src = g1.substring(0, urlMatcher.start());
                } else {
                    src = g1;
                }
            } else if (matcher.group(2) != null) {
                src = matcher.group(2);
            } else if (matcher.group(3) != null) {
                src = matcher.group(3);
            } else {
                src = matcher.group(4);
            }
            String resolved = UrlResolver.getAbsoluteURL(redirectUrl, src == null ? "" : src) + param;
            sb.append(keepImgHtml, appendPos, matcher.start())
              .append("<img src=\"").append(resolved).append("\">");
            appendPos = matcher.end();
        }
        if (appendPos < keepImgHtml.length()) {
            sb.append(keepImgHtml, appendPos, keepImgHtml.length());
        }
        return sb.toString();
    }

    /** golden runner：读 cases/html_formatter_cases.json 的单条用例，输出结果对象。 */
    public static JsonObject run(JsonObject c) {
        JsonObject out = new JsonObject();
        out.addProperty("name", c.get("name").getAsString());
        String html = c.get("html").getAsString();
        out.addProperty("html", html);
        String mode = c.has("mode") ? c.get("mode").getAsString() : "format";
        out.addProperty("mode", mode);
        if ("formatKeepImg".equals(mode)) {
            String redirectUrl = (c.has("redirectUrl") && !c.get("redirectUrl").isJsonNull())
                    ? c.get("redirectUrl").getAsString() : null;
            out.add("redirectUrl", redirectUrl == null
                    ? com.google.gson.JsonNull.INSTANCE : new com.google.gson.JsonPrimitive(redirectUrl));
            out.addProperty("result", formatKeepImg(html, redirectUrl));
        } else {
            out.addProperty("result", format(html));
        }
        return out;
    }
}
