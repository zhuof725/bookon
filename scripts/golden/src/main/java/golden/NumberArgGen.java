package golden;

import cn.hutool.core.codec.Base64;
import cn.hutool.core.util.HexUtil;
import cn.hutool.crypto.digest.DigestUtil;
import com.github.liuyueyi.quick.transfer.ChineseUtils;
import com.google.gson.JsonNull;
import com.google.gson.JsonObject;
import org.mozilla.javascript.Context;
import org.mozilla.javascript.Scriptable;
import org.mozilla.javascript.ScriptableObject;

import java.net.URLEncoder;
import java.util.HashMap;
import java.util.Map;

/**
 * Step 5 收尾：用**真实 Rhino 1.8.1** 验证「JS number → Java String 参数」的真实转换结果，
 * 不靠任何手写规则（旧实现里 JsExtGen/Swift harness 各写了一套「整数无 .0」的假设，已删除）。
 *
 * 原理与 legado 完全一致：
 *  - legado 的 RhinoScriptEngine 把 JsExtensions 实例绑定为脚本里的 `java`（NativeJavaObject），
 *    JS 调 `java.md5Encode(1e21)` 时由 Rhino 的 NativeJavaMethod 走
 *    NativeJavaObject.coerceTypeImpl：JSTYPE_NUMBER && type == STRING -> ScriptRuntime.toString(value)，
 *    最终落到 Rhino 1.8.1 的 DoubleFormatter.toString(d)，其源码注释写明
 *    "Convert a double to String as defined in the Number::toString operation in ECMAScript"。
 *  - 这里用同样的方式：把 {@link Probe}（与 legado JsExtensions 同名同签名的 String 参数方法）
 *    绑定为 `java`，执行 `java.<method>(<literal>)`，记录 Rhino 实际传进来的字符串。
 *
 * 用法：JsExtGen 也复用本类的 {@link #receivedForLiteral(String)}，保证 Java 侧 harness 与
 * Rhino 真实转换是同一份结果（golden 里同时输出 javaReceived 供 Swift 逐条比较）。
 */
public final class NumberArgGen {
    private NumberArgGen() {}

    /**
     * 探针：方法名/签名与 legado JsExtensions 的「接受 String 的 Java 方法」一致。
     * 每个方法先把 Rhino 实际传入的字符串记到 {@link #lastReceived}，再执行真实计算
     * （这样 golden 里既有「Rhino 转成了什么」，也有「真实调用结果是什么」）。
     */
    public static final class Probe {
        public String lastReceived;
        public boolean lastReceivedWasNull;

        public String md5Encode(String s) {
            record(s);
            return s == null ? "" : DigestUtil.digester("MD5").digestHex(s);
        }

        public String base64Encode(String s) {
            record(s);
            return s == null ? "" : Base64.encode(s);
        }

        public String encodeURI(String s) {
            record(s);
            if (s == null) return "";
            try {
                return URLEncoder.encode(s, "UTF-8");
            } catch (Exception e) {
                return "";
            }
        }

        public String t2s(String s) {
            record(s);
            return s == null ? "" : ChineseUtils.t2s(s);
        }

        public String hexEncodeToString(String s) {
            record(s);
            return s == null ? "" : HexUtil.encodeHexStr(s);
        }

        private void record(String s) {
            lastReceived = s;
            lastReceivedWasNull = (s == null);
        }
    }

    /** 缓存：JS 数字字面量 -> Rhino 实际转出的 Java String。 */
    private static final Map<String, String> CACHE = new HashMap<>();
    private static final String NULL_SENTINEL = "\u0000<null>";

    /** literal -> Rhino 实际转换出的字符串（null 用哨兵缓存，返回真实 null）。 */
    public static synchronized String receivedForLiteral(String literal) {
        String cached = CACHE.get(literal);
        if (cached != null) return NULL_SENTINEL.equals(cached) ? null : cached;
        Probe probe = new Probe();
        try (Context cx = Context.enter()) {
            cx.setLanguageVersion(Context.VERSION_ES6);
            cx.setInterpretedMode(true);
            Scriptable scope = cx.initStandardObjects();
            ScriptableObject.putProperty(scope, "java", Context.javaToJS(probe, scope));
            cx.evaluateString(scope, "java.md5Encode(" + literal + ")", "numberArgProbe", 1, null);
        } catch (Exception e) {
            throw new IllegalStateException("Rhino 探针失败: literal=" + literal, e);
        }
        String received = probe.lastReceivedWasNull ? NULL_SENTINEL : probe.lastReceived;
        CACHE.put(literal, received);
        return probe.lastReceivedWasNull ? null : probe.lastReceived;
    }

    /** 单个 golden 用例：{name, method, literal} -> {name, method, literal, javaReceived, callResult}。 */
    public static JsonObject run(JsonObject c) {
        JsonObject out = new JsonObject();
        String name = c.get("name").getAsString();
        String method = c.get("method").getAsString();
        String literal = c.get("literal").getAsString();
        out.addProperty("name", name);
        out.addProperty("method", method);
        out.addProperty("literal", literal);
        if (c.has("knownDivergence")) out.addProperty("knownDivergence", c.get("knownDivergence").getAsString());
        try {
            String received = receivedForLiteral(literal);
            if (received == null) {
                out.add("javaReceived", JsonNull.INSTANCE);
            } else {
                out.addProperty("javaReceived", received);
            }
            Probe probe = new Probe();
            try (Context cx = Context.enter()) {
                cx.setLanguageVersion(Context.VERSION_ES6);
                cx.setInterpretedMode(true);
                Scriptable scope = cx.initStandardObjects();
                ScriptableObject.putProperty(scope, "java", Context.javaToJS(probe, scope));
                Object r = cx.evaluateString(scope, "java." + method + "(" + literal + ")",
                        name, 1, null);
                // Rhino 的 javaPrimitiveWrap 默认 true：Java String 返回值会被包成 NativeJavaObject，
                // 必须像 RhinoGen 一样先拆箱（否则 toString() 得到的是对象 identity hash）。
                if (r instanceof org.mozilla.javascript.Wrapper) {
                    r = ((org.mozilla.javascript.Wrapper) r).unwrap();
                }
                if (r instanceof org.mozilla.javascript.ConsString) r = r.toString();
                if (r == null) {
                    out.add("callResult", JsonNull.INSTANCE);
                } else {
                    out.addProperty("callResult", r.toString());
                }
            }
        } catch (Exception e) {
            out.addProperty("error", e.getClass().getName() + ": " + e.getMessage());
        }
        return out;
    }
}
