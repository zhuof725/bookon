package golden;

import cn.hutool.core.codec.PercentCodec;
import cn.hutool.core.net.RFC3986;
import com.google.gson.Gson;
import com.google.gson.GsonBuilder;
import com.google.gson.JsonDeserializationContext;
import com.google.gson.JsonDeserializer;
import com.google.gson.JsonElement;
import com.google.gson.JsonObject;
import com.google.gson.JsonPrimitive;
import com.google.gson.Strictness;
import com.google.gson.ToNumberPolicy;
import org.mozilla.javascript.Context;
import org.mozilla.javascript.Scriptable;
import org.mozilla.javascript.ScriptableObject;
import org.mozilla.javascript.Undefined;
import org.mozilla.javascript.Wrapper;

import java.lang.reflect.Type;
import java.net.URLEncoder;
import java.nio.charset.Charset;
import java.util.BitSet;
import java.util.LinkedHashMap;
import java.util.Map;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

/**
 * 第 6 步 6A golden：AnalyzeUrl 的规则解析 / 编码 / UrlOption / Cookie 纯函数。
 *
 * ⚠️ README 需标明：本文件里的 encodeParams/analyzeJs/replaceKeyPageJs/analyzeUrl 是 AnalyzeUrl.kt
 * 调度逻辑的**手工 Java 移植**（用于给 Swift 侧提供对照），它只验证真实库的行为
 * （hutool PercentCodec/RFC3986/URLEncoder、Gson 宽松解析、Rhino 1.8.1、java.net.URL）。
 */
public final class UrlRuleGen {
    private UrlRuleGen() {}

    // ==================== 1) 编码 ====================

    private static final BitSet notNeedEncodingQuery = new BitSet(256);
    private static final BitSet notNeedEncodingForm = new BitSet(256);
    static {
        for (int i = 'a'; i <= 'z'; i++) notNeedEncodingQuery.set(i);
        for (int i = 'A'; i <= 'Z'; i++) notNeedEncodingQuery.set(i);
        for (int i = '0'; i <= '9'; i++) notNeedEncodingQuery.set(i);
        for (char c : "!$&()*+,-./:;=?@[\\]^_`{|}~".toCharArray()) notNeedEncodingQuery.set(c);
        for (int i = 'a'; i <= 'z'; i++) notNeedEncodingForm.set(i);
        for (int i = 'A'; i <= 'Z'; i++) notNeedEncodingForm.set(i);
        for (int i = '0'; i <= '9'; i++) notNeedEncodingForm.set(i);
        for (char c : "*-._".toCharArray()) notNeedEncodingForm.set(c);
    }

    private static final PercentCodec queryEncoder =
            RFC3986.UNRESERVED.orNew(PercentCodec.of("!$%&()*+,/:;=?@[\\]^`{|}"));

    static boolean isDigit16Char(char c) {
        return (c >= '0' && c <= '9') || (c >= 'A' && c <= 'F') || (c >= 'a' && c <= 'f');
    }

    static boolean encodedQuery(String str) { return alreadyEncoded(str, notNeedEncodingQuery); }

    static boolean encodedForm(String str) { return alreadyEncoded(str, notNeedEncodingForm); }

    private static boolean alreadyEncoded(String str, BitSet safe) {
        boolean needEncode = false;
        int i = 0;
        while (i < str.length()) {
            char c = str.charAt(i);
            if (safe.get(c)) { i++; continue; }
            if (c == '%' && i + 2 < str.length()) {
                char c1 = str.charAt(++i);
                char c2 = str.charAt(++i);
                if (isDigit16Char(c1) && isDigit16Char(c2)) { i++; continue; }
            }
            needEncode = true;
            break;
        }
        return !needEncode;
    }

    static String escape(String src) {
        StringBuilder tmp = new StringBuilder();
        for (char c : src.toCharArray()) {
            int code = c;
            if ((code >= 48 && code <= 57) || (code >= 65 && code <= 90) || (code >= 97 && code <= 122)) {
                tmp.append(c);
                continue;
            }
            String prefix = code < 16 ? "%0" : (code < 256 ? "%" : "%u");
            tmp.append(prefix).append(Integer.toString(code, 16));
        }
        return tmp.toString();
    }

