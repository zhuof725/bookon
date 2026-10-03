package golden;

import com.google.gson.Gson;
import com.google.gson.GsonBuilder;
import com.google.gson.JsonArray;
import com.google.gson.JsonElement;
import com.google.gson.JsonObject;
import com.google.gson.JsonParser;
import org.seimicrawler.xpath.JXNode;

import java.io.FileReader;
import java.io.FileWriter;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Paths;
import java.util.List;

/**
 * golden 对照数据生成器入口。
 * 读取 scripts/golden/cases/*.json（用例清单），用真实 jsoup 1.16.2 + JsoupXpath 2.5.3
 * 跑出每条 CSS / XPath 规则在对应 HTML 上的真实结果，写出到 golden/*.json 供 Swift 测试比对。
 *
 * 用法: java -jar golden-generator.jar <casesDir> <outDir>
 */
public class Main {

    public static void main(String[] args) throws Exception {
        if (args.length < 2) {
            System.err.println("用法: java -jar golden-generator.jar <casesDir> <outDir>");
            System.exit(1);
        }
        String casesDir = args[0];
        String outDir = args[1];
        Files.createDirectories(Paths.get(outDir));

        Gson gson = new GsonBuilder().disableHtmlEscaping().setPrettyPrinting().create();

        int totalCases = 0;
        int totalFiles = 0;

        try (var stream = Files.list(Paths.get(casesDir))) {
            for (var path : stream.sorted().toArray(java.nio.file.Path[]::new)) {
                if (!path.toString().endsWith(".json")) continue;
                totalFiles++;
                JsonObject input;
                try (FileReader r = new FileReader(path.toFile(), StandardCharsets.UTF_8)) {
                    input = JsonParser.parseReader(r).getAsJsonObject();
                }

                JsonObject htmls = input.getAsJsonObject("htmls");
                JsonObject output = new JsonObject();

                if (input.has("cssCases")) {
                    JsonArray outArr = new JsonArray();
                    for (JsonElement el : input.getAsJsonArray("cssCases")) {
                        JsonObject c = el.getAsJsonObject();
                        outArr.add(runCssCase(c, htmls));
                        totalCases++;
                    }
                    output.add("cssResults", outArr);
                }

                if (input.has("xpathCases")) {
                    JsonArray outArr = new JsonArray();
                    for (JsonElement el : input.getAsJsonArray("xpathCases")) {
                        JsonObject c = el.getAsJsonObject();
                        outArr.add(runXPathCase(c, htmls));
                        totalCases++;
                    }
                    output.add("xpathResults", outArr);
                }

                // ---- 第 4 步 C：工具函数 golden ----
                if (input.has("urlCases")) {
                    JsonArray outArr = new JsonArray();
                    for (JsonElement el : input.getAsJsonArray("urlCases")) {
                        outArr.add(runUrlCase(el.getAsJsonObject()));
                        totalCases++;
                    }
                    output.add("urlResults", outArr);
                }
                if (input.has("unescapeCases")) {
                    JsonArray outArr = new JsonArray();
                    for (JsonElement el : input.getAsJsonArray("unescapeCases")) {
                        outArr.add(runUnescapeCase(el.getAsJsonObject()));
                        totalCases++;
                    }
                    output.add("unescapeResults", outArr);
                }
                if (input.has("regexReplaceCases")) {
                    JsonArray outArr = new JsonArray();
                    for (JsonElement el : input.getAsJsonArray("regexReplaceCases")) {
                        outArr.add(runRegexReplaceCase(el.getAsJsonObject()));
                        totalCases++;
                    }
                    output.add("regexReplaceResults", outArr);
                }
                if (input.has("regexAnalyzeCases")) {
                    JsonArray outArr = new JsonArray();
                    for (JsonElement el : input.getAsJsonArray("regexAnalyzeCases")) {
                        outArr.add(runRegexAnalyzeCase(el.getAsJsonObject()));
                        totalCases++;
                    }
                    output.add("regexAnalyzeResults", outArr);
                }
                if (input.has("jsonPathCases")) {
                    JsonObject docs = input.getAsJsonObject("jsonDocs");
                    JsonArray outArr = new JsonArray();
                    for (JsonElement el : input.getAsJsonArray("jsonPathCases")) {
                        outArr.add(runJsonPathCase(el.getAsJsonObject(), docs));
                        totalCases++;
                    }
                    output.add("jsonPathResults", outArr);
                }
                // ---- 第 5 步：JsExtensions 纯算法 golden ----
                if (input.has("jsExtCases")) {
                    JsonArray outArr = new JsonArray();
                    for (JsonElement el : input.getAsJsonArray("jsExtCases")) {
                        outArr.add(JsExtGen.run(el.getAsJsonObject()));
                        totalCases++;
                    }
                    output.add("jsExtResults", outArr);
                    System.out.println("JsExtensions 纯算法: " + outArr.size() + " 条用例（真实 hutool/quick-transfer/Java 标准库）");
                }

                // ---- 第 5 步收尾：jsoup 替身 golden（真实 jsoup 1.16.2 + 真实 Rhino 1.8.1） ----
                if (input.has("jsoupCases")) {
                    JsonObject caseHtmls = input.getAsJsonObject("htmls");
                    JsonArray outArr = new JsonArray();
                    for (JsonElement el : input.getAsJsonArray("jsoupCases")) {
                        JsonObject c = el.getAsJsonObject().deepCopy();
                        String htmlKey = c.get("html").getAsString();
                        c.addProperty("html", caseHtmls.get(htmlKey).getAsString());
                        outArr.add(JsExtGen.runJsoup(c));
                        totalCases++;
                    }
                    output.add("jsoupResults", outArr);
                    System.out.println("jsoup 替身对照: " + outArr.size()
                            + " 条用例（同一 JS，真实 jsoup 1.16.2 + Rhino 1.8.1）");
                }

                // ---- 第 5 步收尾：JS number -> Java String 参数的真实 Rhino 转换 ----
                if (input.has("numberArgCases")) {
                    JsonArray outArr = new JsonArray();
                    for (JsonElement el : input.getAsJsonArray("numberArgCases")) {
                        outArr.add(NumberArgGen.run(el.getAsJsonObject()));
                        totalCases++;
                    }
                    output.add("numberArgResults", outArr);
                    System.out.println("Rhino 数字入参: " + outArr.size() + " 条（真实 Rhino 1.8.1 转换结果）");
                }

                // ---- 第 5 步收尾：Java MessageDigest 直算（端到端期望值） ----
                if (input.has("javaDigestCases")) {
                    JsonArray outArr = new JsonArray();
                    for (JsonElement el : input.getAsJsonArray("javaDigestCases")) {
                        outArr.add(JsExtGen.runJavaDigest(el.getAsJsonObject()));
                        totalCases++;
                    }
                    output.add("javaDigestResults", outArr);
                    System.out.println("Java MessageDigest: " + outArr.size() + " 条");
                }

                // ---- 第 6 步 6A：AnalyzeUrl 规则解析 / 编码 / UrlOption / Cookie ----
                if (input.has("codecCases")) {
                    JsonArray outArr = new JsonArray();
                    for (JsonElement el : input.getAsJsonArray("codecCases")) {
                        outArr.add(UrlRuleGen.runCodec(el.getAsJsonObject()));
                        totalCases++;
                    }
                    output.add("codecResults", outArr);
                    System.out.println("URL 编码: " + outArr.size() + " 条（真实 hutool/URLEncoder）");
                }
                if (input.has("urlOptionCases")) {
                    JsonArray outArr = new JsonArray();
                    for (JsonElement el : input.getAsJsonArray("urlOptionCases")) {
                        outArr.add(UrlRuleGen.runUrlOption(el.getAsJsonObject()));
                        totalCases++;
                    }
                    output.add("urlOptionResults", outArr);
                    System.out.println("UrlOption 解析: " + outArr.size() + " 条（真实 Gson + legado 定制适配器）");
                }
                if (input.has("analyzeUrlCases")) {
                    JsonArray outArr = new JsonArray();
                    for (JsonElement el : input.getAsJsonArray("analyzeUrlCases")) {
                        outArr.add(UrlRuleGen.runAnalyzeUrl(el.getAsJsonObject()));
                        totalCases++;
                    }
                    output.add("analyzeUrlResults", outArr);
                    System.out.println("AnalyzeUrl 规则解析: " + outArr.size() + " 条（手工移植调度 + 真实 Rhino）");
                }
                if (input.has("cookieCases")) {
                    JsonArray outArr = new JsonArray();
                    for (JsonElement el : input.getAsJsonArray("cookieCases")) {
                        outArr.add(UrlRuleGen.runCookie(el.getAsJsonObject()));
                        totalCases++;
                    }
                    output.add("cookieResults", outArr);
                    System.out.println("Cookie 纯函数: " + outArr.size() + " 条（手工移植 CookieStore/CookieManager）");
                }

                if (input.has("jsCases")) {
                    JsonArray outArr = new JsonArray();
                    for (JsonElement el : input.getAsJsonArray("jsCases")) {
                        outArr.add(RhinoGen.run(el.getAsJsonObject()));
                        totalCases++;
                    }
                    output.add("jsResults", outArr);
                    System.out.println("Rhino 1.8.1: " + outArr.size()
                            + " 条 JS 用例（getString + inline {{}}，保留 rawType/evalType）");
                }

                String outName = path.getFileName().toString();
                try (FileWriter w = new FileWriter(Paths.get(outDir, outName).toFile(), StandardCharsets.UTF_8)) {
                    gson.toJson(output, w);
                }
                System.out.println("生成: " + outName);
            }
        }

        System.out.println("完成：处理 " + totalFiles + " 个用例文件，共 " + totalCases + " 条用例。");
        if (totalCases == 0) {
            System.err.println("错误：没有生成任何用例结果！");
            System.exit(1);
        }
    }

