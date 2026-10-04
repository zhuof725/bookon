package golden;

import org.jsoup.Jsoup;
import org.jsoup.nodes.Element;
import org.jsoup.nodes.TextNode;
import org.jsoup.parser.Parser;
import org.jsoup.select.Collector;
import org.jsoup.select.Elements;
import org.jsoup.select.Evaluator;

import java.util.ArrayList;
import java.util.List;

/**
 * 逐函数、逐分支对照 legado 的 AnalyzeByJSoup.kt 移植到 Java（用真实 jsoup 1.16.2）。
 * 作为 golden 对照的"参考实现"——这就是 Swift 版 AnalyzeByJSoup 试图精确复刻的原始行为。
 */
public class AnalyzeByJSoup {

    private final Element element;

    public AnalyzeByJSoup(Object doc) {
        this.element = parse(doc);
    }

    private Element parse(Object doc) {
        if (doc instanceof Element) {
            return (Element) doc;
        }
        String s = doc.toString();
        try {
            if (s.regionMatches(true, 0, "<?xml", 0, 5)) {
                return Jsoup.parse(s, "", Parser.xmlParser());
            }
        } catch (Exception ignored) {}
        return Jsoup.parse(s);
    }

    public Elements getElements(String rule) {
        return getElements(element, rule);
    }

    public String getString(String ruleStr) {
        if (ruleStr.isEmpty()) return null;
        List<String> list = getStringList(ruleStr);
        if (list.isEmpty()) return null;
        if (list.size() == 1) return list.get(0);
        return String.join("\n", list);
    }

    public String getString0(String ruleStr) {
        List<String> list = getStringList(ruleStr);
        return list.isEmpty() ? "" : list.get(0);
    }

    public List<String> getStringList(String ruleStr) {
        ArrayList<String> textS = new ArrayList<>();
        if (ruleStr.isEmpty()) return textS;

        SourceRule sourceRule = new SourceRule(ruleStr);

        if (sourceRule.elementsRule.isEmpty()) {
            textS.add(element.data());
        } else {
            RuleAnalyzer ruleAnalyzes = new RuleAnalyzer(sourceRule.elementsRule);
            ArrayList<String> ruleStrS = ruleAnalyzes.splitRule("&&", "||", "%%");

            ArrayList<List<String>> results = new ArrayList<>();
            for (String ruleStrX : ruleStrS) {
                List<String> temp;
                if (sourceRule.isCss) {
                    int lastIndex = ruleStrX.lastIndexOf('@');
                    if (lastIndex < 0) {
                        temp = getResultLast(element.select(ruleStrX), "");
                    } else {
                        temp = getResultLast(element.select(ruleStrX.substring(0, lastIndex)),
                                ruleStrX.substring(lastIndex + 1));
                    }
                } else {
                    temp = getResultList(ruleStrX);
                }

                if (temp != null && !temp.isEmpty()) {
                    results.add(temp);
                    if ("||".equals(ruleAnalyzes.elementsType)) break;
                }
            }
            if (!results.isEmpty()) {
                if ("%%".equals(ruleAnalyzes.elementsType)) {
                    for (int i = 0; i < results.get(0).size(); i++) {
                        for (List<String> temp : results) {
                            if (i < temp.size()) textS.add(temp.get(i));
                        }
                    }
                } else {
                    for (List<String> temp : results) textS.addAll(temp);
                }
            }
        }
        return textS;
    }

    private Elements getElements(Element temp, String rule) {
        if (temp == null || rule.isEmpty()) return new Elements();

        Elements elements = new Elements();
        SourceRule sourceRule = new SourceRule(rule);
        RuleAnalyzer ruleAnalyzes = new RuleAnalyzer(sourceRule.elementsRule);
        ArrayList<String> ruleStrS = ruleAnalyzes.splitRule("&&", "||", "%%");

        ArrayList<Elements> elementsList = new ArrayList<>();
        if (sourceRule.isCss) {
            for (String ruleStr : ruleStrS) {
                Elements tempS = temp.select(ruleStr);
                elementsList.add(tempS);
                if (!tempS.isEmpty() && "||".equals(ruleAnalyzes.elementsType)) break;
            }
        } else {
            for (String ruleStr : ruleStrS) {
                RuleAnalyzer rsRule = new RuleAnalyzer(ruleStr);
                rsRule.trim();
                ArrayList<String> rs = rsRule.splitRule("@");

                Elements el;
                if (rs.size() > 1) {
                    Elements acc = new Elements();
                    acc.add(temp);
                    for (String rl : rs) {
                        Elements es = new Elements();
                        for (Element et : acc) es.addAll(getElements(et, rl));
                        acc = es;
                    }
                    el = acc;
                } else {
                    el = new ElementsSingle().getElementsSingle(temp, ruleStr);
                }

                elementsList.add(el);
                if (!el.isEmpty() && "||".equals(ruleAnalyzes.elementsType)) break;
            }
        }

        if (!elementsList.isEmpty()) {
            if ("%%".equals(ruleAnalyzes.elementsType)) {
                for (int i = 0; i < elementsList.get(0).size(); i++) {
                    for (Elements es : elementsList) {
                        if (i < es.size()) elements.add(es.get(i));
                    }
                }
            } else {
                for (Elements es : elementsList) elements.addAll(es);
            }
        }
        return elements;
    }