    /** Kotlin AnalyzeUrl.encodeParams 的手工移植。 */
    static String encodeParams(String params, String charsetName, boolean isQuery) {
        boolean checkEncoded = charsetName == null || charsetName.isEmpty();
        Charset charset;
        if (charsetName == null || charsetName.isEmpty()) charset = java.nio.charset.StandardCharsets.UTF_8;
        else if ("escape".equals(charsetName)) charset = null;
        else charset = Charset.forName(charsetName);
        if (isQuery && charset != null) {
            if (encodedQuery(params)) return params;
            return queryEncoder.encode(params, charset);
        }
        int len = params.length();
        StringBuilder sb = new StringBuilder();
        int pos = 0;
        while (pos <= len) {
            if (sb.length() > 0) sb.append("&");
            int ampOffset = params.indexOf('&', pos);
            if (ampOffset == -1) ampOffset = len;
            int eqOffset = params.indexOf('=', pos);
            String key, value;
            if (eqOffset == -1 || eqOffset > ampOffset) {
                key = params.substring(pos, ampOffset);
                value = null;
            } else {
                key = params.substring(pos, eqOffset);
                value = params.substring(eqOffset + 1, ampOffset);
            }
            appendEncoded(sb, key, checkEncoded, charset);
            if (value != null) {
                sb.append("=");
                appendEncoded(sb, value, checkEncoded, charset);
            }
            pos = ampOffset + 1;
        }
        return sb.toString();
    }

    private static void appendEncoded(StringBuilder sb, String value, boolean checkEncoded, Charset charset) {
        if (checkEncoded && encodedForm(value)) sb.append(value);
        else if (charset == null) sb.append(escape(value));
        else {
            try {
                sb.append(URLEncoder.encode(value, charset.name()));
            } catch (Exception e) {
                throw new IllegalStateException(e);
            }
        }
    }

    /** 单条编码用例。 */
    public static JsonObject runCodec(JsonObject c) {
        JsonObject out = new JsonObject();
        String name = c.get("name").getAsString();
        String kind = c.has("kind") ? c.get("kind").getAsString() : "encodeParams";
        String params = c.has("params") && !c.get("params").isJsonNull() ? c.get("params").getAsString() : null;
        String charset = c.has("charset") && !c.get("charset").isJsonNull() ? c.get("charset").getAsString() : null;
        boolean isQuery = c.has("isQuery") && c.get("isQuery").getAsBoolean();
        out.addProperty("name", name);
        out.addProperty("kind", kind);
        out.add("params", params == null ? com.google.gson.JsonNull.INSTANCE : new JsonPrimitive(params));
        out.add("charset", charset == null ? com.google.gson.JsonNull.INSTANCE : new JsonPrimitive(charset));
        out.addProperty("isQuery", isQuery);
        try {
            String result;
            switch (kind) {
                case "encodedQuery": result = Boolean.toString(encodedQuery(params == null ? "" : params)); break;
                case "encodedForm": result = Boolean.toString(encodedForm(params == null ? "" : params)); break;
                case "escape": result = escape(params == null ? "" : params); break;
                default: result = encodeParams(params == null ? "" : params, charset, isQuery);
            }
            out.addProperty("result", result);
        } catch (Exception e) {
            out.addProperty("error", e.getClass().getName() + ": " + e.getMessage());
        }
        return out;
    }

    // ==================== 2) UrlOption（真实 Gson + legado 定制适配器） ====================

    /** legado GsonExtensions.kt 的 StringJsonDeserializer。 */
    static class StringJsonDeserializer implements JsonDeserializer<String> {
        @Override
        public String deserialize(JsonElement json, Type typeOfT, JsonDeserializationContext context) {
            if (json.isJsonPrimitive()) return json.getAsString();
            if (json.isJsonNull()) return null;
            return json.toString();
        }
    }

    /** legado GsonExtensions.kt 的 IntJsonDeserializer（非 number 一律 null，不抛错）。 */
    static class IntJsonDeserializer implements JsonDeserializer<Integer> {
        @Override
        public Integer deserialize(JsonElement json, Type typeOfT, JsonDeserializationContext context) {
            if (json.isJsonPrimitive() && json.getAsJsonPrimitive().isNumber()) {
                return json.getAsJsonPrimitive().getAsNumber().intValue();
            }
            return null;
        }
    }

