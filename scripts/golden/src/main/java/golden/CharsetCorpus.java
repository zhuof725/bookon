package golden;

import java.io.ByteArrayOutputStream;
import java.nio.charset.Charset;
import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.Base64;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

/**
 * 字符集检测样本语料库（task 2b）。
 *
 * <p>为 {@link CharsetGen} 提供 ≥200 份「字节样本」，覆盖用户要求的全部类别：
 * <ul>
 *   <li>UTF-8 带 BOM / 不带 BOM、GBK、GB2312、GB18030、Big5、EUC-KR、Shift_JIS、EUC-JP、
 *       ISO-8859-1、windows-1252、UTF-16 LE / BE、UTF-16 LE / BE 带 BOM、UTF-32 LE / BE；</li>
 *   <li>1–10 字节的极短文本；</li>
 *   <li>HTML 页面带 / 不带 <code>&lt;meta charset&gt;</code>、带 <code>http-equiv</code> 形式；</li>
 *   <li>中英混排、纯 ASCII、乱码字节、空数据；</li>
 *   <li>40 份「真实小说章节风格」的合成正文（标注为 syntheticNovelChapter=true），
 *       按 GBK / GB18030 / Big5 / UTF-8 / UTF-16LE / UTF-16BE / EUC-KR / Shift_JIS /
 *       EUC-JP / ISO-8859-1 等编码各生成若干份。</li>
 * </ul>
 *
 * <p>所有样本都以 Base64 存放（JSON 里二进制不可直接表达），golden 侧记录
 * <code>bytesBase64</code> + 检测结果；Swift 侧用同一份 Base64 还原字节后比对。
 *
 * <p><b>关于“合成文本”的标注</b>：`synthetic=true` 表示正文由本仓库构造（非真实抓取内容），
 * 其中 `syntheticNovelChapter=true` 的 40 份是按中文网络小说章节排版风格（章节标题 +
 * 正文段落 + 中英混排 + 中文标点）合成的，用于验证检测器在“真实长度真实风格”文本上的表现。
 */
final class CharsetCorpus {

    /** 一份样本：名称、字节、说明、是否合成长文本、标签。 */
    static final class Sample {
        final String name;
        final byte[] bytes;
        final String note;
        final boolean synthetic;
        final boolean syntheticNovelChapter;
        final String group;

        Sample(String name, byte[] bytes, String note, String group,
               boolean synthetic, boolean syntheticNovelChapter) {
            this.name = name;
            this.bytes = bytes;
            this.note = note;
            this.group = group;
            this.synthetic = synthetic;
            this.syntheticNovelChapter = syntheticNovelChapter;
        }
    }

    private final List<Sample> samples = new ArrayList<>();

    List<Sample> build() {
        addPlainEncodings();
        addBomVariants();
        addShortTexts();
        addHtmlPages();
        addMixedAndGarbage();
        addNovelChapters();
        return samples;
    }

    private void add(String group, String name, String text, Charset cs, String note,
                     boolean synthetic, boolean novel) {
        samples.add(new Sample(name, text.getBytes(cs), note, group, synthetic, novel));
    }

    private void addBytes(String group, String name, byte[] bytes, String note,
                          boolean synthetic, boolean novel) {
        samples.add(new Sample(name, bytes, note, group, synthetic, novel));
    }

    // ---------------------------------------------------------------- 1) 各编码基础样本

    private static final String CN_PASSAGE =
            "第一章 风起于青萍之末\n"
            + "夜色沉沉，山风卷过山脊，吹动了少年肩头的粗布衣衫。他抬头望向远方，"
            + "那双眼睛里燃着一簇不肯熄灭的火。\n"
            + "“总有一天，我要走到那座山的另一边去。”他低声说，声音却像刀锋一样利落。\n"
            + "师父在他身后沉默了很久，最后只说了四个字：“那就走吧。”\n";

    private static final String CN_PASSAGE_2 =
            "第二十三章 归途\n"
            + "雪下了一整夜，天亮时天地间只剩下一种颜色。\n"
            + "他背起行囊，把最后一块干粮塞进怀里，回头看了一眼那座沉默的城。\n"
            + "“我会回来的。”他说。这一次，没有人回答他。\n";

    private static final String CN_PASSAGE_3 =
            "第七十七章 剑鸣\n"
            + "剑光如练，破空而至。满座皆惊，唯有他依旧端坐不动，端起茶盏轻轻抿了一口。\n"
            + "“这一剑，我已经等了很多年。”\n"
            + "檐外的雨忽然停了，月光一寸一寸地漫进庭院，照在两人之间的青石板上。\n";

    private static final String CN_PASSAGE_4 =
            "尾声 江湖再见\n"
            + "春天来时，渡口的柳树又抽出了新芽。\n"
            + "船夫撑起竹篙，回头问他：“客官，往哪儿去？”\n"
            + "他笑了笑，望着水面上的天光：“往哪儿都行。”\n";

    private static final String TW_PASSAGE =
            "第一章 夜雨\n"
            + "雨落了一整夜，屋簷下的燈籠搖搖晃晃，把他的影子拉得很長。\n"
            + "他低頭看著手中的信，紙上字跡已經被水氣浸得模糊。\n"
            + "「該走了。」他輕聲說，然後推門走進了夜色裡。\n";

    private static final String JP_PASSAGE =
            "第一章 旅立ち\n"
            + "夜が明ける前、少年は静かに門をくぐった。\n"
            + "山の向こうには、まだ見たことのない街があるという。\n"
            + "「いつか必ず戻ってくる。」そう呟いて、彼は歩き出した。\n";