    private static JsonObject runCssCase(JsonObject c, JsonObject htmls) {
        String name = c.get("name").getAsString();
        String htmlKey = c.get("html").getAsString();
        String rule = c.get("rule").getAsString();
        String html = htmls.get(htmlKey).getAsString();

        JsonObject out = new JsonObject();
        out.addProperty("name", name);
        out.addProperty("rule", rule);
        out.addProperty("htmlKey", htmlKey);
        // 直接把 HTML 内容也写进结果，避免 Swift 侧（尤其 iOS 模拟器沙盒环境）
        // 还要另外读取 scripts/golden/cases/*.json 输入文件（那不在 App Bundle 里）。
        out.addProperty("html", html);

        try {
            AnalyzeByJSoup j = new AnalyzeByJSoup(html);
            int elementsCount = j.getElements(rule).size();
            String getStringResult = j.getString(rule);
            List<String> getStringListResult = j.getStringList(rule);
            String getString0Result = j.getString0(rule);

            out.addProperty("elementsCount", elementsCount);
            out.add("getString", getStringResult == null ? null : new com.google.gson.JsonPrimitive(getStringResult));
            JsonArray arr = new JsonArray();
            for (String s : getStringListResult) arr.add(s);
            out.add("getStringList", arr);
            out.addProperty("getString0", getString0Result);
            out.addProperty("error", (String) null);
        } catch (Exception e) {
            out.addProperty("error", e.getClass().getSimpleName() + ": " + e.getMessage());
        }
        return out;
    }

