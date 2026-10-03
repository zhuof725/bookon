package golden;

import cn.hutool.core.codec.Base64;
import cn.hutool.core.util.HexUtil;
import cn.hutool.crypto.digest.DigestUtil;
import com.github.liuyueyi.quick.transfer.ChineseUtils;
import com.github.liuyueyi.quick.transfer.constants.TransType;
import com.google.gson.JsonArray;
import com.google.gson.JsonElement;
import com.google.gson.JsonObject;
import org.jsoup.Jsoup;

import java.io.BufferedReader;
import java.io.InputStream;
import java.io.InputStreamReader;
import java.net.URLEncoder;
import java.nio.charset.StandardCharsets;
import java.text.SimpleDateFormat;
import java.util.ArrayList;
import java.util.Date;
import java.util.List;
import java.util.Locale;
import java.util.SimpleTimeZone;
import java.util.TimeZone;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

/**
 * Step 5 golden：JsExtensions 纯算法对照（真实库）。
 *  - md5/base64/hex：hutool 5.8.22（与 legado 一致）
 *  - t2s/s2t：quick-chinese-transfer 0.2.17 + legado fixT2sDict 排除词
 *  - timeFormat：Java SimpleDateFormat（FastDateFormat 语义）
 *  - encodeURI：java.net.URLEncoder
 *  - toNumChapter：legado AppPattern.titleNumPattern + StringUtils.stringToInt 复刻
 *  - htmlFormat：legado HtmlFormatter.formatKeepImg(null) 复刻
 *  - bytesToStr/strToBytes：UTF-8
 *  - Jsoup.parse 链：jsoup 1.16.2 真实对象
 * Java 侧按 Kotlin 签名处理数值入参（JS 数字 → Java 参数：整数无 .0 的 JS toString 语义）。
 */
public final class JsExtGen {
    private JsExtGen() {}

    private static boolean t2sFixed = false;

    /** legado ChineseUtils.fixT2sDict 的排除词（从 golden resources 读取，与 Swift vendored 同源）。 */
    private static synchronized void fixT2sDict() {
        if (t2sFixed) return;
        t2sFixed = true;
        List<String> excludes = new ArrayList<>();
        try (InputStream in = JsExtGen.class.getResourceAsStream("/t2s_exclude.txt")) {
            if (in != null) {
                try (BufferedReader r = new BufferedReader(new InputStreamReader(in, StandardCharsets.UTF_8))) {
                    String line;
                    while ((line = r.readLine()) != null) {
                        if (!line.isEmpty()) excludes.add(line);
                    }
                }
            }
        } catch (Exception ignored) {
            // 资源缺失时按无排除词处理（与 Swift 侧一致时用同文件，正常不会缺）
        }
        ChineseUtils.loadExcludeDict(TransType.TRADITIONAL_TO_SIMPLE, excludes);
    }

    /** JS 数字 → Java 参数：按 Rhino 对 String 参数的转换（JS ToString：整数无 .0）。 */
    private static String numberToString(double d) {
        if (d == Math.rint(d) && Math.abs(d) < 1e21) {
            return Long.toString((long) d);
        }
        // 1e21 以上按 JS 科学计数（简化：仅覆盖 golden 实际用到的常规数值）
        String s = Double.toString(d);
        return s;
    }

    private static String argAsString(JsonElement e) {
        if (e == null || e.isJsonNull()) return null;
        if (e.isJsonPrimitive()) {
            var p = e.getAsJsonPrimitive();
            if (p.isNumber()) return numberToString(p.getAsDouble());
            return p.getAsString();
        }
        return e.getAsString();
    }

    private static final Pattern titleNumPattern = Pattern.compile("(第)(.+?)(章)");

    // ---- StringUtils.stringToInt 复刻（fullToHalf + parseInt else chineseNumToInt）----
    private static final java.util.HashMap<Character, Integer> CHN = new java.util.HashMap<>();
    static {
        String a = "零一二三四五六七八九十", b = "〇壹贰叁肆伍陆柒捌玖拾";
        for (int i = 0; i < a.length(); i++) CHN.put(a.charAt(i), i);
        for (int i = 0; i < b.length(); i++) CHN.put(b.charAt(i), i);
        CHN.put('两', 2); CHN.put('百', 100); CHN.put('佰', 100);
        CHN.put('千', 1000); CHN.put('仟', 1000); CHN.put('万', 10000); CHN.put('亿', 100000000);
    }
    private static String fullToHalf(String s) {
        StringBuilder sb = new StringBuilder();
        for (char c : s.toCharArray()) {
            if (c == 12288) { sb.append(' '); continue; }
            if (c >= 65281 && c <= 65374) { sb.append((char) (c - 65248)); continue; }
            sb.append(c);
        }
        return sb.toString();
    }
    private static int chineseNumToInt(String chNum) {
        int result = 0, tmp = 0, billion = 0;
        char[] cn = chNum.toCharArray();
        try {
            for (int i = 0; i < cn.length; i++) {
                int n = CHN.get(cn[i]);
                if (n == 100000000) { result += tmp; result *= n; billion = billion * 100000000 + result; result = 0; tmp = 0; }
                else if (n == 10000) { result += tmp; result *= n; tmp = 0; }
                else if (n >= 10) { if (tmp == 0) tmp = 1; result += n * tmp; tmp = 0; }
                else {
                    if (i >= 2 && i == cn.length - 1 && CHN.get(cn[i - 1]) > 10) tmp = n * CHN.get(cn[i - 1]) / 10;
                    else tmp = tmp * 10 + n;
                }
            }
            result += tmp + billion;
            return result;
        } catch (Exception e) { return -1; }
    }
    private static int stringToInt(String str) {
        if (str == null) return -1;
        String num = fullToHalf(str).replaceAll("\\s+", "");
        try { return Integer.parseInt(num); }
        catch (Exception e) { return chineseNumToInt(num); }
    }

