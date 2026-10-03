package golden;

import cn.hutool.core.codec.Base64;
import cn.hutool.core.util.HexUtil;
import cn.hutool.crypto.digest.DigestUtil;
import com.github.liuyueyi.quick.transfer.ChineseUtils;
import com.github.liuyueyi.quick.transfer.constants.TransType;
import com.google.gson.JsonArray;
import com.google.gson.JsonElement;
import com.google.gson.JsonNull;
import com.google.gson.JsonObject;
import org.jsoup.Jsoup;
import org.mozilla.javascript.ConsString;
import org.mozilla.javascript.Context;
import org.mozilla.javascript.Scriptable;
import org.mozilla.javascript.ScriptableObject;
import org.mozilla.javascript.Undefined;
import org.mozilla.javascript.Wrapper;

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
 *  - bytesToStr/strToBytes：UTF-8 / GBK / ISO-8859-1（Java new String(bytes, charset) 语义）
 *  - Jsoup.parse 链（{@link #runJsoup}）：真实 Rhino 1.8.1 求值同一条 JS，classpath 上是
 *    真实 jsoup 1.16.2 —— 与 Swift 侧 JsoupJSBridge（SwiftSoup 替身）比较同一表达式结果。
 *  - Java MessageDigest 直算（{@link #runJavaDigest}）：供端到端测试取真实期望值。
 * 数字入参不再有手写规则：JS number → Java String 参数的一律取
 * {@link NumberArgGen#receivedForLiteral}（真实 Rhino 1.8.1 跑出来的结果）。
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

    /**
     * JS 数字 → Java String 参数：**不是**手写规则，取真实 Rhino 1.8.1 的转换结果
     * （见 {@link NumberArgGen}；legado 用同一个 Rhino，走
     * NativeJavaObject.coerceTypeImpl -> ScriptRuntime.toString -> DoubleFormatter）。
     * 这里把字面量原文交给 Rhino 求值，取它实际传进 String 参数的那一串。
     */
    private static String numberToString(String literal) {
        return NumberArgGen.receivedForLiteral(literal);
    }

    private static String argAt(List<String> args, int index) {
        return index < args.size() ? args.get(index) : null;
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
        JsonArray argsJs = c.has("argsJs") ? c.getAsJsonArray("argsJs") : null;
        out.add("args", argsArr);
        if (argsJs != null) out.add("argsJs", argsJs);
        // Swift 侧不再自己推导「JS 数字 → 字符串」：这里逐条给出真实 Rhino 转出的参数串
        // （字符串参数原样、null 原样、数字走 NumberArgGen），Swift 直接读 argStrings 使用。
        // argsJs 用于 JSON 表达不了的 JS 字面量（NaN / Infinity / -0 …），直接按 JS 源码求值。
        List<String> argList = new ArrayList<>();
        JsonArray argStrings = new JsonArray();
        for (int i = 0; i < argsArr.size(); i++) {
            JsonElement e = argsArr.get(i);
            String s;
            if (argsJs != null && i < argsJs.size() && !argsJs.get(i).isJsonNull()) {
                s = numberToString(argsJs.get(i).getAsString());
            } else if (e == null || e.isJsonNull()) {
                s = null;
            } else if (e.isJsonPrimitive()) {
                var p = e.getAsJsonPrimitive();
                s = p.isNumber() ? numberToString(p.getAsString()) : p.getAsString();
            } else {
                s = e.getAsString();
            }
            argList.add(s);
            if (s == null) argStrings.add(JsonNull.INSTANCE); else argStrings.add(s);
        }
        out.add("argStrings", argStrings);
        if (c.has("hex")) out.addProperty("hex", c.get("hex").getAsString());
        if (c.has("charset")) out.addProperty("charset", c.get("charset").getAsString());

        try {
            switch (method) {
                case "md5Encode": {
                    String input = argAt(argList, 0);
                    out.addProperty("result", DigestUtil.digester("MD5").digestHex(input));
                    break;
                }
                case "md5Encode16": {
                    String input = argAt(argList, 0);
                    String full = DigestUtil.digester("MD5").digestHex(input);
                    out.addProperty("result", full.length() >= 24 ? full.substring(8, 24) : full);
                    break;
                }
                case "base64Encode": {
                    String input = argAt(argList, 0);
                    out.addProperty("result", Base64.encode(input == null ? "" : input));
                    break;
                }
                case "base64Decode": {
                    String input = argAt(argList, 0);
                    out.addProperty("result", Base64.decodeStr(input == null ? "" : input));
                    break;
                }
                case "hexEncodeToString": {
                    String input = argAt(argList, 0);
                    out.addProperty("result", HexUtil.encodeHexStr(input == null ? "" : input));
                    break;
                }
                case "hexDecodeToString": {
                    String input = argAt(argList, 0);
                    // Kotlin hexDecodeToString = HexUtil.decodeHexStr(hex)：空串原样返回 ""，非法字符抛错
                    out.addProperty("result", HexUtil.decodeHexStr(input == null ? "" : input));
                    break;
                }
                case "t2s": {
                    fixT2sDict();
                    String input = argAt(argList, 0);
                    out.addProperty("result", ChineseUtils.t2s(input == null ? "" : input));
                    break;
                }
                case "s2t": {
                    String input = argAt(argList, 0);
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
                    String format = argAt(argList, 1);
                    int sh = argsArr.size() > 2 ? argsArr.get(2).getAsInt() : 0;
                    SimpleDateFormat f = new SimpleDateFormat(format, Locale.getDefault());
                    f.setTimeZone(new SimpleTimeZone(sh, "UTC"));
                    out.addProperty("result", f.format(new Date(ms)));
                    break;
                }
                case "encodeURI": {
                    String input = argAt(argList, 0);
                    try { out.addProperty("result", URLEncoder.encode(input, "UTF-8")); }
                    catch (Exception e) { out.addProperty("result", ""); }
                    break;
                }
                case "toNumChapter": {
                    String input = argAt(argList, 0);
                    if (input == null) { out.add("result", com.google.gson.JsonNull.INSTANCE); break; }
                    Matcher m = titleNumPattern.matcher(input);
                    if (m.find()) {
                        out.addProperty("result", m.group(1) + stringToInt(m.group(2)) + m.group(3));
                    } else out.addProperty("result", input);
                    break;
                }
                case "htmlFormat": {
                    String input = argAt(argList, 0);
                    out.addProperty("result", htmlFormat(input == null ? "" : input));
                    break;
                }
                case "strToBytes": {
                    String input = argAt(argList, 0);
                    String charset = c.has("charset") ? c.get("charset").getAsString() : "UTF-8";
                    byte[] bytes = (input == null ? "" : input).getBytes(java.nio.charset.Charset.forName(charset));
                    StringBuilder hex = new StringBuilder();
                    for (byte b : bytes) hex.append(String.format("%02x", b));
                    out.addProperty("result", hex.toString());
                    break;
                }
                case "bytesToStr": {
                    String hex = c.has("hex") ? c.get("hex").getAsString() : "";
                    String charset = c.has("charset") ? c.get("charset").getAsString() : "UTF-8";
                    // hutool HexUtil.decodeHex("") 返回 null（与 decodeHexStr("") 返回 "" 不同），
                    // 空 hex 应按「零字节」处理：new String(new byte[0], charset) == ""。
                    byte[] bytes = hex.isEmpty() ? new byte[0] : HexUtil.decodeHex(hex);
                    // Java new String(bytes, charset)：非法字节按 CharsetDecoder 的 REPLACE 语义替换为 U+FFFD。
                    out.addProperty("result", new String(bytes, java.nio.charset.Charset.forName(charset)));
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

    // ==================== jsoup 替身 golden（真实 jsoup 1.16.2） ====================

    /**
     * 对**真实 jsoup 1.16.2** 对象执行与 Swift 替身完全相同的一条 JS 链：
     * 用真实 Rhino 1.8.1 求值 `js`（作用域里绑定 `result` = HTML），classpath 上是真实 jsoup，
     * 所以 `org.jsoup.Jsoup.parse(result)` / `Packages.org.jsoup.Jsoup.parse(result)` 都会落到
     * 真实的 org.jsoup 实现上。Swift 侧用 JSC + JsoupJSBridge 求值同一条 JS，两边比较
     * 「结果字符串 / 抛错」二态。
     *
     * 用例 JSON: {name, source, js, html}（Main 会把 htmls 里的 HTML 解析进 html 字段）。
     */
    public static JsonObject runJsoup(JsonObject c) {
        JsonObject out = new JsonObject();
        String name = c.get("name").getAsString();
        String js = c.get("js").getAsString();
        String html = c.get("html").getAsString();
        out.addProperty("name", name);
        out.addProperty("js", js);
        out.addProperty("html", html);
        if (c.has("source")) out.addProperty("source", c.get("source").getAsString());
        // 已登记到 README 差异表的用例：golden 必须原样带出标记，Swift 侧才能按登记处理
        // （不能悄悄丢掉，否则会变成"未登记的不一致"）。
        if (c.has("knownDivergence")) out.addProperty("knownDivergence", c.get("knownDivergence").getAsString());
        try (Context cx = Context.enter()) {
            cx.setLanguageVersion(Context.VERSION_ES6);
            cx.setInterpretedMode(true);
            ScriptableObject standard = cx.initStandardObjects();
            // 与 legado RhinoScriptEngine 一致：绑定放在**顶层对象下新建的子作用域**上
            // （原型链仍指向标准全局对象），而不是直接改 ImporterTopLevel 自己的属性。
            Scriptable scope = cx.newObject(standard);
            scope.setPrototype(standard);
            ScriptableObject.putProperty(scope, "result", html);
            // 真实书源的 JS 链里还会调 `java.t2s(...)`（台湾小说网 ruleContent.content），
            // 这里绑一个与 legado 同名同签名的探针（真实 quick-chinese-transfer 实现）。
            ScriptableObject.putProperty(scope, "java", Context.javaToJS(new NumberArgGen.Probe(), scope));
            Object r = cx.evaluateString(scope, js, name, 1, null);
            if (r instanceof Wrapper) r = ((Wrapper) r).unwrap();
            if (r instanceof ConsString) r = r.toString();
            if (r == null || r == Undefined.instance) {
                out.add("result", JsonNull.INSTANCE);
            } else {
                out.addProperty("result", r.toString());
            }
        } catch (Exception e) {
            out.addProperty("error", e.getClass().getName() + ": " + e.getMessage());
        }
        return out;
    }

    // ==================== Java MessageDigest 直算（端到端测试的期望值来源） ====================

    /**
     * 用具名算法（这里只用 MD5）在 golden 里算出真实摘要，供端到端测试取期望值，
     * 避免用 Swift 自己的 md5Encode 反推期望值（那样只能证明「自洽」，不能证明与 Java 一致）。
     * 用例 JSON: {name, algorithm, input}。
     */
    public static JsonObject runJavaDigest(JsonObject c) {
        JsonObject out = new JsonObject();
        String name = c.get("name").getAsString();
        String algorithm = c.get("algorithm").getAsString();
        String input = c.get("input").getAsString();
        out.addProperty("name", name);
        out.addProperty("algorithm", algorithm);
        out.addProperty("input", input);
        try {
            java.security.MessageDigest md = java.security.MessageDigest.getInstance(algorithm);
            byte[] digest = md.digest(input.getBytes(StandardCharsets.UTF_8));
            StringBuilder hex = new StringBuilder();
            for (byte b : digest) hex.append(String.format("%02x", b));
            out.addProperty("result", hex.toString());
        } catch (Exception e) {
            out.addProperty("error", e.getClass().getName() + ": " + e.getMessage());
        }
        return out;
    }
}
