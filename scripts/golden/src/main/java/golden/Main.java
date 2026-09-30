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
}