    static final Gson GSON = new GsonBuilder()
            .registerTypeAdapter(String.class, new StringJsonDeserializer())
            .registerTypeAdapter(int.class, new IntJsonDeserializer())
            .registerTypeAdapter(Integer.class, new IntJsonDeserializer())
            .setObjectToNumberStrategy(ToNumberPolicy.LONG_OR_DOUBLE)
            .disableHtmlEscaping()
            .create();

    static final Gson GSON_STRICT = GSON.newBuilder().setStrictness(Strictness.STRICT).create();

    /** AnalyzeUrl.UrlOption 的等价 Java 类（字段名与 Kotlin 一致，Gson 反射写字段）。 */
    static class UrlOptionJava {
        private String method;
        private String charset;
        private Object headers;
        private Object body;
        private String origin;
        private Integer retry;
        private String type;
        private Object webView;
        private String webJs;
        private String dnsIp;
        private String js;
        private String bodyJs;
        private Long serverID;
        private Long webViewDelayTime;

        String getMethod() { return method; }
        String getCharset() { return charset; }
        String getOrigin() { return origin; }
        int getRetry() { return retry == null ? 0 : retry; }
        String getType() { return type; }
        String getWebJs() { return webJs; }
        String getDnsIp() { return dnsIp; }
        String getJs() { return js; }
        String getBodyJs() { return bodyJs; }
        Long getServerID() { return serverID; }
        Long getWebViewDelayTime() { return webViewDelayTime; }

        boolean useWebView() {
            Object v = webView;
            if (v == null) return false;
            if (v instanceof String && ((String) v).isEmpty()) return false;
            if (v instanceof Boolean && !((Boolean) v)) return false;
            return !(v instanceof String) || !"false".equals(v);
        }

        @SuppressWarnings("unchecked")
        Map<String, Object> getHeaderMap() {
            Object v = headers;
            if (v instanceof Map) return (Map<String, Object>) v;
            if (v instanceof String) {
                try {
                    return GSON.fromJson((String) v, Map.class);
                } catch (Exception e) {
                    return null;
                }
            }
            return null;
        }

        String getBody() {
            if (body == null) return null;
            if (body instanceof String) return (String) body;
            return GSON.toJson(body);
        }
    }

    public static JsonObject runUrlOption(JsonObject c) {
        JsonObject out = new JsonObject();
        String name = c.get("name").getAsString();
        String json = c.has("json") && !c.get("json").isJsonNull() ? c.get("json").getAsString() : null;
        out.addProperty("name", name);
        out.add("json", json == null ? com.google.gson.JsonNull.INSTANCE : new JsonPrimitive(json));
        boolean ok = false;
        boolean usedLenient = false;
        String dump = null;
        try {
            UrlOptionJava option = null;
            if (json != null) {
                try {
                    option = GSON_STRICT.fromJson(json, UrlOptionJava.class);
                } catch (Exception ignored) {
                }
                if (option == null) {
                    try {
                        option = GSON.fromJson(json, UrlOptionJava.class);
                        if (option != null) usedLenient = true;
                    } catch (Exception ignored) {
                    }
                }
            }
            if (option != null) {
                ok = true;
                dump = dumpOption(option);
            }
        } catch (Exception e) {
            out.addProperty("error", e.getClass().getName() + ": " + e.getMessage());
        }
        out.addProperty("ok", ok);
        out.addProperty("usedLenient", usedLenient);
        out.add("dump", dump == null ? com.google.gson.JsonNull.INSTANCE : new JsonPrimitive(dump));
        return out;
    }

