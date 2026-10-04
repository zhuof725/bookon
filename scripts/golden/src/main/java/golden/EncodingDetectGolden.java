package golden;

import org.jsoup.Jsoup;
import org.jsoup.nodes.Document;
import org.jsoup.nodes.Element;
import org.jsoup.select.Elements;

import java.nio.charset.Charset;
import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.List;

/**
 * golden 侧的 legado <code>io.legado.app.utils.EncodingDetect</code> 逐行 Java 移植。
 *
 * <p>源文件：<code>app/src/main/java/io/legado/app/utils/EncodingDetect.kt</code>。
 *
 * <p>本类只做「Kotlin → Java」的语法搬运，判定逻辑与调用顺序完全保持一致：
 * <ol>
 *   <li>{@link #getHtmlEncode}：先按 <code>headOpenBytes</code>/<code>headCloseBytes</code> 切出
 *       <code>&lt;head&gt;</code> 段（找不到则用 {@code headTagRegex = "(?i)<head>[\\s\\S]*?</head>"}），
 *       再用 Jsoup <code>parseBodyFragment</code> 取全部 <code>&lt;meta&gt;</code>：
 *       优先 <code>charset</code> 属性；否则当 <code>http-equiv</code> 等于 "content-type"（忽略大小写）时，
 *       从 <code>content</code> 中取 <code>charset=</code> 之后的内容（无 <code>charset=</code> 则取
 *       <code>substringAfter(";")</code>）；任一命中即返回。</li>
 *   <li>全部未命中或抛异常 → 回退 {@link #getEncode}。</li>
 *   <li>{@link #getEncode}：<code>CharsetDetector().setText(bytes).detect()</code> 的
 *       <code>match?.name ?: "UTF-8"</code>（无匹配时 Kotlin 兜底 "UTF-8"）。</li>
 * </ol>
 *
 * <p>与 Kotlin 的唯一差异是 Kotlin 用 <code>android.text.TextUtils.isEmpty</code> 判空，
 * 这里用等价的 <code>s == null || s.isEmpty()</code>。
 */
final class EncodingDetectGolden {

    private static final String HEAD_TAG_REGEX = "(?i)<head>[\\s\\S]*?</head>";
    private static final byte[] HEAD_OPEN_BYTES = "<head>".getBytes(StandardCharsets.UTF_8);
    private static final byte[] HEAD_CLOSE_BYTES = "</head>".getBytes(StandardCharsets.UTF_8);

    private EncodingDetectGolden() {}

    /** 对应 Kotlin <code>EncodingDetect.getHtmlEncode(bytes)</code>。 */
    static String getHtmlEncode(byte[] bytes) {
        try {
            String head = null;
            int startIndex = indexOf(bytes, HEAD_OPEN_BYTES, 0);
            if (startIndex > -1) {
                int endIndex = indexOf(bytes, HEAD_CLOSE_BYTES, startIndex);
                if (endIndex > -1) {
                    int to = endIndex + HEAD_CLOSE_BYTES.length;
                    head = new String(bytes, startIndex, to - startIndex, StandardCharsets.UTF_8);
                }
            }
            String fragment = head;
            if (fragment == null) {
                // Kotlin: headTagRegex.find(String(bytes))!!.value（找不到会抛 NPE 被 catch 吞掉）
                java.util.regex.Matcher m =
                        java.util.regex.Pattern.compile(HEAD_TAG_REGEX)
                                .matcher(new String(bytes, StandardCharsets.UTF_8));
                if (!m.find()) {
                    return getEncode(bytes);
                }
                fragment = m.group();
            }
            Document doc = Jsoup.parseBodyFragment(fragment);
            Elements metaTags = doc.getElementsByTag("meta");
            for (Element metaTag : metaTags) {
                String charsetStr = metaTag.attr("charset");
                if (!isEmpty(charsetStr)) {
                    return charsetStr;
                }
                String httpEquiv = metaTag.attr("http-equiv");
                if (httpEquiv.equalsIgnoreCase("content-type")) {
                    String content = metaTag.attr("content");
                    int idx = indexOfIgnoreCase(content, "charset=");
                    if (idx > -1) {
                        charsetStr = content.substring(idx + "charset=".length());
                    } else {
                        int semi = content.indexOf(';');
                        charsetStr = semi >= 0 ? content.substring(semi + 1) : content;
                    }
                    if (!isEmpty(charsetStr)) {
                        return charsetStr;
                    }
                }
            }
        } catch (Exception ignored) {
            // 与 Kotlin 的 catch (ignored: Exception) 一致：静默回退到检测器
        }
        return getEncode(bytes);
    }

