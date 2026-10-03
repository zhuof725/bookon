package golden;

import com.google.gson.JsonObject;
import io.legado.app.lib.icu4j.CharsetDetector;
import io.legado.app.lib.icu4j.CharsetMatch;

import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

/**
 * 第 6 步 6B golden：字符集检测 / 响应解码对照。
 *
 * 本类是对 legado 以下代码的**手工逐行移植**（不依赖 Android/jsoup），供 golden 生成器在 JVM 上运行：
 *   - io.legado.app.utils.EncodingDetect.kt（getHtmlEncode / getEncode）
 *   - io.legado.app.help.http.OkHttpUtils.kt 的 ResponseBody.text()（decodeText 的顺序）
 *   - io.legado.app.utils.Utf8BomUtils.kt（removeUTF8Bom）
 * 检测器本体直接使用 scripts/golden/icu4j-src 里的真实 legado icu4j 类
 * （CharsetDetector().setText(bytes).detect()）。
 * 解码用 JDK 11 的 Charset.forName(...)（CI golden job 即 temurin JDK 11），
 * 与 Swift 侧 `TextDecoder`（un/nio/cs 各 Decoder 的移植）逐字节对照。
 *
 * ⚠️ 与 Swift 侧 EncodingDetect / StrResponse 的算法必须逐行一致（golden 对照），
 * 差异点（jsoup→正则、OkHttp MediaType→正则）已用「差异：」标注。
 */
final class CharsetGen {

    private CharsetGen() {}

    /** 差异：Kotlin 用 jsoup parseBodyFragment(head) 解析，这里用等价的正则提取 meta 标签。 */
    private static final Pattern HEAD_REGEX = Pattern.compile("(?i)<head>[\\s\\S]*?</head>");
    private static final Pattern META_TAG_REGEX = Pattern.compile("(?i)<meta\\b[^>]*>");
    /** 差异：OkHttp MediaType.charset() 的等价简化实现（参数名大小写不敏感，值去引号）。 */
    private static final Pattern HEADER_CHARSET_REGEX =
            Pattern.compile("(?i)(?:^|;)\\s*charset\\s*=\\s*\"?([^\";\\s]+)");

    private static final byte[] HEAD_OPEN = "<head>".getBytes(StandardCharsets.UTF_8);
    private static final byte[] HEAD_CLOSE = "</head>".getBytes(StandardCharsets.UTF_8);
    private static final byte[] UTF8_BOM = new byte[]{(byte) 0xEF, (byte) 0xBB, (byte) 0xBF};

    /** 对应 Kotlin EncodingDetect.getHtmlEncode(bytes)：BOM 剥离 → meta → 检测器。 */
    static String getHtmlEncode(byte[] rawBytes) {
        byte[] bytes = removeUTF8BOM(rawBytes);
        try {
            String head = null;
            int start = indexOf(bytes, HEAD_OPEN, 0);
            if (start > -1) {
                int end = indexOf(bytes, HEAD_CLOSE, start);
                if (end > -1) {
                    head = new String(java.util.Arrays.copyOfRange(bytes, start, end + HEAD_CLOSE.length),
                            StandardCharsets.UTF_8);
                }
            }
            if (head == null) {
                Matcher m = HEAD_REGEX.matcher(new String(bytes, StandardCharsets.UTF_8));
                if (m.find()) {
                    head = m.group();
                }
            }
            if (head != null) {
                for (MetaTag meta : extractMetaTags(head)) {
                    String charsetStr = meta.attrs.get("charset");
                    if (charsetStr != null && !charsetStr.isEmpty()) {
                        return charsetStr;
                    }
                    String httpEquiv = meta.attrs.get("http-equiv");
                    if (httpEquiv != null && httpEquiv.equalsIgnoreCase("content-type")) {
                        String content = meta.attrs.get("content");
                        if (content != null) {
                            int idx = indexOfIgnoreCase(content, "charset=");
                            String cs;
                            if (idx > -1) {
                                cs = content.substring(idx + "charset=".length());
                            } else {
                                // Kotlin: content.substringAfter(";")，缺省 missingDelimiterValue = this（整串）
                                int semi = content.indexOf(';');
                                cs = semi < 0 ? content : content.substring(semi + 1);
                            }
                            if (!cs.isEmpty()) {
                                return cs;
                            }
                        }
                    }
                }
            }
        } catch (Exception ignored) {
            // Kotlin: catch (ignored: Exception)，全部忽略
        }
        return getEncode(bytes);
    }