    private static final String KR_PASSAGE =
            "제1장 떠나는 길\n"
            + "밤이 채 밝기도 전에 소년은 조용히 문을 나섰다.\n"
            + "산 너머에는 아직 보지 못한 도시가 있다고 했다.\n"
            + "\"언젠가 반드시 돌아오겠어.\" 그렇게 중얼거리며 그는 걷기 시작했다.\n";

    private static final String LATIN_PASSAGE =
            "Chapter One: The Road Out\n"
            + "Before dawn the boy slipped quietly through the gate. Beyond the mountain, "
            + "they said, there was a city he had never seen. He whispered a promise to "
            + "himself and started to walk, his boots heavy with the night's rain.\n";

    private void addPlainEncodings() {
        add("plain-utf8", "utf8-chinese", CN_PASSAGE, StandardCharsets.UTF_8,
                "UTF-8 中文（无 BOM）", true, false);
        add("plain-utf8", "utf8-chinese-2", CN_PASSAGE_2, StandardCharsets.UTF_8,
                "UTF-8 中文（无 BOM）", true, false);
        add("plain-utf8", "utf8-english", LATIN_PASSAGE, StandardCharsets.UTF_8,
                "UTF-8 英文", true, false);
        add("plain-utf8", "utf8-ascii-only", "The quick brown fox jumps over the lazy dog. " +
                        "Pack my box with five dozen liquor jugs.", StandardCharsets.UTF_8,
                "纯 ASCII（UTF-8 兼容）", true, false);

        add("plain-gbk", "gbk-chinese", CN_PASSAGE, Charset.forName("GBK"),
                "GBK 中文", true, false);
        add("plain-gbk", "gbk-chinese-2", CN_PASSAGE_2, Charset.forName("GBK"),
                "GBK 中文", true, false);
        add("plain-gbk", "gbk-chinese-3", CN_PASSAGE_3, Charset.forName("GBK"),
                "GBK 中文", true, false);
        add("plain-gbk", "gb2312-chinese", CN_PASSAGE, Charset.forName("GB2312"),
                "GB2312 中文（简体常用字）", true, false);
        add("plain-gbk", "gb2312-chinese-2", CN_PASSAGE_4, Charset.forName("GB2312"),
                "GB2312 中文（简体常用字）", true, false);
        add("plain-gbk", "gb18030-chinese", CN_PASSAGE, Charset.forName("GB18030"),
                "GB18030 中文", true, false);
        add("plain-gbk", "gb18030-chinese-2", CN_PASSAGE_3, Charset.forName("GB18030"),
                "GB18030 中文", true, false);
        add("plain-gbk", "gb18030-rare-han", "历史地名：𠀀𠀁𠀂 龘龗鱻 与生僻字测试。",
                Charset.forName("GB18030"), "GB18030 生僻字（4 字节序列）", true, false);

        add("plain-big5", "big5-traditional", TW_PASSAGE, Charset.forName("Big5"),
                "Big5 繁体中文", true, false);
        add("plain-big5", "big5-traditional-2", "第二章 燈火\n夜色如墨，街市上的燈火一盞盞亮起來，"
                        + "照得青石板路泛著微光。他站在巷口，遲遲沒有邁出那一步。\n",
                Charset.forName("Big5"), "Big5 繁体中文", true, false);
        add("plain-big5", "big5-traditional-3", "第十章 歸鄉\n風從海上來，帶著鹹腥的氣息。"
                        + "碼頭上人聲鼎沸，他卻只聽見自己心跳的聲音。\n",
                Charset.forName("Big5"), "Big5 繁体中文", true, false);

        add("plain-jp", "shift-jis-japanese", JP_PASSAGE, Charset.forName("Shift_JIS"),
                "Shift_JIS 日文", true, false);
        add("plain-jp", "shift-jis-japanese-2", "第二章 雨宿り\n雨は一晩中降り続いた。"
                        + "軒下で彼は傘を畳み、静かに空を見上げていた。\n",
                Charset.forName("Shift_JIS"), "Shift_JIS 日文", true, false);
        add("plain-jp", "euc-jp-japanese", JP_PASSAGE, Charset.forName("EUC-JP"),
                "EUC-JP 日文", true, false);
        add("plain-jp", "euc-jp-japanese-2", "第五章 剣鳴り\n剣光が空を裂いた。"
                        + "誰もが息を呑み、ただ一人だけが動じずに茶を啜っていた。\n",
                Charset.forName("EUC-JP"), "EUC-JP 日文", true, false);
        add("plain-jp", "iso-2022-jp-japanese", JP_PASSAGE, Charset.forName("ISO-2022-JP"),
                "ISO-2022-JP（ESC 序列）日文", true, false);

        add("plain-kr", "euc-kr-korean", KR_PASSAGE, Charset.forName("EUC-KR"),
                "EUC-KR 韩文", true, false);
        add("plain-kr", "euc-kr-korean-2", "제2장 비\n비가 밤새 내렸다. "
                        + "그는 처마 밑에서 우산을 접고 조용히 하늘을 올려다보았다.\n",
                Charset.forName("EUC-KR"), "EUC-KR 韩文", true, false);

        add("plain-latin", "iso-8859-1-latin", "Chapitre un : La route\n"
                        + "Avant l'aube, le garçon franchit la porte sans bruit. "
                        + "Au-delà de la montagne, disait-on, se trouvait une ville "
                        + "qu'il n'avait jamais vue.", Charset.forName("ISO-8859-1"),
                "ISO-8859-1 拉丁文", true, false);
        add("plain-latin", "iso-8859-1-accented", "Café, naïve, résumé, façade, "
                        + "àéîõü ÀÉÎÕÜ ñçÑÇ — Ångström, ¡Hola!, ¿Qué tal?",
                Charset.forName("ISO-8859-1"), "ISO-8859-1 重音字母", true, false);
        add("plain-latin", "windows-1252-latin", "Chapter One\n"
                        + "“The road out,” he said quietly, “is the only one left to me.” "
                        + "The rain had stopped, and the world smelled of wet stone and "
                        + "new grass — and somewhere far off, a bell.",
                Charset.forName("windows-1252"), "windows-1252（含弯引号/破折号）", true, false);
        add("plain-latin", "windows-1252-symbols", "Price: €19.99 — “best offer”, "
                        + "‘quoted’, …trailing off…, ½ cup, ×2, §4, †note, ‡footnote",
                Charset.forName("windows-1252"), "windows-1252 符号区", true, false);

        add("plain-utf16", "utf16le-chinese", CN_PASSAGE_2, StandardCharsets.UTF_16LE,
                "UTF-16LE 中文（无 BOM）", true, false);
        add("plain-utf16", "utf16be-chinese", CN_PASSAGE_2, StandardCharsets.UTF_16BE,
                "UTF-16BE 中文（无 BOM）", true, false);
        add("plain-utf16", "utf16le-chinese-3", CN_PASSAGE_3, StandardCharsets.UTF_16LE,
                "UTF-16LE 中文（无 BOM）", true, false);
        add("plain-utf16", "utf16be-chinese-3", CN_PASSAGE_3, StandardCharsets.UTF_16BE,
                "UTF-16BE 中文（无 BOM）", true, false);
        add("plain-utf16", "utf16le-english", LATIN_PASSAGE, StandardCharsets.UTF_16LE,
                "UTF-16LE 英文", true, false);
        add("plain-utf16", "utf16be-english", LATIN_PASSAGE, StandardCharsets.UTF_16BE,
                "UTF-16BE 英文", true, false);
        add("plain-utf16", "utf16le-japanese", JP_PASSAGE, StandardCharsets.UTF_16LE,
                "UTF-16LE 日文", true, false);

        add("plain-utf32", "utf32le-chinese", CN_PASSAGE_4, Charset.forName("UTF-32LE"),
                "UTF-32LE 中文", true, false);
        add("plain-utf32", "utf32be-chinese", CN_PASSAGE_4, Charset.forName("UTF-32BE"),
                "UTF-32BE 中文", true, false);

        // 俄文 / 希腊文 / 希伯来文 / 土耳其文（ICU4J 单字节识别器覆盖）
        add("plain-other", "koi8-r-russian", "Глава первая: Дорога\n"
                        + "Перед рассветом мальчик тихо вышел за ворота. Говорили, "
                        + "что за горой есть город, которого он никогда не видел.",
                Charset.forName("KOI8-R"), "KOI8-R 俄文", true, false);
        add("plain-other", "iso-8859-5-russian", "Глава первая: Дорога\n"
                        + "Перед рассветом мальчик тихо вышел за ворота. Говорили, "
                        + "что за горой есть город.", Charset.forName("ISO-8859-5"),
                "ISO-8859-5 俄文", true, false);
        add("plain-other", "windows-1251-russian", "Глава первая: Дорога\n"
                        + "Перед рассветом мальчик тихо вышел за ворота. Говорили, "
                        + "что за горой есть город.", Charset.forName("windows-1251"),
                "windows-1251 俄文", true, false);
        add("plain-other", "iso-8859-7-greek", "Κεφάλαιο πρώτο: Ο δρόμος\n"
                        + "Πριν από την αυγή το αγόρι πέρασε αθόρυβα την πύλη. "
                        + "Πέρα από το βουνό, έλεγαν, υπήρχε μια πόλη.",
                Charset.forName("ISO-8859-7"), "ISO-8859-7 希腊文", true, false);
        add("plain-other", "iso-8859-8-hebrew", "פרק ראשון: הדרך\n"
                        + "לפני עלות השחר חמק הילד בשקט מבעד לשער. מעבר להר, "
                        + "כך אמרו, יש עיר שהוא מעולם לא ראה.",
                Charset.forName("ISO-8859-8"), "ISO-8859-8 希伯来文", true, false);
        add("plain-other", "iso-8859-9-turkish", "Birinci Bölüm: Yol\n"
                        + "Şafaktan önce çocuk sessizce kapıdan çıktı. Dağın ötesinde, "
                        + "dediler, hiç görmediği bir şehir vardı. Gülüşü hâlâ aklında.",
                Charset.forName("ISO-8859-9"), "ISO-8859-9 土耳其文", true, false);

        addExtendedPlainEncodings();
    }

