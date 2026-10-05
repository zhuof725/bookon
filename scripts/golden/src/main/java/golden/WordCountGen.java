package golden;

import com.google.gson.JsonObject;

import java.text.DecimalFormat;
import java.util.regex.Pattern;

/**
 * 第 7 步 A 段：StringUtils.wordCountFormat 的手工 Java 移植（golden 对照）。
 *
 * <p>源文件：{@code app/src/main/java/io/legado/app/utils/StringUtils.kt} 的
 * {@code fun wordCountFormat(words: Int)} 与 {@code fun wordCountFormat(wc: String?)}。
 * 逐行对照移植，唯一目的是产出期望值供 Swift 侧逐条比对。
 */
public final class WordCountGen {

    private WordCountGen() {}

    private static final DecimalFormat DF = new DecimalFormat("#.#");
    private static final Pattern NUMERIC = Pattern.compile("-?[0-9]+");

    /** 对应 Kotlin {@code fun isNumeric(str: String): Boolean}. */
    private static boolean isNumeric(String str) {
        return NUMERIC.matcher(str).matches();
    }

    /** 对应 Kotlin {@code fun wordCountFormat(words: Int): String}. */
    public static String wordCountFormat(int words) {
        String wordsS = "";
        if (words > 0) {
            if (words > 10000) {
                wordsS = DF.format(words * 1.0 / 10000.0) + "万字";
            } else {
                wordsS = words + "字";
            }
        }
        return wordsS;
    }

    /** 对应 Kotlin {@code fun wordCountFormat(wc: String?): String}. */
    public static String wordCountFormat(String wc) {
        if (wc == null) return "";
        String wordsS = "";
        if (isNumeric(wc)) {
            int words = Integer.parseInt(wc);
            wordsS = wordCountFormat(words);
        } else {
            wordsS = wc;
        }
        return wordsS;
    }

    /** golden runner：读 cases/word_count_cases.json 的单条用例，输出结果对象。 */
    public static JsonObject run(JsonObject c) {
        JsonObject out = new JsonObject();
        out.addProperty("name", c.get("name").getAsString());
        if (c.has("input") && !c.get("input").isJsonNull()) {
            String input = c.get("input").getAsString();
            out.addProperty("input", input);
            out.addProperty("result", wordCountFormat(input));
        } else {
            out.add("input", com.google.gson.JsonNull.INSTANCE);
            out.addProperty("result", wordCountFormat((String) null));
        }
        return out;
    }
}