    // ---- HtmlFormatter.formatKeepImg(null) 复刻（legado 正则原样）----
    private static final Pattern nbspRegex = Pattern.compile("(&nbsp;)+");
    private static final Pattern espRegex = Pattern.compile("(&ensp;|&emsp;)");
    private static final Pattern noPrintRegex = Pattern.compile("(&thinsp;|&zwnj;|&zwj;|\u2009|\u200C|\u200D)");
    private static final Pattern wrapHtmlRegex = Pattern.compile("</?(?:div|p|br|hr|h\\d|article|dd|dl)[^>]*>");
    private static final Pattern commentRegex = Pattern.compile("<!--[^>]*-->");
    private static final Pattern notImgHtmlRegex = Pattern.compile("</?(?!img)[a-zA-Z]+(?=[ >])[^<>]*>");
    private static final Pattern formatImagePattern = Pattern.compile(
        "<img[^>]*\\ssrc\\s*=\\s*['\"]([^'\"{>]*\\{(?:[^{}]|\\{[^}>]+\\})+\\})['\"][^>]*>|<img[^>]*\\sdata-(?:src|original|srcset)\\s*=\\s*['\"]([^'\">]+)['\"][^>]*>|<img[^>]*\\ssrc\\s*=\\s*\"([^\">]+)\"[^>]*>|<img[^>]*\\s(?:data-[^=>]*|src)=\\s*['\"]([^'\">]*)['\"][^>]*>",
        Pattern.CASE_INSENSITIVE);
    private static final Pattern indent1Regex = Pattern.compile("\\s*\\n+\\s*");
    private static final Pattern indent2Regex = Pattern.compile("^[\\n\\s]+");
    private static final Pattern lastRegex = Pattern.compile("[\\n\\s]+$");

    private static String htmlFormat(String html) {
        if (html == null) return "";
        String s = nbspRegex.matcher(html).replaceAll(" ");
        s = espRegex.matcher(s).replaceAll(" ");
        s = noPrintRegex.matcher(s).replaceAll("");
        s = wrapHtmlRegex.matcher(s).replaceAll("\n");
        s = commentRegex.matcher(s).replaceAll("");
        s = notImgHtmlRegex.matcher(s).replaceAll("");
        s = indent1Regex.matcher(s).replaceAll("\n　　");
        s = indent2Regex.matcher(s).replaceAll("　　");
        s = lastRegex.matcher(s).replaceAll("");
        // formatKeepImg（redirectUrl=null）：getAbsoluteURL(null, src) 按 NetworkUtils 返回 trim 原串
        Matcher m = formatImagePattern.matcher(s);
        StringBuilder sb = new StringBuilder();
        int appendPos = 0;
        while (m.find()) {
            String group = m.group(1) != null ? m.group(1)
                    : m.group(2) != null ? m.group(2)
                    : m.group(3) != null ? m.group(3) : m.group(4);
            String param = "";
            if (m.group(1) != null) {
                // 含 {…} 参数：legado 用 AnalyzeUrl.paramPattern 切分；redirectUrl null 场景简化
                int brace = group.indexOf('{');
                if (brace >= 0) { param = "," + group.substring(brace + 1, group.length() - 1); group = group.substring(0, brace); }
            }
            sb.append(s, appendPos, m.start()).append("<img src=\"").append(group).append(param).append("\">");
            appendPos = m.end();
        }
        if (appendPos < s.length()) sb.append(s.substring(appendPos));
        return sb.toString();
    }