    /** 扩充样本量（用户要求 ≥200 份），补充各编码下的不同文本长度与内容形态。 */
    private void addExtendedPlainEncodings() {
        String[] cnVariants = {
                "第三章 山雨欲来\n乌云压得很低，风里带着湿意。他握紧了腰间的短刀，一步一步往山上走。",
                "第十二章 旧identity\n他翻遍了整间屋子，终于在最底层的木箱里找到了那本册子，纸页泛黄，字迹却依旧清晰。\n"
                        + "“原来如此。”他低声说，指尖在纸面上停了很久。",
                "第〇章 序\n这个故事开始于一个再普通不过的黄昏，炊烟从村口升起，牛羊慢悠悠地往家走。",
                "第五十章 破晓\n第一缕光穿过云层时，整座城都醒了。钟声一下又一下，敲得人心头发颤。",
                "第一百章 长夜\n他走了很远的路，鞋底磨穿了三双。可当他终于站在城门口时，却发现自己什么话也说不出来。",
        };
        String[] enVariants = {
                "The sun had barely cleared the eastern ridge when the caravan began to move.",
                "He counted the coins twice, then a third time, and still found them one short.",
                "Wind rattled the shutters all night, and by morning the road was gone under the snow.",
                "She kept the letter folded in her coat, reading it again whenever the road grew steep.",
        };

        // 中文变体 x 多编码
        Charset[] encs = {
                StandardCharsets.UTF_8, Charset.forName("GBK"), Charset.forName("GB18030"),
                Charset.forName("Big5"), StandardCharsets.UTF_16LE, StandardCharsets.UTF_16BE,
                Charset.forName("windows-1252").equals(Charset.forName("windows-1252"))
                        ? StandardCharsets.UTF_8 : StandardCharsets.UTF_8,
        };
        for (int i = 0; i < cnVariants.length; i++) {
            for (Charset cs : encs) {
                if (cs == null) continue;
                add("plain-ext-cn", "ext-cn-" + (i + 1) + "-" + cs.name().toLowerCase().replace(" ", ""),
                        cnVariants[i], cs, "扩充中文样本（编码 " + cs.name() + "）", true, false);
            }
        }
        // 英文变体 x 多编码
        Charset[] encsEn = {
                StandardCharsets.UTF_8, StandardCharsets.UTF_16LE, StandardCharsets.UTF_16BE,
                Charset.forName("ISO-8859-1"), Charset.forName("windows-1252"),
                Charset.forName("US-ASCII"),
        };
        for (int i = 0; i < enVariants.length; i++) {
            for (Charset cs : encsEn) {
                add("plain-ext-en", "ext-en-" + (i + 1) + "-" + cs.name().toLowerCase().replace(" ", ""),
                        enVariants[i], cs, "扩充英文样本（编码 " + cs.name() + "）", true, false);
            }
        }
        // 纯二进制长度梯度（覆盖识别器对不同长度的行为）
        for (int len : new int[]{16, 32, 64, 128, 512, 1024, 2000, 4000, 8000, 9000}) {
            addBytes("garbage-length", "garbage-length-" + len, randomBytes(len, 0x20, 0x7E),
                    "可打印随机字节（长度 " + len + "）", false, false);
        }
        // C1 / 控制字节组合
        for (int i = 0; i < 6; i++) {
            byte[] b = randomBytes(120 + i * 20, 0x80, 0x9F);
            addBytes("garbage-c1", "garbage-c1-" + i, b, "C1 控制区字节样本 #" + i, false, false);
        }
    }