    private static String dumpOption(UrlOptionJava o) {
        StringBuilder sb = new StringBuilder();
        sb.append("method=").append(o.getMethod() == null ? "<null>" : o.getMethod()).append('\n');
        sb.append("charset=").append(o.getCharset() == null ? "<null>" : o.getCharset()).append('\n');
        sb.append("origin=").append(o.getOrigin() == null ? "<null>" : o.getOrigin()).append('\n');
        sb.append("retry=").append(o.getRetry()).append('\n');
        sb.append("type=").append(o.getType() == null ? "<null>" : o.getType()).append('\n');
        sb.append("webJs=").append(o.getWebJs() == null ? "<null>" : o.getWebJs()).append('\n');
        sb.append("dnsIp=").append(o.getDnsIp() == null ? "<null>" : o.getDnsIp()).append('\n');
        sb.append("js=").append(o.getJs() == null ? "<null>" : o.getJs()).append('\n');
        sb.append("bodyJs=").append(o.getBodyJs() == null ? "<null>" : o.getBodyJs()).append('\n');
        sb.append("serverID=").append(o.getServerID() == null ? "<null>" : o.getServerID().toString()).append('\n');
        sb.append("webViewDelayTime=").append(o.getWebViewDelayTime() == null ? "<null>" : o.getWebViewDelayTime().toString()).append('\n');
        sb.append("useWebView=").append(o.useWebView()).append('\n');
        Map<String, Object> hm = o.getHeaderMap();
        if (hm == null) {
            sb.append("headerMap=<null>");
        } else {
            StringBuilder h = new StringBuilder();
            for (Map.Entry<String, Object> e : hm.entrySet()) {
                if (h.length() > 0) h.append(';');
                h.append(e.getKey()).append('=').append(String.valueOf(e.getValue()));
            }
            sb.append("headerMap=").append(h);
        }
        sb.append('\n');
        sb.append("body=").append(o.getBody() == null ? "<null>" : o.getBody());
        return sb.toString();
    }

    // ==================== 3) AnalyzeUrl 规则解析（手工移植调度逻辑） ====================

    private static final Pattern PARAM_PATTERN = Pattern.compile("\\s*,\\s*(?=\\{)");
    private static final Pattern PAGE_PATTERN = Pattern.compile("<(.*?)>");
    private static final Pattern JS_PATTERN =
            Pattern.compile("<js>([\\w\\W]*?)</js>|@js:([\\w\\W]*)", Pattern.CASE_INSENSITIVE);