    private static JsonObject runXPathCase(JsonObject c, JsonObject htmls) {
        String name = c.get("name").getAsString();
        String htmlKey = c.get("html").getAsString();
        String rule = c.get("rule").getAsString();
        String html = htmls.get(htmlKey).getAsString();

        JsonObject out = new JsonObject();
        out.addProperty("name", name);
        out.addProperty("rule", rule);
        out.addProperty("htmlKey", htmlKey);
        out.addProperty("html", html);

        try {
            AnalyzeByXPath x = new AnalyzeByXPath(html);
            List<JXNode> els = x.getElements(rule);
            String getStringResult = x.getString(rule);
            List<String> getStringListResult = x.getStringList(rule);

            out.addProperty("elementsCount", els == null ? -1 : els.size());
            out.add("getString", getStringResult == null ? null : new com.google.gson.JsonPrimitive(getStringResult));
            JsonArray arr = new JsonArray();
            for (String s : getStringListResult) arr.add(s);
            out.add("getStringList", arr);
            out.addProperty("error", (String) null);
        } catch (Exception e) {
            out.addProperty("error", e.getClass().getSimpleName() + ": " + e.getMessage());
        }
        return out;
    }

    // ============ 第 4 步 C：工具函数 golden runner ============

    private static JsonObject runUrlCase(JsonObject c) {
        JsonObject out = new JsonObject();
        out.addProperty("name", c.get("name").getAsString());
        String base = (c.has("base") && !c.get("base").isJsonNull()) ? c.get("base").getAsString() : null;
        String relative = c.get("relative").getAsString();
        out.add("base", base == null ? com.google.gson.JsonNull.INSTANCE : new com.google.gson.JsonPrimitive(base));
        out.addProperty("relative", relative);
        out.addProperty("result", UrlResolver.getAbsoluteURL(base, relative));
        return out;
    }