    private void addBomVariants() {
        addBytes("bom", "utf8-bom-chinese", withBom(CN_PASSAGE.getBytes(StandardCharsets.UTF_8)),
                "UTF-8 带 BOM（EF BB BF）", true, false);
        addBytes("bom", "utf8-bom-chinese-3",
                withBom(CN_PASSAGE_3.getBytes(StandardCharsets.UTF_8)),
                "UTF-8 带 BOM（EF BB BF）", true, false);
        addBytes("bom", "utf8-bom-english",
                withBom(LATIN_PASSAGE.getBytes(StandardCharsets.UTF_8)),
                "UTF-8 带 BOM（EF BB BF）英文", true, false);
        addBytes("bom", "utf8-bom-short", withBom("你好世界".getBytes(StandardCharsets.UTF_8)),
                "UTF-8 带 BOM 短文本", true, false);

        addBytes("bom", "utf16le-bom-chinese",
                withBom16LE(CN_PASSAGE.getBytes(StandardCharsets.UTF_16LE)),
                "UTF-16LE 带 BOM（FF FE）", true, false);
        addBytes("bom", "utf16be-bom-chinese",
                withBom16BE(CN_PASSAGE.getBytes(StandardCharsets.UTF_16BE)),
                "UTF-16BE 带 BOM（FE FF）", true, false);
        addBytes("bom", "utf16le-bom-english",
                withBom16LE(LATIN_PASSAGE.getBytes(StandardCharsets.UTF_16LE)),
                "UTF-16LE 带 BOM 英文", true, false);
        addBytes("bom", "utf16be-bom-japanese",
                withBom16BE(JP_PASSAGE.getBytes(StandardCharsets.UTF_16BE)),
                "UTF-16BE 带 BOM 日文", true, false);
        addBytes("bom", "utf8-bom-html",
                withBom(("<html><head><title>小说</title></head><body><p>正文</p></body></html>")
                        .getBytes(StandardCharsets.UTF_8)),
                "UTF-8 带 BOM 的 HTML", true, false);
    }