    public static JsonObject runAnalyzeUrl(JsonObject c) {
        JsonObject out = new JsonObject();
        String name = c.get("name").getAsString();
        String ruleUrl0 = c.get("ruleUrl").getAsString();
        String baseUrl0 = c.has("baseUrl") && !c.get("baseUrl").isJsonNull() ? c.get("baseUrl").getAsString() : "";
        Integer page = c.has("page") && !c.get("page").isJsonNull() ? c.get("page").getAsInt() : null;
        out.addProperty("name", name);
        out.addProperty("ruleUrl", ruleUrl0);
        out.addProperty("baseUrl", baseUrl0);
        out.add("page", page == null ? com.google.gson.JsonNull.INSTANCE : new JsonPrimitive(page));
        try {
            String baseUrl = baseUrl0;
            Matcher bm = PARAM_PATTERN.matcher(baseUrl);
            if (bm.find()) baseUrl = baseUrl.substring(0, bm.start());

            String ruleUrl = ruleUrl0;
            // analyzeJs
            int start = 0;
            Matcher jsMatcher = JS_PATTERN.matcher(ruleUrl);
            String result = ruleUrl;
            while (jsMatcher.find()) {
                if (jsMatcher.start() > start) {
                    String seg = ruleUrl.substring(start, jsMatcher.start()).trim();
                    if (!seg.isEmpty()) result = seg.replace("@result", result);
                }
                String jsSrc = jsMatcher.group(2) != null ? jsMatcher.group(2) : jsMatcher.group(1);
                result = evalJs(jsSrc, result, baseUrl, page);
                start = jsMatcher.end();
            }
            if (ruleUrl.length() > start) {
                String seg = ruleUrl.substring(start).trim();
                if (!seg.isEmpty()) result = seg.replace("@result", result);
            }
            ruleUrl = result;

            // replaceKeyPageJs（{{}} 内嵌规则：逐段用 consumeTo 语义替换）
            if (ruleUrl.contains("{{") && ruleUrl.contains("}}")) {
                ruleUrl = replaceInnerRule(ruleUrl, baseUrl, page);
            }
            if (page != null) {
                Matcher matcher = PAGE_PATTERN.matcher(ruleUrl);
                while (matcher.find()) {
                    String[] pages = matcher.group(1).split(",");
                    String replacement = page < pages.length
                            ? pages[page - 1].trim()
                            : pages[pages.length - 1].trim();
                    ruleUrl = ruleUrl.replace(matcher.group(), replacement);
                }
            }

            // analyzeUrl
            Matcher urlMatcher = PARAM_PATTERN.matcher(ruleUrl);
            String urlNoOption = urlMatcher.find() ? ruleUrl.substring(0, urlMatcher.start()) : ruleUrl;
            String url = UrlResolver.getAbsoluteURL(baseUrl, urlNoOption);
            String baseFromUrl = getBaseUrl(url);
            if (baseFromUrl != null) baseUrl = baseFromUrl;

            String method = "GET";
            String charset = null;
            String body = null;
            String encodedQuery = null;
            String encodedForm = null;
            if (urlNoOption.length() != ruleUrl.length()) {
                String urlOptionStr = ruleUrl.substring(urlMatcher.end());
                UrlOptionJava option = null;
                try {
                    option = GSON_STRICT.fromJson(urlOptionStr, UrlOptionJava.class);
                } catch (Exception ignored) {
                }
                if (option == null) {
                    try {
                        option = GSON.fromJson(urlOptionStr, UrlOptionJava.class);
                    } catch (Exception ignored) {
                    }
                }
                if (option != null) {
                    String m = option.getMethod();
                    if (m != null) {
                        String up = m.toUpperCase();
                        method = "POST".equals(up) ? "POST" : ("HEAD".equals(up) ? "HEAD" : "GET");
                    }
                    charset = option.getCharset();
                    if (option.getJs() != null) url = evalJs(option.getJs(), url, baseUrl, page);
                    body = option.getBody();
                }
            }
            String urlNoQuery = url;
            if ("POST".equals(method)) {
                if (body != null && !isJson(body) && !isXml(body)) {
                    encodedForm = encodeParams(body, charset, false);
                }
            } else {
                int pos = url.indexOf('?');
                if (pos != -1) {
                    encodedQuery = encodeParams(url.substring(pos + 1), charset, true);
                    urlNoQuery = url.substring(0, pos);
                }
            }
            out.addProperty("urlNoQuery", urlNoQuery);
            out.addProperty("resultUrl", url);
            out.addProperty("method", method);
            out.add("encodedQuery", encodedQuery == null ? com.google.gson.JsonNull.INSTANCE : new JsonPrimitive(encodedQuery));
            out.add("encodedForm", encodedForm == null ? com.google.gson.JsonNull.INSTANCE : new JsonPrimitive(encodedForm));
        } catch (Exception e) {
            out.addProperty("error", e.getClass().getName() + ": " + e.getMessage());
        }
        return out;
    }

    /** 对齐 Kotlin RuleAnalyzer.innerRule(startStr, endStr, fr) 的逐段替换（Swift 侧同语义）。 */
    private static String replaceInnerRule(String src, String baseUrl, Integer page) {
        StringBuilder st = new StringBuilder();
        int pos = 0, startX = 0;
        int startU = 2, endU = 2;
        while (true) {
            int idx = src.indexOf("{{", pos);
            if (idx == -1) break;
            pos = idx + startU;
            int posPre = pos;
            int end = src.indexOf("}}", pos);
            if (end == -1) break;
            String inner = src.substring(posPre, end);
            String frv = evalJs(inner, "", baseUrl, page);
            st.append(src, startX, posPre - startU).append(frv);
            pos = end + endU;
            startX = pos;
        }
        if (startX == 0) return src;
        st.append(src.substring(startX));
        return st.toString();
    }

    /** 用真实 Rhino 1.8.1 求值一段 JS（绑定 result），返回 toString（null -> "null"）。 */
    static String evalJs(String js, String result, String baseUrl, Integer page) {
        try (Context cx = Context.enter()) {
            cx.setLanguageVersion(Context.VERSION_ES6);
            cx.setInterpretedMode(true);
            Scriptable scope = cx.initStandardObjects();
            ScriptableObject.putProperty(scope, "result", result);
            ScriptableObject.putProperty(scope, "baseUrl", baseUrl);
            if (page != null) ScriptableObject.putProperty(scope, "page", page);
            Object r = cx.evaluateString(scope, js, "analyzeUrlJs", 1, null);
            if (r instanceof Wrapper) r = ((Wrapper) r).unwrap();
            if (r == null || r == Undefined.instance) return "null";
            return r.toString();
        }
    }

