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

        // 3e. 标准 UTF-8 解码（Unicode 最大子部分算法）供跨平台对照。
        //
        // 背景：Java 的 `new String(bytes, "UTF-8")` 对**连续非法字节**的替换字符数量与
        // Unicode 标准（以及 Swift `String(decoding:as:UTF8.self)`、Python `errors='replace'`）
        // 不一致。实测（240 份语料中的 18 份）Java 会把 `[0xC9,0xBD]` 这类序列中更早的字节
        // 判为非法而少插一个 U+FFFD，表现为「Java 的 FFFD 连续长度比标准短 1」。
        // 这是 JDK 的历史行为（`sun.nio.cs.UTF_8` 的 resync 逻辑），不是本移植的偏差。
        //
        // 因此额外输出一份「标准算法」的结果：Swift 侧与它比较，两者必须逐字符相等；
        // Java 原生结果的差异在 README 差异表中单列说明。
        o.addProperty("decodedExplicitUtf8Standard", truncate(standardUtf8Decode(s.bytes), 400));

        return o;
    }

    /**
     * Unicode 最大子部分（maximal subpart）算法的 UTF-8 容错解码。
     *
     * <p>与 Java 的 {@code new String(bytes, "UTF-8")} 的区别只在「连续非法字节产生几个
     * U+FFFD」：本实现每个「最长非法前缀」产生一个 U+FFFD，Java 有时会为同一段产生更少的
     * 替换字符。合法输入两者完全一致。
     *
     * <p>前 3 字节若为 UTF-8 BOM 先剥离（对齐 {@code EncodingDetectGolden.removeUTF8Bom}）。
     */
    private static String standardUtf8Decode(byte[] input) {
        byte[] bytes = EncodingDetectGolden.removeUTF8Bom(input);
        StringBuilder sb = new StringBuilder(bytes.length);
        int i = 0;
        final int n = bytes.length;
        while (i < n) {
            int b0 = bytes[i] & 0xFF;
            int need;
            int cp;
            int lowerBound;   // 该长度序列第二字节的合法下界（用于判定最大子部分）
            if (b0 < 0x80) { sb.append((char) b0); i++; continue; }
            else if (b0 >= 0xC2 && b0 <= 0xDF) { need = 1; cp = b0 & 0x1F; lowerBound = 0x80; }
            else if (b0 >= 0xE0 && b0 <= 0xEF) { need = 2; cp = b0 & 0x0F; lowerBound = 0x80; }
            else if (b0 >= 0xF0 && b0 <= 0xF4) { need = 3; cp = b0 & 0x07; lowerBound = 0x80; }
            else { sb.append('\uFFFD'); i++; continue; }

            int consumed = 1;
            boolean ok = true;
            for (int k = 1; k <= need; k++) {
                if (i + k >= n) { ok = false; break; }
                int bk = bytes[i + k] & 0xFF;
                if (bk < 0x80 || bk > 0xBF) { ok = false; break; }
                // 过长短编码（E0 80..9F、F0 80..8F、F4 90..BF）按最长子部分只吃首字节。
                if (k == 1) {
                    if (b0 == 0xE0 && bk < 0xA0) { ok = false; break; }
                    if (b0 == 0xED && bk > 0x9F) { ok = false; break; }
                    if (b0 == 0xF0 && bk < 0x90) { ok = false; break; }
                    if (b0 == 0xF4 && bk > 0x8F) { ok = false; break; }
                }
                cp = (cp << 6) | (bk & 0x3F);
                consumed++;
            }
            if (ok && consumed == need + 1) {
                if (Character.isSupplementaryCodePoint(cp)) {
                    sb.appendCodePoint(cp);
                } else {
                    sb.append((char) cp);
                }
                i += consumed;
            } else {
                // 非法：按「已消费的合法首/续字节」整体产生一个 U+FFFD（最大子部分）。
                sb.append('\uFFFD');
                i += Math.max(consumed, 1);
            }
        }
        return sb.toString();
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
