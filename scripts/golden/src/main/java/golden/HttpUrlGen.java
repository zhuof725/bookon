package golden;

import com.google.gson.JsonNull;
import com.google.gson.JsonObject;
import com.google.gson.JsonPrimitive;
import okhttp3.HttpUrl;

import java.lang.reflect.Method;

/**
 * 第 6 步 6B golden：URL 规范化对照（**真实 OkHttp 5.3.2 的 HttpUrl**，与 legado 用的一致）。
 *
 *  - kind=httpUrl：直接 `HttpUrl.parse(input)`（失败为 null），输出 toString()；
 *  - kind=absoluteThenHttpUrl：先 `UrlResolver.getAbsoluteURL(base, input)`（java.net.URL 语义，
 *    第 4 步 C 已 golden 对照），再交给 HttpUrl；
 *  - 输出里同时给出中间串（getAbsoluteURL 的结果）与最终结果，方便定位差异在「拼接」还是「规范化」。
 *
 * ⚠️ OkHttp 5.x 的 Kotlin API 在不同小版本上名字不同（parse / get / toHttpUrlOrNull /
 * Companion.get），这里用反射按可用性择一，并在都不可用时抛出明确错误（不允许静默返回 null）。
 */
public final class HttpUrlGen {
    private HttpUrlGen() {}

    /** 解析入口（返回 null 表示 OkHttp 判定为非法 URL）。 */
    static HttpUrl parse(String s) {
        Method m = findParseMethod();
        if (m == null) {
            throw new IllegalStateException("OkHttp HttpUrl 解析 API 未命中（parse/get/toHttpUrlOrNull 都不可用）");
        }
        try {
            Object target = java.lang.reflect.Modifier.isStatic(m.getModifiers()) ? null : companionInstance();
            Object r = m.invoke(target, s);
            return (HttpUrl) r;
        } catch (java.lang.reflect.InvocationTargetException e) {
            // OkHttp 对非法 URL 抛 IllegalArgumentException -> 视为解析失败（返回 null）
            if (e.getCause() instanceof IllegalArgumentException) return null;
            throw new IllegalStateException("HttpUrl 解析异常: " + e.getCause(), e);
        } catch (Exception e) {
            throw new IllegalStateException("HttpUrl 解析调用失败", e);
        }
    }

    private static CompanionHolder holder = null;

    private static Object companionInstance() {
        if (holder == null) {
            try {
                Object c = HttpUrl.class.getField("Companion").get(null);
                holder = new CompanionHolder(c);
            } catch (Exception e) {
                throw new IllegalStateException("无法获取 HttpUrl.Companion", e);
            }
        }
        return holder.value;
    }

    private static final class CompanionHolder {
        final Object value;
        CompanionHolder(Object v) { this.value = v; }
    }

    private static Method parseMethod = null;
    private static boolean parseMethodResolved = false;

    private static Method findParseMethod() {
        if (parseMethodResolved) return parseMethod;
        parseMethodResolved = true;
        // 1) 静态方法：HttpUrl.get(String)（4.x 起）/ HttpUrl.parse(String)（老版本）
        for (String name : new String[]{"get", "parse"}) {
            try {
                Method m = HttpUrl.class.getMethod(name, String.class);
                if (java.lang.reflect.Modifier.isStatic(m.getModifiers())) {
                    parseMethod = m;
                    return parseMethod;
                }
            } catch (NoSuchMethodException ignored) {
            }
        }
        // 2) Kotlin companion 上的方法
        try {
            Class<?> comp = Class.forName("okhttp3.HttpUrl$Companion");
            for (String name : new String[]{"get", "toHttpUrlOrNull", "parse"}) {
                try {
                    Method m = comp.getMethod(name, String.class);
                    parseMethod = m;
                    return parseMethod;
                } catch (NoSuchMethodException ignored) {
                }
            }
        } catch (ClassNotFoundException ignored) {
        }
        // 3) Kotlin 顶层扩展函数（HttpUrlKt.toHttpUrlOrNull）
        try {
            Class<?> kt = Class.forName("okhttp3.HttpUrlKt");
            Method m = kt.getMethod("toHttpUrlOrNull", String.class);
            parseMethod = m;
            return parseMethod;
        } catch (Exception ignored) {
        }
        return null;
    }

    public static JsonObject run(JsonObject c) {
        JsonObject out = new JsonObject();
        String name = c.get("name").getAsString();
        String kind = c.has("kind") ? c.get("kind").getAsString() : "httpUrl";
        String input = c.has("input") && !c.get("input").isJsonNull() ? c.get("input").getAsString() : null;
        String base = c.has("base") && !c.get("base").isJsonNull() ? c.get("base").getAsString() : null;
        out.addProperty("name", name);
        out.addProperty("kind", kind);
        out.add("input", input == null ? JsonNull.INSTANCE : new JsonPrimitive(input));
        out.add("base", base == null ? JsonNull.INSTANCE : new JsonPrimitive(base));
        try {
            String candidate = input == null ? "" : input;
            if ("absoluteThenHttpUrl".equals(kind)) {
                candidate = UrlResolver.getAbsoluteURL(base, input == null ? "" : input);
                out.addProperty("intermediate", candidate);
            } else {
                out.add("intermediate", JsonNull.INSTANCE);
            }
            HttpUrl url = parse(candidate);
            if (url == null) {
                out.addProperty("ok", false);
                out.add("result", JsonNull.INSTANCE);
            } else {
                out.addProperty("ok", true);
                out.addProperty("result", url.toString());
            }
        } catch (Exception e) {
            out.addProperty("ok", false);
            out.addProperty("error", e.getClass().getName() + ": " + e.getMessage());
        }
        return out;
    }
}