    private List<String> getResultList(String ruleStr) {
        if (ruleStr.isEmpty()) return null;

        Elements elements = new Elements();
        elements.add(element);

        RuleAnalyzer rule = new RuleAnalyzer(ruleStr);
        rule.trim();
        ArrayList<String> rules = rule.splitRule("@");

        int last = rules.size() - 1;
        for (int i = 0; i < last; i++) {
            Elements es = new Elements();
            for (Element elt : elements) {
                es.addAll(new ElementsSingle().getElementsSingle(elt, rules.get(i)));
            }
            elements = es;
        }
        if (elements.isEmpty()) return null;
        return getResultLast(elements, rules.get(last));
    }

    private ArrayList<String> getResultLast(Elements elements, String lastRule) {
        ArrayList<String> textS = new ArrayList<>();
        switch (lastRule) {
            case "text":
                for (Element el : elements) {
                    String text = el.text();
                    if (!text.isEmpty()) textS.add(text);
                }
                break;
            case "textNodes":
                for (Element el : elements) {
                    ArrayList<String> tn = new ArrayList<>();
                    for (TextNode item : el.textNodes()) {
                        String text = item.text().trim();
                        if (!text.isEmpty()) tn.add(text);
                    }
                    if (!tn.isEmpty()) textS.add(String.join("\n", tn));
                }
                break;
            case "ownText":
                for (Element el : elements) {
                    String text = el.ownText();
                    if (!text.isEmpty()) textS.add(text);
                }
                break;
            case "html": {
                elements.select("script").remove();
                elements.select("style").remove();
                String html = elements.outerHtml();
                if (!html.isEmpty()) textS.add(html);
                break;
            }
            case "all":
                textS.add(elements.outerHtml());
                break;
            default:
                for (Element el : elements) {
                    String url = el.attr(lastRule);
                    if (url.trim().isEmpty() || textS.contains(url)) continue;
                    textS.add(url);
                }
        }
        return textS;
    }

    static class SourceRule {
        boolean isCss = false;
        String elementsRule;

        SourceRule(String ruleStr) {
            if (ruleStr.regionMatches(true, 0, "@CSS:", 0, 5)) {
                isCss = true;
                elementsRule = ruleStr.substring(5).trim();
            } else {
                elementsRule = ruleStr;
            }
        }
    }

    static class ElementsSingle {
        char split = '.';
        String beforeRule = "";
        ArrayList<Integer> indexDefault = new ArrayList<>();
        ArrayList<Object> indexes = new ArrayList<>(); // Integer 或 int[3]{start,end,step}(可能为 null 用 Integer.MIN_VALUE 表示省略)