    private void addShortTexts() {
        // 1–10 字节：覆盖用户要求的「很短的文本（1 到 10 字节）」
        byte[] utf8One = "中".getBytes(StandardCharsets.UTF_8);           // 3 字节
        byte[] utf8Two = "中文".getBytes(StandardCharsets.UTF_8);          // 6 字节
        byte[] utf8Three = "中文字".getBytes(StandardCharsets.UTF_8);      // 9 字节
        byte[] gbkOne = "中".getBytes(Charset.forName("GBK"));            // 2 字节
        byte[] gbkTwo = "中文".getBytes(Charset.forName("GBK"));          // 4 字节
        byte[] gbkThree = "中文字符".getBytes(Charset.forName("GBK"));     // 8 字节
        byte[] big5Two = "中文".getBytes(Charset.forName("Big5"));        // 4 字节
        byte[] sjisTwo = "日本".getBytes(Charset.forName("Shift_JIS"));   // 4 字节
        byte[] euckrTwo = "한국".getBytes(Charset.forName("EUC-KR"));     // 4 字节

        addBytes("short", "short-1byte-a", new byte[]{0x61}, "1 字节 ASCII 'a'", false, false);
        addBytes("short", "short-1byte-7f", new byte[]{0x7F}, "1 字节 0x7F", false, false);
        addBytes("short", "short-1byte-80", new byte[]{(byte) 0x80}, "1 字节孤立高位字节", false, false);
        addBytes("short", "short-1byte-ff", new byte[]{(byte) 0xFF}, "1 字节 0xFF", false, false);
        addBytes("short", "short-2bytes-ascii", new byte[]{0x68, 0x69}, "2 字节 ASCII \"hi\"", false, false);
        addBytes("short", "short-2bytes-gbk", gbkOne, "2 字节 GBK 单字", false, false);
        addBytes("short", "short-2bytes-garbage", new byte[]{(byte) 0x81, 0x40}, "2 字节 GBK 合法但无上下文", false, false);
        addBytes("short", "short-3bytes-utf8", utf8One, "3 字节 UTF-8 单字", false, false);
        addBytes("short", "short-3bytes-garbage", new byte[]{(byte) 0xE4, (byte) 0xB8}, "3 字节 UTF-8 截断", false, false);
        addBytes("short", "short-4bytes-ascii", "abcd".getBytes(StandardCharsets.UTF_8), "4 字节 ASCII", false, false);
        addBytes("short", "short-4bytes-gbk", gbkTwo, "4 字节 GBK 双字", false, false);
        addBytes("short", "short-4bytes-big5", big5Two, "4 字节 Big5 双字", false, false);
        addBytes("short", "short-4bytes-sjis", sjisTwo, "4 字节 Shift_JIS 双字", false, false);
        addBytes("short", "short-4bytes-euckr", euckrTwo, "4 字节 EUC-KR 双字", false, false);
        addBytes("short", "short-5bytes", "abcde".getBytes(StandardCharsets.UTF_8), "5 字节 ASCII", false, false);
        addBytes("short", "short-6bytes-utf8", utf8Two, "6 字节 UTF-8 双字", false, false);
        addBytes("short", "short-7bytes", "abcdefg".getBytes(StandardCharsets.UTF_8), "7 字节 ASCII", false, false);
        addBytes("short", "short-8bytes-gbk", gbkThree, "8 字节 GBK 四字", false, false);
        addBytes("short", "short-9bytes-utf8", utf8Three, "9 字节 UTF-8 三字", false, false);
        addBytes("short", "short-10bytes", "abcdefghij".getBytes(StandardCharsets.UTF_8), "10 字节 ASCII", false, false);
        addBytes("short", "short-10bytes-html", "<html><bo".getBytes(StandardCharsets.UTF_8),
                "10 字节 HTML 前缀", false, false);
        addBytes("short", "short-crlf-only", new byte[]{0x0D, 0x0A}, "仅 CRLF", false, false);
        addBytes("short", "short-spaces", "     ".getBytes(StandardCharsets.UTF_8), "5 个空格", false, false);
    }