    private static JsonObject runUnescapeCase(JsonObject c) {
        JsonObject out = new JsonObject();
        out.addProperty("name", c.get("name").getAsString());
        String input = c.get("input").getAsString();
        out.addProperty("input", input);
        out.addProperty("result", UtilGen.unescapeHtml4(input));
        return out;
    }

    private static JsonObject runRegexReplaceCase(JsonObject c) {
        JsonObject out = new JsonObject();
        out.addProperty("name", c.get("name").getAsString());
        String input = c.get("input").getAsString();
        String regex = c.get("regex").getAsString();
        String replacement = c.get("replacement").getAsString();
        boolean replaceFirst = c.has("replaceFirst") && c.get("replaceFirst").getAsBoolean();
        out.addProperty("input", input);
        out.addProperty("regex", regex);
        out.addProperty("replacement", replacement);
        out.addProperty("replaceFirst", replaceFirst);
        out.addProperty("result", UtilGen.replaceRegex(input, regex, replacement, replaceFirst));
        return out;
    }

    private static JsonObject runRegexAnalyzeCase(JsonObject c) {
        JsonObject out = new JsonObject();
        out.addProperty("name", c.get("name").getAsString());
        String res = c.get("res").getAsString();
        JsonArray regsArr = c.getAsJsonArray("regs");
        String[] regs = new String[regsArr.size()];
        for (int i = 0; i < regs.length; i++) regs[i] = regsArr.get(i).getAsString();
        out.addProperty("res", res);
        out.add("regs", regsArr);
        // getElement（index=0）
        try {
            List<String> el = UtilGen.getElement(res, regs, 0);
            if (el == null) {
                out.add("getElement", com.google.gson.JsonNull.INSTANCE);
            } else {
                JsonArray a = new JsonArray();
                for (String s : el) a.add(s); // 可能含 null（Kotlin group(i)!! NPE 情形，这里保留 null 如实对照）
                out.add("getElement", a);
            }
            out.addProperty("getElementError", (String) null);
        } catch (Exception e) {
            out.add("getElement", com.google.gson.JsonNull.INSTANCE);
            out.addProperty("getElementError", e.getClass().getSimpleName());
        }
        // getElements
        try {
            List<List<String>> els = UtilGen.getElements(res, regs, 0);
            JsonArray a = new JsonArray();
            for (List<String> row : els) {
                JsonArray ra = new JsonArray();
                for (String s : row) ra.add(s);
                a.add(ra);
            }
            out.add("getElements", a);
            out.addProperty("getElementsError", (String) null);
        } catch (Exception e) {
            out.add("getElements", new JsonArray());
            out.addProperty("getElementsError", e.getClass().getSimpleName());
        }
        return out;
    }

    private static JsonObject runJsonPathCase(JsonObject c, JsonObject docs) {
        JsonObject out = new JsonObject();
        out.addProperty("name", c.get("name").getAsString());
        String docKey = c.get("doc").getAsString();
        String rule = c.get("rule").getAsString();
        String json = docs.get(docKey).getAsString();
        out.addProperty("rule", rule);
        out.addProperty("docKey", docKey);
        out.addProperty("json", json);
        try {
            JsonPathGen.Result r = JsonPathGen.run(json, rule);
            out.add("getString", r.getString == null ? com.google.gson.JsonNull.INSTANCE
                    : new com.google.gson.JsonPrimitive(r.getString));
            JsonArray a = new JsonArray();
            for (String s : r.getStringList) a.add(s);
            out.add("getStringList", a);
            out.addProperty("threw", r.threw);
            out.addProperty("error", (String) null);
        } catch (Exception e) {
            out.addProperty("error", e.getClass().getSimpleName() + ": " + e.getMessage());
        }
        return out;
    }
}