        Elements getElementsSingle(Element temp, String rule) {
            findIndexSet(rule);

            Elements elements;
            if (beforeRule.isEmpty()) {
                elements = temp.children();
            } else {
                String[] rules = beforeRule.split("\\.", -1);
                switch (rules[0]) {
                    case "children":
                        elements = temp.children();
                        break;
                    case "class":
                        elements = rules.length > 1 ? temp.getElementsByClass(rules[1]) : new Elements();
                        break;
                    case "tag":
                        elements = rules.length > 1 ? temp.getElementsByTag(rules[1]) : new Elements();
                        break;
                    case "id":
                        elements = rules.length > 1 ? Collector.collect(new Evaluator.Id(rules[1]), temp) : new Elements();
                        break;
                    case "text":
                        elements = rules.length > 1 ? temp.getElementsContainingOwnText(rules[1]) : new Elements();
                        break;
                    default:
                        elements = temp.select(beforeRule);
                }
            }

            int len = elements.size();
            int lastIndexes = (indexDefault.size() - 1) != -1 ? (indexDefault.size() - 1) : (indexes.size() - 1);
            java.util.LinkedHashSet<Integer> indexSet = new java.util.LinkedHashSet<>();

            if (indexes.isEmpty()) {
                for (int ix = lastIndexes; ix >= 0; ix--) {
                    int it = indexDefault.get(ix);
                    if (it >= 0 && it < len) indexSet.add(it);
                    else if (it < 0 && len >= -it) indexSet.add(it + len);
                }
            } else {
                for (int ix = lastIndexes; ix >= 0; ix--) {
                    Object o = indexes.get(ix);
                    if (o instanceof int[]) {
                        int[] triple = (int[]) o; // [startOrMin, endOrMin, step]
                        Integer startX = triple[0] == Integer.MIN_VALUE ? null : triple[0];
                        Integer endX = triple[1] == Integer.MIN_VALUE ? null : triple[1];
                        int stepX = triple[2];

                        int startV = startX == null ? 0 : startX;
                        if (startV < 0) startV += len;
                        int endV = endX == null ? (len - 1) : endX;
                        if (endV < 0) endV += len;

                        if ((startV < 0 && endV < 0) || (startV >= len && endV >= len)) continue;
                        if (startV >= len) startV = len - 1; else if (startV < 0) startV = 0;
                        if (endV >= len) endV = len - 1; else if (endV < 0) endV = 0;

                        if (startV == endV || stepX >= len) {
                            indexSet.add(startV);
                            continue;
                        }
                        int stp = stepX > 0 ? stepX : (-stepX < len ? stepX + len : 1);
                        if (endV > startV) {
                            for (int v = startV; v <= endV; v += stp) indexSet.add(v);
                        } else {
                            for (int v = startV; v >= endV; v -= stp) indexSet.add(v);
                        }
                    } else {
                        int it = (Integer) o;
                        if (it >= 0 && it < len) indexSet.add(it);
                        else if (it < 0 && len >= -it) indexSet.add(it + len);
                    }
                }
            }

            if (split == '!') {
                Elements es = new Elements();
                for (int i = 0; i < elements.size(); i++) {
                    if (!indexSet.contains(i)) es.add(elements.get(i));
                }
                elements = es;
            } else if (split == '.') {
                Elements es = new Elements();
                for (int idx : indexSet) {
                    if (idx >= 0 && idx < elements.size()) es.add(elements.get(idx));
                }
                elements = es;
            }
            return elements;
        }

        private void findIndexSet(String rule) {
            String rus = rule.trim();
            int len = rus.length();
            Integer curInt;
            boolean curMinus = false;
            ArrayList<Integer> curList = new ArrayList<>();
            StringBuilder l = new StringBuilder();

            boolean head = len > 0 && rus.charAt(len - 1) == ']';

            if (head) {
                len--;
                while (true) {
                    boolean cond = len >= 0;
                    len--;
                    if (!cond) break;
                    int idx = len;
                    if (idx < 0) break;
                    char rl = rus.charAt(idx);
                    if (rl == ' ') continue;

                    if (rl >= '0' && rl <= '9') { l.insert(0, rl); }
                    else if (rl == '-') { curMinus = true; }
                    else {
                        curInt = l.length() == 0 ? null : (curMinus ? -Integer.parseInt(l.toString()) : Integer.parseInt(l.toString()));
                        if (rl == ':') {
                            curList.add(curInt);
                        } else {
                            if (curList.isEmpty()) {
                                if (curInt == null) break;
                                indexes.add(curInt);
                            } else {
                                int step = (curList.size() == 2 ? curList.get(0) : 1);
                                int startEnc = curInt == null ? Integer.MIN_VALUE : curInt;
                                Integer lastV = curList.get(curList.size() - 1);
                                int endEnc = lastV == null ? Integer.MIN_VALUE : lastV;
                                indexes.add(new int[]{startEnc, endEnc, step});
                                curList.clear();
                            }
                            if (rl == '!') {
                                split = '!';
                                do {
                                    len--;
                                    if (len < 0) break;
                                    rl = rus.charAt(len);
                                } while (len > 0 && rl == ' ');
                            }
                            if (rl == '[') {
                                beforeRule = rus.substring(0, Math.max(len, 0));
                                return;
                            }
                            if (rl != ',') break;
                        }
                        l.setLength(0);
                        curMinus = false;
                    }
                }
            } else {
                while (true) {
                    boolean cond = len >= 0;
                    len--;
                    if (!cond) break;
                    int idx = len;
                    if (idx < 0) break;
                    char rl = rus.charAt(idx);
                    if (rl == ' ') continue;

                    if (rl >= '0' && rl <= '9') { l.insert(0, rl); }
                    else if (rl == '-') { curMinus = true; }
                    else {
                        if (rl == '!' || rl == '.' || rl == ':') {
                            int val = l.length() == 0 ? 0 : Integer.parseInt(l.toString());
                            indexDefault.add(curMinus ? -val : val);
                            if (rl != ':') {
                                split = rl;
                                beforeRule = rus.substring(0, idx);
                                return;
                            }
                        } else break;
                        l.setLength(0);
                        curMinus = false;
                    }
                }
            }

            split = ' ';
            beforeRule = rus;
        }
    }
}
