package golden;

import com.google.gson.JsonArray;
import com.google.gson.JsonObject;

import java.util.List;

/**
 * 字符集检测 golden 生成器（task 2b）。
 *
 * <p>对 {@link CharsetCorpus} 产出的每一份字节样本，用 <b>legado 自带的 icu4j 检测器源码</b>
 * （{@code app/src/main/java/io/legado/app/lib/icu4j/}，逐行复制到 {@code legadoicu} 包，
 * 仅去掉 Android 专有的 ParcelFileDescriptor 重载）配合 {@link EncodingDetectGolden}
 * （{@code EncodingDetect.kt} 的 Java 移植）产出：
 * <ul>
 *   <li>{@code detectName} / {@code detectConfidence}：{@code getEncode(bytes)}（detect() 的
 *       首选结果 + 置信度；无匹配时 name 为 Kotlin 兜底 "UTF-8"，confidence 为 -1）；</li>
 *   <li>{@code allMatches}：{@code detectAll()} 的完整有序候选（name + confidence）；</li>
 *   <li>{@code htmlEncode}：{@code getHtmlEncode(bytes)} 的结果（HTML meta → 检测器）；</li>
 *   <li>{@code decodedByHtmlEncode}：按 getHtmlEncode 结果完整解码出的文本（前 400 字符）；</li>
 *   <li>以及若干「显式 charset / Content-Type charset」组合下的完整解码结果，
 *       用于覆盖 Kotlin {@code ResponseBody.text(encode)} 的整条链。</li>
 * </ul>
 *
 * <p>输出直接写成 {@code outDir/charset_cases.json} 的 {@code charsetResults} 数组。
 * 用例数 = 语料库样本数（≥200）。
 */
final class CharsetGen {

    private CharsetGen() {}

    /** 生成的条目数（供 Main 累加 totalCases）。 */
    static int run(String outDir) throws Exception {
        List<CharsetCorpus.Sample> corpus = new CharsetCorpus().build();
        JsonArray arr = new JsonArray();
        for (CharsetCorpus.Sample s : corpus) {
            arr.add(runCase(s));
        }

        JsonObject root = new JsonObject();
        root.add("charsetResults", arr);

        java.nio.file.Path out = java.nio.file.Paths.get(outDir, "charset_cases.json");
        try (java.io.FileWriter w = new java.io.FileWriter(out.toFile(),
                java.nio.charset.StandardCharsets.UTF_8)) {
            new com.google.gson.GsonBuilder()
                    .disableHtmlEscaping().setPrettyPrinting().create()
                    .toJson(root, w);
        }

        int novelCount = 0;
        for (CharsetCorpus.Sample s : corpus) {
            if (s.syntheticNovelChapter) novelCount++;
        }
        System.out.println("字符集检测: " + arr.size() + " 条（真实 legado icu4j 检测器源码 + EncodingDetect 移植；"
                + "其中合成小说章节文本 " + novelCount + " 条）");
        return arr.size();
    }

    private static JsonObject runCase(CharsetCorpus.Sample s) {
        JsonObject o = new JsonObject();
        o.addProperty("name", s.name);
        o.addProperty("group", s.group);
        o.addProperty("note", s.note);
        o.addProperty("synthetic", s.synthetic);
        o.addProperty("syntheticNovelChapter", s.syntheticNovelChapter);
        o.addProperty("bytesBase64", CharsetCorpus.base64(s.bytes));
        o.addProperty("byteLength", s.bytes.length);

        // ---- 1) getEncode（detect 首选结果 + 置信度）----
        List<EncodingDetectGolden.MatchInfo> all = EncodingDetectGolden.detectAll(s.bytes);
        String detectName;
        int detectConfidence;
        if (all.isEmpty()) {
            // 与 Kotlin match?.name ?: "UTF-8" 一致
            detectName = "UTF-8";
            detectConfidence = -1;
        } else {
            detectName = all.get(0).name;
            detectConfidence = all.get(0).confidence;
        }
        o.addProperty("detectName", detectName);
        o.addProperty("detectConfidence", detectConfidence);
        o.addProperty("getEncode", EncodingDetectGolden.getEncode(s.bytes));

        JsonArray matches = new JsonArray();
        for (EncodingDetectGolden.MatchInfo m : all) {
            JsonObject mo = new JsonObject();
            mo.addProperty("name", m.name);
            mo.addProperty("confidence", m.confidence);
            matches.add(mo);
        }
        o.add("allMatches", matches);

        // ---- 2) getHtmlEncode（HTML meta → 检测器）----
        String htmlEncode;
        String htmlDecodeError = null;
        String decoded = null;
        try {
            htmlEncode = EncodingDetectGolden.getHtmlEncode(s.bytes);
            try {
                decoded = new String(s.bytes,
                        java.nio.charset.Charset.forName(htmlEncode));
            } catch (Exception e) {
                htmlDecodeError = e.getClass().getSimpleName() + ": " + e.getMessage();
            }
        } catch (Exception e) {
            htmlEncode = null;
            htmlDecodeError = e.getClass().getSimpleName() + ": " + e.getMessage();
        }
        o.addProperty("htmlEncode", htmlEncode);
        o.addProperty("htmlDecodeError", htmlDecodeError);
        o.addProperty("decodedByHtmlEncode", truncate(decoded, 400));

        // ---- 3) 完整解码链：BOM → explicit → Content-Type → getHtmlEncode ----
        // 3a. 无 explicit / 无 Content-Type（等价 ResponseBody.text(null) 且无头）
        addDecode(o, "decodedDefault", s.bytes, null, null);

        // 3b. 显式 charset（对应书源 UrlOption.charset）
        addDecode(o, "decodedExplicitUtf8", s.bytes, "UTF-8", null);
        addDecode(o, "decodedExplicitGbk", s.bytes, "GBK", null);
        addDecode(o, "decodedExplicitBig5", s.bytes, "Big5", null);
        addDecode(o, "decodedExplicitIso88591", s.bytes, "ISO-8859-1", null);

        // 3c. Content-Type charset 优先于检测器
        addDecode(o, "decodedContentTypeUtf8", s.bytes, null, "text/html; charset=UTF-8");
        addDecode(o, "decodedContentTypeGbk", s.bytes, null, "text/html; charset=gbk");
        addDecode(o, "decodedContentTypeQuoted", s.bytes, null, "text/html; charset=\"UTF-8\"");
        addDecode(o, "decodedContentTypeNoCharset", s.bytes, null, "text/html");
        // 3d. 显式 charset 优先于 Content-Type
        addDecode(o, "decodedExplicitBeatsHeader", s.bytes, "GBK", "text/html; charset=UTF-8");

        return o;
    }

    /** 跑一次完整解码链，把结果（或异常）写进 o[key] / o[key+"Error"]。 */
    private static void addDecode(JsonObject o, String key, byte[] bytes,
                                  String explicit, String contentType) {
        try {
            String v = EncodingDetectGolden.decodeBody(bytes, explicit, contentType);
            o.addProperty(key, truncate(v, 400));
            o.addProperty(key + "Error", (String) null);
        } catch (Exception e) {
            o.addProperty(key, (String) null);
            o.addProperty(key + "Error", e.getClass().getSimpleName() + ": " + e.getMessage());
        }
    }

    private static String truncate(String s, int max) {
        if (s == null) return null;
        return s.length() <= max ? s : s.substring(0, max);
    }
}