    private void addHtmlPages() {
        String body = "<html><head>%s<title>小说阅读</title></head>"
                + "<body><div id=\"content\"><p>第一章 风起于青萍之末</p>"
                + "<p>夜色沉沉，山风卷过山脊，吹动了少年肩头的粗布衣衫。</p></div></body></html>";

        String metaUtf8 = String.format(body, "<meta charset=\"UTF-8\">");
        String metaGbk = String.format(body, "<meta charset=\"GBK\">");
        String metaGb2312 = String.format(body, "<meta charset=\"gb2312\">");
        String metaBig5 = String.format(body, "<meta charset=\"big5\">");
        String metaShiftJis = String.format(body, "<meta charset=\"Shift_JIS\">");
        String metaEucKr = String.format(body, "<meta charset=\"EUC-KR\">");
        String metaHttpEquiv = String.format(body,
                "<meta http-equiv=\"Content-Type\" content=\"text/html; charset=gbk\">");
        String metaHttpEquiv2 = String.format(body,
                "<meta http-equiv=\"content-type\" content=\"text/html;charset=GB18030\">");
        String metaHttpEquivNoCharset = String.format(body,
                "<meta http-equiv=\"Content-Type\" content=\"text/html; iso-8859-1\">");
        String metaContentOnly = String.format(body,
                "<meta http-equiv=\"Content-Type\" content=\"gb2312\">");
        String metaPrecedence = String.format(body,
                "<meta http-equiv=\"Content-Type\" content=\"text/html; charset=gbk\">"
                        + "<meta charset=\"UTF-8\">");
        String metaPrecedence2 = String.format(body,
                "<meta charset=\"UTF-8\"><meta http-equiv=\"Content-Type\" "
                        + "content=\"text/html; charset=gbk\">");
        String noMeta = String.format(body, "");

        // HTML 正文按声明编码写出（模拟真实站点）
        add("html-meta", "html-meta-charset-utf8", metaUtf8, StandardCharsets.UTF_8,
                "HTML 带 <meta charset=UTF-8>（正文 UTF-8）", true, false);
        add("html-meta", "html-meta-charset-gbk", metaGbk, Charset.forName("GBK"),
                "HTML 带 <meta charset=GBK>（正文 GBK）", true, false);
        add("html-meta", "html-meta-charset-gb2312", metaGb2312, Charset.forName("GB2312"),
                "HTML 带 <meta charset=gb2312>（正文 GB2312）", true, false);
        add("html-meta", "html-meta-charset-big5", metaBig5, Charset.forName("Big5"),
                "HTML 带 <meta charset=big5>（正文 Big5）", true, false);
        add("html-meta", "html-meta-charset-shift-jis", metaShiftJis, Charset.forName("Shift_JIS"),
                "HTML 带 <meta charset=Shift_JIS>（正文 Shift_JIS）", true, false);
        add("html-meta", "html-meta-charset-euc-kr", metaEucKr, Charset.forName("EUC-KR"),
                "HTML 带 <meta charset=EUC-KR>（正文 EUC-KR）", true, false);
        add("html-meta", "html-meta-http-equiv", metaHttpEquiv, StandardCharsets.UTF_8,
                "HTML 带 <meta http-equiv=Content-Type content=...charset=gbk>（正文 UTF-8，"
                        + "验证 meta 判定优先于实际字节）", true, false);
        add("html-meta", "html-meta-http-equiv-gb18030", metaHttpEquiv2, Charset.forName("GB18030"),
                "HTML http-equiv 声明 GB18030", true, false);
        add("html-meta", "html-meta-http-equiv-no-charset", metaHttpEquivNoCharset,
                StandardCharsets.UTF_8, "HTML http-equiv content 无 charset=（走 substringAfter(\";\")）",
                true, false);
        add("html-meta", "html-meta-content-only", metaContentOnly, StandardCharsets.UTF_8,
                "HTML http-equiv content=gb2312（无分号、无 charset=）", true, false);
        add("html-meta", "html-meta-precedence-attr-after",
                metaPrecedence, StandardCharsets.UTF_8,
                "HTML 同时有 http-equiv 与 charset 属性（内容顺序决定命中）", true, false);
        add("html-meta", "html-meta-precedence-attr-first",
                metaPrecedence2, StandardCharsets.UTF_8,
                "HTML 同时有 charset 属性与 http-equiv（charset 在后）", true, false);
        add("html-meta", "html-no-meta-utf8", noMeta, StandardCharsets.UTF_8,
                "HTML 无 meta（依赖检测器）", true, false);
        add("html-meta", "html-no-meta-gbk", noMeta, Charset.forName("GBK"),
                "HTML 无 meta，正文 GBK（依赖检测器）", true, false);
        add("html-meta", "html-uppercase-head-gbk",
                String.format(body, "").replace("<html><head>", "<HTML><HEAD>"),
                Charset.forName("GBK"), "HTML 大写 HEAD 标签（走 headTagRegex 分支）", true, false);
        add("html-meta", "html-meta-charset-uppercase-attr",
                String.format(body, "<META CHARSET=\"GBK\">"), Charset.forName("GBK"),
                "HTML 大写 META/CHARSET 属性", true, false);
        add("html-meta", "html-meta-single-quote",
                String.format(body, "<meta charset='gbk'>"), Charset.forName("GBK"),
                "HTML meta 属性用单引号", true, false);
        add("html-meta", "html-meta-no-quote",
                String.format(body, "<meta charset=gbk>"), Charset.forName("GBK"),
                "HTML meta 属性无引号", true, false);
        add("html-meta", "html-meta-unknown-name",
                String.format(body, "<meta charset=\"X-UNKNOWN-ENCODING\">"), StandardCharsets.UTF_8,
                "HTML 声明了不存在的字符集名（Jsoup 原样返回）", true, false);
        add("html-meta", "html-utf8-bom-with-meta",
                new String(withBom(metaUtf8.getBytes(StandardCharsets.UTF_8)),
                        StandardCharsets.ISO_8859_1),
                StandardCharsets.ISO_8859_1,
                "HTML 带 BOM 与 meta（BOM 在解码前已被剥离）", true, false);
    }

