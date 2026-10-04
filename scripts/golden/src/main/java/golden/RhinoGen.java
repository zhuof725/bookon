package golden;

import com.google.gson.JsonObject;
import org.mozilla.javascript.ConsString;
import org.mozilla.javascript.Context;
import org.mozilla.javascript.Scriptable;
import org.mozilla.javascript.ScriptableObject;
import org.mozilla.javascript.Undefined;
import org.mozilla.javascript.Wrapper;

import java.util.Locale;

/**
 * 真实 Rhino 1.8.1（非字符串模拟）。配置及拆箱复刻 legado modules/rhino 的
 * RhinoScriptEngine：VERSION_ES6 + interpretedMode；Wrapper -> unwrap，
 * ConsString -> String，Undefined -> null。AnalyzeRule.evalJS 直接返回 script.eval。
 * 下面严格分开 Kotlin getString 的最终 raw.toString() 和 makeUpRule {{}} 特例。
 */
public final class RhinoGen {
    private RhinoGen() {}

    private static Object unwrapReturnValue(Object result) {
        if (result instanceof Wrapper) result = ((Wrapper) result).unwrap();
        if (result instanceof ConsString) result = result.toString();
        return result instanceof Undefined ? null : result;
    }

    public static JsonObject run(JsonObject c) {
        JsonObject out = new JsonObject();
        String name = c.get("name").getAsString();
        String js = c.get("js").getAsString();
        out.addProperty("name", name);
        out.addProperty("js", js);
        if (c.has("result")) out.add("result", c.get("result"));
        try (Context cx = Context.enter()) {
            cx.setLanguageVersion(Context.VERSION_ES6);
            cx.setInterpretedMode(true);
            Scriptable scope = cx.initStandardObjects();
            Object binding = c.has("result") && !c.get("result").isJsonNull()
                    ? c.get("result").getAsString() : null;
            ScriptableObject.putProperty(scope, "result", binding);
            Object evaluated = cx.evaluateString(scope, js, name, 1, null);
            Object raw = unwrapReturnValue(evaluated);
            out.addProperty("evalType", evaluated == null ? "null" : evaluated.getClass().getName());
            out.addProperty("rawType", raw == null ? "null" : raw.getClass().getName());
            // NativeArray 没有稳定的 Java toString（Object identity hash 每次运行都不同）。
            // golden 对该类型记录稳定标记；Swift 测试把它作为已知不可逐字节对齐项，
            // 真正的 JS 内部数组字符串化由 String([..]) / join / JSON.stringify 用例验证。
            boolean unstableArray = raw instanceof org.mozilla.javascript.NativeArray;
            String getString = raw == null ? "" : (unstableArray ? "<NativeArray identity>" : raw.toString());
            String inlineString;
            if (raw == null) inlineString = "";
            else if (unstableArray) inlineString = "<NativeArray identity>";
            else if (raw instanceof String) inlineString = (String) raw;
            else if (raw instanceof Double && ((Double) raw) % 1.0 == 0.0)
                inlineString = String.format(Locale.ROOT, "%.0f", (Double) raw);
            else inlineString = raw.toString();
            out.addProperty("getString", getString);
            out.addProperty("inlineString", inlineString);
        } catch (Exception e) {
            out.addProperty("error", e.getClass().getName() + ": " + e.getMessage());
        }
        return out;
    }
}