    /** 对应 Kotlin <code>EncodingDetect.getEncode(bytes)</code>。 */
    static String getEncode(byte[] bytes) {
        legadoicu.CharsetMatch match = new legadoicu.CharsetDetector().setText(bytes).detect();
        return match != null ? match.getName() : "UTF-8";
    }

    // ---- 检测器全量输出（golden 用于逐条比较字符集名 + 置信度）----

    /** 检测结果单项：字符集名 + 置信度（对应 Java <code>CharsetMatch.getName()/getConfidence()</code>）。 */
    static final class MatchInfo {
        final String name;
        final int confidence;

        MatchInfo(String name, int confidence) {
            this.name = name;
            this.confidence = confidence;
        }
    }

    /**
     * 对应 Java <code>CharsetDetector.detectAll()</code>：全部置信度 &gt; 0 的候选，
     * 已按「置信度降序、并列时识别器列表靠后者优先」排好序。
     */
    static List<MatchInfo> detectAll(byte[] bytes) {
        List<MatchInfo> out = new ArrayList<>();
        legadoicu.CharsetMatch[] matches = new legadoicu.CharsetDetector().setText(bytes).detectAll();
        if (matches != null) {
            for (legadoicu.CharsetMatch m : matches) {
                out.add(new MatchInfo(m.getName(), m.getConfidence()));
            }
        }
        return out;
    }

    /** 对应 Kotlin <code>Utf8BomUtils.removeUTF8BOM(bytes)</code>。 */
    static byte[] removeUTF8Bom(byte[] bytes) {
        if (bytes.length > 3
                && bytes[0] == (byte) 0xEF
                && bytes[1] == (byte) 0xBB
                && bytes[2] == (byte) 0xBF) {
            byte[] copy = new byte[bytes.length - 3];
            System.arraycopy(bytes, 3, copy, 0, copy.length);
            return copy;
        }
        return bytes;
    }

    /**
     * 对应 Kotlin <code>ResponseBody.text(encode)</code>（OkHttpUtils.kt）的完整判定链：
     * BOM 剥离 → 显式 charset（书源 UrlOption.charset）→ Content-Type charset → getHtmlEncode。
     */
    static String decodeBody(byte[] rawBytes, String explicitCharset, String contentTypeHeader) {
        byte[] responseBytes = removeUTF8Bom(rawBytes);
        if (explicitCharset != null && !explicitCharset.isEmpty()) {
            return new String(responseBytes, java.nio.charset.Charset.forName(explicitCharset));
        }
        String contentTypeCharset = charsetFromContentType(contentTypeHeader);
        if (contentTypeCharset != null) {
            return new String(responseBytes, java.nio.charset.Charset.forName(contentTypeCharset));
        }
        return new String(responseBytes, java.nio.charset.Charset.forName(getHtmlEncode(responseBytes)));
    }

    /** 对应 OkHttp <code>MediaType.charset()</code>：从 Content-Type 头取 charset 参数。 */
    static String charsetFromContentType(String contentType) {
        if (contentType == null) return null;
        int idx = indexOfIgnoreCase(contentType, "charset=");
        if (idx < 0) return null;
        String rest = contentType.substring(idx + "charset=".length()).trim();
        int end = rest.length();
        for (int i = 0; i < rest.length(); i++) {
            char c = rest.charAt(i);
            if (c == ';' || c == ' ' || c == '\t' || c == '"' || c == '\'') {
                end = i;
                break;
            }
        }
        String value = rest.substring(0, end).trim();
        return value.isEmpty() ? null : value;
    }

    // ---- 小工具 ----

    private static boolean isEmpty(String s) {
        return s == null || s.isEmpty();
    }

    /** Kotlin <code>ByteArray.indexOf(bytes)</code> 的等价物（从 fromIndex 起找首个完全匹配）。 */
    static int indexOf(byte[] haystack, byte[] needle, int fromIndex) {
        if (needle.length == 0) return fromIndex;
        outer:
        for (int i = Math.max(fromIndex, 0); i + needle.length <= haystack.length; i++) {
            for (int j = 0; j < needle.length; j++) {
                if (haystack[i + j] != needle[j]) continue outer;
            }
            return i;
        }
        return -1;
    }

    static int indexOfIgnoreCase(String haystack, String needle) {
        return haystack.toLowerCase(java.util.Locale.ROOT)
                .indexOf(needle.toLowerCase(java.util.Locale.ROOT));
    }
}