    public static JsonObject run(JsonObject c) {
        JsonObject out = new JsonObject();
        out.addProperty("name", c.get("name").getAsString());
        String method = c.get("method").getAsString();
        out.addProperty("method", method);
        JsonArray argsArr = c.getAsJsonArray("args");
        out.add("args", argsArr);
        if (c.has("hex")) out.addProperty("hex", c.get("hex").getAsString());

        try {
            switch (method) {
                case "md5Encode": {
                    String input = argAsString(argsArr.size() > 0 ? argsArr.get(0) : null);
                    out.addProperty("result", DigestUtil.digester("MD5").digestHex(input));
                    break;
                }
                case "md5Encode16": {
                    String input = argAsString(argsArr.size() > 0 ? argsArr.get(0) : null);
                    String full = DigestUtil.digester("MD5").digestHex(input);
                    out.addProperty("result", full.length() >= 24 ? full.substring(8, 24) : full);
                    break;
                }
                case "base64Encode": {
                    String input = argAsString(argsArr.size() > 0 ? argsArr.get(0) : null);
                    out.addProperty("result", Base64.encode(input == null ? "" : input));
                    break;
                }
                case "base64Decode": {
                    String input = argAsString(argsArr.size() > 0 ? argsArr.get(0) : null);
                    out.addProperty("result", Base64.decodeStr(input == null ? "" : input));
                    break;
                }
                case "hexEncodeToString": {
                    String input = argAsString(argsArr.size() > 0 ? argsArr.get(0) : null);
                    out.addProperty("result", HexUtil.encodeHexStr(input == null ? "" : input));
                    break;
                }
                case "hexDecodeToString": {
                    String input = argAsString(argsArr.size() > 0 ? argsArr.get(0) : null);
                    // Kotlin hexDecodeToString = HexUtil.decodeHexStr(hex)：空串原样返回 ""，非法字符抛错
                    out.addProperty("result", HexUtil.decodeHexStr(input == null ? "" : input));
                    break;
                }
                case "t2s": {
                    fixT2sDict();
                    String input = argAsString(argsArr.size() > 0 ? argsArr.get(0) : null);
                    out.addProperty("result", ChineseUtils.t2s(input == null ? "" : input));
                    break;
                }
                case "s2t": {
                    String input = argAsString(argsArr.size() > 0 ? argsArr.get(0) : null);
                    out.addProperty("result", ChineseUtils.s2t(input == null ? "" : input));
                    break;
                }
                case "timeFormat": {
                    long ms = argsArr.size() > 0 ? (long) argsArr.get(0).getAsDouble() : 0L;
                    SimpleDateFormat f = new SimpleDateFormat("yyyy/MM/dd HH:mm", Locale.getDefault());
                    f.setTimeZone(TimeZone.getDefault());
                    out.addProperty("result", f.format(new Date(ms)));
                    break;
                }
                case "timeFormatUTC": {
                    long ms = argsArr.size() > 0 ? (long) argsArr.get(0).getAsDouble() : 0L;
                    String format = argAsString(argsArr.get(1));
                    int sh = argsArr.size() > 2 ? argsArr.get(2).getAsInt() : 0;
                    SimpleDateFormat f = new SimpleDateFormat(format, Locale.getDefault());
                    f.setTimeZone(new SimpleTimeZone(sh, "UTC"));
                    out.addProperty("result", f.format(new Date(ms)));
                    break;
                }
                case "encodeURI": {
                    String input = argAsString(argsArr.size() > 0 ? argsArr.get(0) : null);
                    try { out.addProperty("result", URLEncoder.encode(input, "UTF-8")); }
                    catch (Exception e) { out.addProperty("result", ""); }
                    break;
                }
                case "toNumChapter": {
                    String input = argAsString(argsArr.size() > 0 ? argsArr.get(0) : null);
                    if (input == null) { out.add("result", com.google.gson.JsonNull.INSTANCE); break; }
                    Matcher m = titleNumPattern.matcher(input);
                    if (m.find()) {
                        out.addProperty("result", m.group(1) + stringToInt(m.group(2)) + m.group(3));
                    } else out.addProperty("result", input);
                    break;
                }
                case "htmlFormat": {
                    String input = argAsString(argsArr.size() > 0 ? argsArr.get(0) : null);
                    out.addProperty("result", htmlFormat(input == null ? "" : input));
                    break;
                }
                case "strToBytes": {
                    String input = argAsString(argsArr.size() > 0 ? argsArr.get(0) : null);
                    byte[] bytes = (input == null ? "" : input).getBytes(StandardCharsets.UTF_8);
                    StringBuilder hex = new StringBuilder();
                    for (byte b : bytes) hex.append(String.format("%02x", b));
                    out.addProperty("result", hex.toString());
                    break;
                }
                case "bytesToStr": {
                    String hex = c.has("hex") ? c.get("hex").getAsString() : "";
                    byte[] bytes = HexUtil.decodeHex(hex);
                    out.addProperty("result", new String(bytes, StandardCharsets.UTF_8));
                    break;
                }
                default:
                    throw new IllegalArgumentException("未知 jsExt method: " + method);
            }
        } catch (Exception e) {
            out.addProperty("error", e.getClass().getSimpleName() + ": " + e.getMessage());
        }
        return out;
    }
}