    /** 对应 Kotlin EncodingDetect.getEncode(bytes)：detect()?.name ?: "UTF-8"。 */
    static String getEncode(byte[] bytes) {
        CharsetMatch match = new CharsetDetector().setText(bytes).detect();
        return match == null ? "UTF-8" : match.getName();
    }

    /** 对应 Kotlin Utf8BomUtils.removeUTF8Bom(bytes)。 */
    static byte[] removeUTF8BOM(byte[] bytes) {
        if (bytes.length >= 3 && bytes[0] == UTF8_BOM[0] && bytes[1] == UTF8_BOM[1] && bytes[2] == UTF8_BOM[2]) {
            return java.util.Arrays.copyOfRange(bytes, 3, bytes.length);
        }
        return bytes;
    }

    /**
     * 对应 legado ResponseBody.text(encode)（OkHttpUtils.kt）：
     * removeUTF8BOM → 显式编码 → Content-Type 头 charset → getHtmlEncode（meta → 检测器）。
     */
    static String decodeText(byte[] rawBytes, String explicitCharset, String contentTypeHeader) {
        byte[] bytes = removeUTF8BOM(rawBytes);
        if (explicitCharset != null) {
            return new String(bytes, java.nio.charset.Charset.forName(explicitCharset));
        }
        String headerCs = charsetFromContentTypeHeader(contentTypeHeader);
        if (headerCs != null) {
            return new String(bytes, java.nio.charset.Charset.forName(headerCs));
        }
        return new String(bytes, java.nio.charset.Charset.forName(getHtmlEncode(bytes)));
    }

    static String charsetFromContentTypeHeader(String header) {
        if (header == null || header.isEmpty()) {
            return null;
        }
        Matcher m = HEADER_CHARSET_REGEX.matcher(header);
        return m.find() ? m.group(1) : null;
    }

    /** 与 Kotlin String.indexOf(String, ignoreCase=true) 等价（ASCII 目标）。 */
    static int indexOfIgnoreCase(String s, String target) {
        for (int i = 0; i + target.length() <= s.length(); i++) {
            if (s.regionMatches(true, i, target, 0, target.length())) {
                return i;
            }
        }
        return -1;
    }

    /** 字节串 indexOf（Kotlin ByteArray.indexOf(byteArray, startIndex) 语义）。 */
    static int indexOf(byte[] haystack, byte[] needle, int from) {
        outer:
        for (int i = Math.max(from, 0); i + needle.length <= haystack.length; i++) {
            for (int j = 0; j < needle.length; j++) {
                if (haystack[i + j] != needle[j]) {
                    continue outer;
                }
            }
            return i;
        }
        return -1;
    }

    /** meta 标签及其属性（属性名小写、首个出现者优先；与 jsoup attr() 行为近似）。 */
    static final class MetaTag {
        final Map<String, String> attrs = new LinkedHashMap<>();
    }

    static List<MetaTag> extractMetaTags(String html) {
        List<MetaTag> out = new ArrayList<>();
        Matcher m = META_TAG_REGEX.matcher(html);
        while (m.find()) {
            out.add(parseMetaTag(m.group()));
        }
        return out;
    }

