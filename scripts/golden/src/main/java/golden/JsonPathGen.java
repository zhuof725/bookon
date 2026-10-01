package golden;

import com.jayway.jsonpath.JsonPath;
import com.jayway.jsonpath.ReadContext;

import java.util.ArrayList;
import java.util.List;

/**
 * JSONPath golden 生成器：用真实 Jayway JsonPath 2.10.0（默认 json-smart provider），
 * 走 Kotlin AnalyzeByJSonPath.getString/getStringList 的**单规则路径**逻辑（手工移植调度，
 * Jayway 为真实库）。本项目用例不含 && / || / %% / {$.} 组合规则（那属 RuleAnalyzer，
 * 已在第 2/3 步单测覆盖），因此这里只复刻单规则的 ctx.read + 结果格式化。
 *
 * Kotlin 单规则路径：
 *   getString:  try { val ob = ctx.read<Any>(rule);
 *                     result = if (ob is List<*>) ob.joinToString("\n") else ob.toString() }
 *               catch (e) { } ; return result (初值 "")
 *   getStringList: try { val obj = ctx.read<Any>(rule);
 *                        if (obj is List<*>) for (o in obj) result.add(o.toString())
 *                        else result.add(obj.toString()) }
 *                  catch (e) { } ; return result
 *
 * json-smart 的 toString()：对象 -> {"k":v,...}，数组 -> [..]，标量 -> 其字面量。
 */
public final class JsonPathGen {

    /** 返回 {getString, getStringList, threw}。threw=是否 Jayway 读取抛异常（Kotlin 吞掉）。 */
    public static Result run(String json, String rule) {
        Result r = new Result();
        if (rule.isEmpty()) {
            r.getString = null;
            r.getStringList = new ArrayList<>();
            return r;
        }
        ReadContext ctx = JsonPath.parse(json);

        // getString：初值为 ""（Kotlin: var result: String; 未赋初值则 innerRule 返回 ""）
        String gs = "";
        try {
            Object ob = ctx.read(rule);
            if (ob instanceof List) {
                gs = joinList((List<?>) ob, "\n");
            } else {
                gs = String.valueOf(ob); // null -> "null" (Kotlin ob.toString() 对 null 实际 NPE，但 Jayway definite 缺失会抛 PathNotFound 先行)
            }
        } catch (Exception e) {
            r.threw = true;
        }
        r.getString = gs;

        // getStringList
        List<String> list = new ArrayList<>();
        try {
            Object obj = ctx.read(rule);
            if (obj instanceof List) {
                for (Object o : (List<?>) obj) list.add(String.valueOf(o));
            } else {
                list.add(String.valueOf(obj));
            }
        } catch (Exception e) {
            // Kotlin catch 吞异常，result 保持空
        }
        r.getStringList = list;

        return r;
    }

    private static String joinList(List<?> list, String sep) {
        StringBuilder sb = new StringBuilder();
        for (int i = 0; i < list.size(); i++) {
            if (i > 0) sb.append(sep);
            sb.append(String.valueOf(list.get(i)));
        }
        return sb.toString();
    }

    public static final class Result {
        public String getString;
        public List<String> getStringList;
        public boolean threw;
    }
}