    /** 对应 NetworkUtils.getBaseUrl(url)：http(s):// 前缀时取到首个 '/' 之前。 */
    static String getBaseUrl(String url) {
        if (url == null) return null;
        String lower = url.toLowerCase();
        if (lower.startsWith("http://") || lower.startsWith("https://")) {
            int index = url.indexOf('/', 9);
            return index == -1 ? url : url.substring(0, index);
        }
        return null;
    }

    static boolean isJson(String s) {
        String t = s.trim();
        return (t.startsWith("{") && t.endsWith("}")) || (t.startsWith("[") && t.endsWith("]"));
    }

    static boolean isXml(String s) {
        String t = s.trim();
        return t.startsWith("<") && t.endsWith(">");
    }

    // ==================== 4) Cookie 纯函数 ====================

    static LinkedHashMap<String, String> cookieToMap(String cookie) {
        LinkedHashMap<String, String> map = new LinkedHashMap<>();
        if (cookie == null || cookie.trim().isEmpty()) return map;
        String[] pairs = cookie.split(";", -1);
        int end = pairs.length;
        while (end > 0 && pairs[end - 1].isEmpty()) end--;
        for (int i = 0; i < end; i++) {
            String pair = pairs[i];
            String[] kv = pair.split("=", 2);
            if (kv.length <= 1) continue;
            String key = kv[0].trim();
            String value = kv[1];
            if (!value.trim().isEmpty() || value.trim().equals("null")) {
                map.put(key, value.trim());
            }
        }
        return map;
    }

    static String mapToCookie(Map<String, String> map) {
        if (map == null || map.isEmpty()) return null;
        StringBuilder sb = new StringBuilder();
        for (Map.Entry<String, String> e : map.entrySet()) {
            if (sb.length() > 0) sb.append("; ");
            sb.append(e.getKey()).append('=').append(e.getValue());
        }
        return sb.toString();
    }

    static String mergeCookies(String... cookies) {
        LinkedHashMap<String, String> merged = new LinkedHashMap<>();
        for (String c : cookies) {
            if (c == null) continue;
            merged.putAll(cookieToMap(c));
        }
        return mapToCookie(merged);
    }

    public static JsonObject runCookie(JsonObject c) {
        JsonObject out = new JsonObject();
        String name = c.get("name").getAsString();
        String op = c.get("op").getAsString();
        out.addProperty("name", name);
        out.addProperty("op", op);
        if (c.has("cookies")) out.add("cookies", c.get("cookies"));
        if (c.has("cookie")) out.addProperty("cookie", c.get("cookie").getAsString());
        try {
            String result;
            switch (op) {
                case "cookieToMap": {
                    result = mapToCookie(cookieToMap(c.get("cookie").getAsString()));
                    break;
                }
                case "mapToCookie": {
                    LinkedHashMap<String, String> map = new LinkedHashMap<>();
                    for (JsonElement e : c.getAsJsonArray("pairs")) {
                        JsonObject p = e.getAsJsonObject();
                        map.put(p.get("k").getAsString(), p.get("v").getAsString());
                    }
                    result = mapToCookie(map);
                    break;
                }
                case "mergeCookies": {
                    java.util.List<String> list = new java.util.ArrayList<>();
                    for (JsonElement e : c.getAsJsonArray("cookies")) {
                        list.add(e.isJsonNull() ? null : e.getAsString());
                    }
                    result = mergeCookies(list.toArray(new String[0]));
                    break;
                }
                default:
                    throw new IllegalArgumentException("未知 cookie op: " + op);
            }
            out.add("result", result == null ? com.google.gson.JsonNull.INSTANCE : new JsonPrimitive(result));
        } catch (Exception e) {
            out.addProperty("error", e.getClass().getName() + ": " + e.getMessage());
        }
        return out;
    }
}