    /**
     * 解析单个 &lt;meta ...&gt; 标签的属性。
     * 差异：jsoup 的 HTML5 tokenizer 属性解析的等价简化（引号/无引号值、属性名小写、首个出现者优先）。
     */
    static MetaTag parseMetaTag(String tag) {
        MetaTag meta = new MetaTag();
        int i = 0;
        // 跳过 "<meta"
        while (i < tag.length() && tag.charAt(i) != '>') {
            if (Character.isWhitespace(tag.charAt(i))) {
                i++;
            } else if (isAttrNameStart(tag.charAt(i))) {
                int nameStart = i;
                while (i < tag.length() && isAttrNameChar(tag.charAt(i))) {
                    i++;
                }
                String name = tag.substring(nameStart, i).toLowerCase(java.util.Locale.ROOT);
                while (i < tag.length() && Character.isWhitespace(tag.charAt(i))) {
                    i++;
                }
                String value = "";
                if (i < tag.length() && tag.charAt(i) == '=') {
                    i++;
                    while (i < tag.length() && Character.isWhitespace(tag.charAt(i))) {
                        i++;
                    }
                    if (i < tag.length() && tag.charAt(i) == '"') {
                        i++;
                        int vStart = i;
                        while (i < tag.length() && tag.charAt(i) != '"') {
                            i++;
                        }
                        value = tag.substring(vStart, i);
                        if (i < tag.length()) {
                            i++;
                        }
                    } else if (i < tag.length() && tag.charAt(i) == '\'') {
                        i++;
                        int vStart = i;
                        while (i < tag.length() && tag.charAt(i) != '\'') {
                            i++;
                        }
                        value = tag.substring(vStart, i);
                        if (i < tag.length()) {
                            i++;
                        }
                    } else {
                        int vStart = i;
                        while (i < tag.length() && !Character.isWhitespace(tag.charAt(i)) && tag.charAt(i) != '>') {
                            i++;
                        }
                        value = tag.substring(vStart, i);
                    }
                }
                if (!meta.attrs.containsKey(name)) {
                    meta.attrs.put(name, value);
                }
            } else {
                i++;
            }
        }
        return meta;
    }

    private static boolean isAttrNameStart(char c) {
        return (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || c == '_' || c == ':';
    }

    private static boolean isAttrNameChar(char c) {
        return isAttrNameStart(c) || (c >= '0' && c <= '9') || c == '.' || c == '-';
    }

    /** 跑一条用例，输出 {name, hex, detected, htmlEncode, decoded}。 */
    static JsonObject run(JsonObject c) {
        JsonObject out = new JsonObject();
        String name = c.get("name").getAsString();
        String hex = c.get("hex").getAsString();
        String explicit = c.has("explicitCharset") && !c.get("explicitCharset").isJsonNull()
                ? c.get("explicitCharset").getAsString() : null;
        String header = c.has("contentTypeHeader") && !c.get("contentTypeHeader").isJsonNull()
                ? c.get("contentTypeHeader").getAsString() : null;
        byte[] raw = hexToBytes(hex);
        out.addProperty("name", name);
        out.addProperty("hex", hex);
        out.add("explicitCharset", explicit == null ? com.google.gson.JsonNull.INSTANCE
                : new com.google.gson.JsonPrimitive(explicit));
        out.add("contentTypeHeader", header == null ? com.google.gson.JsonNull.INSTANCE
                : new com.google.gson.JsonPrimitive(header));
        try {
            out.addProperty("detected", getEncode(removeUTF8BOM(raw)));
            out.addProperty("htmlEncode", getHtmlEncode(raw));
            out.addProperty("decoded", decodeText(raw, explicit, header));
        } catch (Exception e) {
            out.addProperty("error", e.getClass().getSimpleName() + ": " + e.getMessage());
        }
        return out;
    }

    static byte[] hexToBytes(String hex) {
        int len = hex.length();
        byte[] data = new byte[len / 2];
        for (int i = 0; i < len; i += 2) {
            data[i / 2] = (byte) ((Character.digit(hex.charAt(i), 16) << 4)
                    | Character.digit(hex.charAt(i + 1), 16));
        }
        return data;
    }
}