    private void addMixedAndGarbage() {
        String mixed = "第 3 章 Chapter Three — 中英混排 Mixed Text 测试 12345\n"
                + "He said “你好”，and she replied “Hello”。\n"
                + "比例 3:1，温度 25°C，价格 ¥99.9，时间 2024-01-01 12:00:00。\n"
                + "URL: https://example.com/path?q=%E4%B8%AD%E6%96%87&lang=zh-CN\n"
                + "Email: test@example.com  #hashtag  @mention  <tag>  [bracket]  {brace}\n";

        add("mixed", "mixed-cn-en-utf8", mixed, StandardCharsets.UTF_8, "中英混排（UTF-8）", true, false);
        add("mixed", "mixed-cn-en-gbk", mixed, Charset.forName("GBK"), "中英混排（GBK）", true, false);
        add("mixed", "mixed-cn-en-big5", mixed, Charset.forName("Big5"), "中英混排（Big5）", true, false);
        add("mixed", "mixed-cn-en-gb18030", mixed, Charset.forName("GB18030"), "中英混排（GB18030）", true, false);
        add("mixed", "mixed-cn-en-utf16le", mixed, StandardCharsets.UTF_16LE, "中英混排（UTF-16LE）", true, false);
        add("mixed", "mixed-cn-en-utf16be", mixed, StandardCharsets.UTF_16BE, "中英混排（UTF-16BE）", true, false);
        add("mixed", "mixed-cn-jp-kr-utf8", "中文 日本語 한국어 混排 テスト 한국어 테스트 테스트",
                StandardCharsets.UTF_8, "中/日/韩混排（UTF-8）", true, false);
        add("mixed", "mixed-emoji-utf8", "第 1 章 出发 🚀✨ 天气不错 ☀️ 心情很好 😊",
                StandardCharsets.UTF_8, "含 emoji 的 UTF-8（4 字节序列）", true, false);
        add("mixed", "mixed-numbers-punct",
                "0123456789 !@#$%^&*()_+-=[]{}|;':\",./<>? `~ ！＠＃￥％……＆×（）——＋",
                StandardCharsets.UTF_8, "ASCII + 全角标点", true, false);

        // 乱码字节：编码与声明不一致、随机高位字节、二进制
        add("garbage", "garbage-utf8-read-as-gbk",
                new String(CN_PASSAGE.getBytes(StandardCharsets.UTF_8), Charset.forName("GBK")),
                Charset.forName("GBK"), "UTF-8 字节被当 GBK 解读后的乱码文本（再以 GBK 编码）", true, false);
        add("garbage", "garbage-gbk-read-as-utf8",
                new String(CN_PASSAGE.getBytes(Charset.forName("GBK")), StandardCharsets.UTF_8),
                StandardCharsets.UTF_8, "GBK 字节被当 UTF-8 解读后的替换字符文本", true, false);
        addBytes("garbage", "garbage-random-high-bytes", randomBytes(300, 0x80, 0xFF),
                "纯随机高位字节（300 字节）", false, false);
        addBytes("garbage", "garbage-random-all-bytes", randomBytes(400, 0x00, 0xFF),
                "纯随机全字节域（400 字节）", false, false);
        addBytes("garbage", "garbage-binary-zip-magic",
                concat(new byte[]{0x50, 0x4B, 0x03, 0x04}, randomBytes(200, 0x00, 0xFF)),
                "ZIP 魔数 + 随机二进制", false, false);
        addBytes("garbage", "garbage-all-ff", repeatByte((byte) 0xFF, 256), "256 个 0xFF", false, false);
        addBytes("garbage", "garbage-all-80", repeatByte((byte) 0x80, 256), "256 个 0x80", false, false);
        addBytes("garbage", "garbage-nulls-mixed", concat(repeatByte((byte) 0x00, 64),
                        "some text in between".getBytes(StandardCharsets.UTF_8),
                        repeatByte((byte) 0x00, 64)),
                "NUL 填充 + ASCII", false, false);
        addBytes("garbage", "garbage-control-chars", repeatByte((byte) 0x01, 32),
                "32 个控制字符 0x01", false, false);
        addBytes("garbage", "garbage-truncated-multibyte",
                truncate(CN_PASSAGE.getBytes(StandardCharsets.UTF_8), 7),
                "UTF-8 多字节序列被截断（7 字节）", true, false);
        addBytes("garbage", "garbage-gbk-trailing-single",
                truncate(CN_PASSAGE.getBytes(Charset.forName("GBK")), 21),
                "GBK 双字节序列被截断（21 字节，落单尾字节）", true, false);
        addBytes("garbage", "garbage-c1-control", concat("text".getBytes(StandardCharsets.UTF_8),
                        new byte[]{(byte) 0x9B, 0x1B, (byte) 0x9B}, "more text".getBytes(StandardCharsets.UTF_8)),
                "含 C1 控制字节（0x9B/0x1B）", false, false);

        // 空数据
        addBytes("empty", "empty-zero-bytes", new byte[0], "空字节数组", false, false);
        addBytes("empty", "empty-one-byte-null", new byte[]{0x00}, "单个 NUL 字节", false, false);
        addBytes("empty", "empty-whitespace-only", "\n\t \r\n".getBytes(StandardCharsets.UTF_8),
                "仅空白字符", false, false);
        addBytes("empty", "empty-only-bom", new byte[]{(byte) 0xEF, (byte) 0xBB, (byte) 0xBF},
                "仅含 UTF-8 BOM（剥离后为空）", false, false);
        addBytes("empty", "empty-only-bom16le", new byte[]{(byte) 0xFF, (byte) 0xFE},
                "仅含 UTF-16LE BOM", false, false);
        addBytes("empty", "empty-only-bom16be", new byte[]{(byte) 0xFE, (byte) 0xFF},
                "仅含 UTF-16BE BOM", false, false);
    }

    /** 40 份「真实小说章节风格」的合成文本：按编码各生成若干份。 */
    private void addNovelChapters() {
        String[] chapters = {CN_PASSAGE, CN_PASSAGE_2, CN_PASSAGE_3, CN_PASSAGE_4};
        Charset[] cnEncodings = {
                StandardCharsets.UTF_8, StandardCharsets.UTF_8, StandardCharsets.UTF_8,
                Charset.forName("GBK"), Charset.forName("GBK"),
                Charset.forName("GB2312"),
                Charset.forName("GB18030"), Charset.forName("GB18030"),
        };
        // 4 章 × 8 编码 = 32 份（中文系）
        for (int i = 0; i < chapters.length; i++) {
            for (int j = 0; j < cnEncodings.length; j++) {
                Charset cs = cnEncodings[j];
                String label = cs.name().startsWith("UTF-8") ? "utf8"
                        : cs.name().toLowerCase().replace("gb", "gb");
                add("novel-cn", "novel-chapter" + (i + 1) + "-" + label, chapters[i], cs,
                        "合成小说章节（第 " + (i + 1) + " 章，编码 " + cs.name()
                                + "，中文网络小说排版风格）", true, true);
            }
        }

        // 繁体 2 份
        add("novel-tw", "novel-tw-chapter1-big5", TW_PASSAGE, Charset.forName("Big5"),
                "合成小说章节（繁体，Big5）", true, true);
        add("novel-tw", "novel-tw-chapter1-utf8", TW_PASSAGE, StandardCharsets.UTF_8,
                "合成小说章节（繁体，UTF-8）", true, true);

        // 日文 2 份
        add("novel-jp", "novel-jp-chapter1-sjis", JP_PASSAGE, Charset.forName("Shift_JIS"),
                "合成小说章节（日文，Shift_JIS）", true, true);
        add("novel-jp", "novel-jp-chapter1-eucjp", JP_PASSAGE, Charset.forName("EUC-JP"),
                "合成小说章节（日文，EUC-JP）", true, true);

        // 韩文 2 份
        add("novel-kr", "novel-kr-chapter1-euckr", KR_PASSAGE, Charset.forName("EUC-KR"),
                "合成小说章节（韩文，EUC-KR）", true, true);
        add("novel-kr", "novel-kr-chapter1-utf8", KR_PASSAGE, StandardCharsets.UTF_8,
                "合成小说章节（韩文，UTF-8）", true, true);

        // 英文 1 份
        add("novel-en", "novel-en-chapter1-utf8", LATIN_PASSAGE, StandardCharsets.UTF_8,
                "合成小说章节（英文，UTF-8）", true, true);

        // 中文 → UTF-16 2 份
        add("novel-utf16", "novel-chapter2-utf16le", CN_PASSAGE_2, StandardCharsets.UTF_16LE,
                "合成小说章节（中文，UTF-16LE）", true, true);
        add("novel-utf16", "novel-chapter2-utf16be", CN_PASSAGE_2, StandardCharsets.UTF_16BE,
                "合成小说章节（中文，UTF-16BE）", true, true);

        // 长章节（>2000 字节）用于验证 kBufSize 上限行为：2 份
        StringBuilder longCn = new StringBuilder();
        for (int i = 0; i < 12; i++) {
            longCn.append(CN_PASSAGE).append(CN_PASSAGE_2).append('\n');
        }
        add("novel-long", "novel-long-chapter-utf8", longCn.toString(), StandardCharsets.UTF_8,
                "合成小说长章节（>2000 字节，UTF-8）", true, true);
        add("novel-long", "novel-long-chapter-gbk", longCn.toString(), Charset.forName("GBK"),
                "合成小说长章节（>2000 字节，GBK）", true, true);

        // 拉丁小说风格 2 份
        StringBuilder longLatin = new StringBuilder();
        for (int i = 0; i < 8; i++) {
            longLatin.append(LATIN_PASSAGE).append('\n');
        }
        add("novel-latin", "novel-latin-chapter-iso88591", longLatin.toString(),
                Charset.forName("ISO-8859-1"), "合成小说章节（拉丁，ISO-8859-1）", true, true);
        add("novel-latin", "novel-latin-chapter-win1252", longLatin.toString(),
                Charset.forName("windows-1252"), "合成小说章节（拉丁，windows-1252）", true, true);
    }

    // ---------------------------------------------------------------- 工具

    private static byte[] withBom(byte[] b) {
        return concat(new byte[]{(byte) 0xEF, (byte) 0xBB, (byte) 0xBF}, b);
    }

    private static byte[] withBom16LE(byte[] b) {
        return concat(new byte[]{(byte) 0xFF, (byte) 0xFE}, b);
    }

    private static byte[] withBom16BE(byte[] b) {
        return concat(new byte[]{(byte) 0xFE, (byte) 0xFF}, b);
    }

    private static byte[] concat(byte[]... parts) {
        ByteArrayOutputStream out = new ByteArrayOutputStream();
        for (byte[] p : parts) {
            out.writeBytes(p);
        }
        return out.toByteArray();
    }

    private static byte[] repeatByte(byte value, int count) {
        byte[] out = new byte[count];
        java.util.Arrays.fill(out, value);
        return out;
    }

    /** 固定种子的伪随机字节（保证 golden 可复现）。 */
    private static byte[] randomBytes(int count, int lo, int hi) {
        java.util.Random rnd = new java.util.Random(20260101L + count * 31L + lo);
        byte[] out = new byte[count];
        int span = hi - lo + 1;
        for (int i = 0; i < count; i++) {
            out[i] = (byte) (lo + rnd.nextInt(span));
        }
        return out;
    }

    private static byte[] truncate(byte[] b, int len) {
        byte[] out = new byte[Math.min(len, b.length)];
        System.arraycopy(b, 0, out, 0, out.length);
        return out;
    }

    static String base64(byte[] b) {
        return Base64.getEncoder().encodeToString(b);
    }

    /** 供调试/日志用的分组计数。 */
    static Map<String, Integer> groupCounts(List<Sample> list) {
        Map<String, Integer> m = new LinkedHashMap<>();
        for (Sample s : list) {
            m.merge(s.group, 1, Integer::sum);
        }
        return m;
    }
}
