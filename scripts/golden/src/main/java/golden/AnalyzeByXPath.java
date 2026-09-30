package golden;

import org.jsoup.Jsoup;
import org.jsoup.nodes.Document;
import org.jsoup.nodes.Element;
import org.jsoup.parser.Parser;
import org.jsoup.select.Elements;
import org.seimicrawler.xpath.JXDocument;
import org.seimicrawler.xpath.JXNode;

import java.util.ArrayList;
import java.util.List;

/**
 * 逐函数对照 legado 的 AnalyzeByXPath.kt 移植到 Java（用真实 JsoupXpath 2.5.3）。
 * 作为 golden 对照的"参考实现"。
 */
public class AnalyzeByXPath {

    private final Object jxNode; // JXNode 或 JXDocument

    public AnalyzeByXPath(Object doc) {
        this.jxNode = parse(doc);
    }

    private Object parse(Object doc) {
        if (doc instanceof JXNode) {
            JXNode n = (JXNode) doc;
            return n.isElement() ? n : strToJXDocument(n.toString());
        }
        if (doc instanceof Document) return JXDocument.create((Document) doc);
        if (doc instanceof Element) return JXDocument.create(new Elements((Element) doc));
        if (doc instanceof Elements) return JXDocument.create((Elements) doc);
        return strToJXDocument(doc.toString());
    }

    private JXDocument strToJXDocument(String html) {
        String html1 = html;
        if (html1.endsWith("</td>")) html1 = "<tr>" + html1 + "</tr>";
        if (html1.endsWith("</tr>") || html1.endsWith("</tbody>")) html1 = "<table>" + html1 + "</table>";
        try {
            if (html1.trim().regionMatches(true, 0, "<?xml", 0, 5)) {
                return JXDocument.create(Jsoup.parse(html1, "", Parser.xmlParser()));
            }
        } catch (Exception ignored) {}
        return JXDocument.create(html1);
    }

    private List<JXNode> getResult(String xPath) {
        try {
            if (jxNode instanceof JXNode) {
                return ((JXNode) jxNode).sel(xPath);
            } else {
                return ((JXDocument) jxNode).selN(xPath);
            }
        } catch (Exception e) {
            return null;
        }
    }

    public List<JXNode> getElements(String xPath) {
        if (xPath.isEmpty()) return null;

        ArrayList<JXNode> jxNodes = new ArrayList<>();
        RuleAnalyzer ruleAnalyzes = new RuleAnalyzer(xPath);
        ArrayList<String> rules = ruleAnalyzes.splitRule("&&", "||", "%%");

        if (rules.size() == 1) {
            return getResult(rules.get(0));
        } else {
            ArrayList<List<JXNode>> results = new ArrayList<>();
            for (String rl : rules) {
                List<JXNode> temp = getElements(rl);
                if (temp != null && !temp.isEmpty()) {
                    results.add(temp);
                    if ("||".equals(ruleAnalyzes.elementsType)) break;
                }
            }
            if (!results.isEmpty()) {
                if ("%%".equals(ruleAnalyzes.elementsType)) {
                    for (int i = 0; i < results.get(0).size(); i++) {
                        for (List<JXNode> temp : results) {
                            if (i < temp.size()) jxNodes.add(temp.get(i));
                        }
                    }
                } else {
                    for (List<JXNode> temp : results) jxNodes.addAll(temp);
                }
            }
        }
        return jxNodes;
    }

    public List<String> getStringList(String xPath) {
        ArrayList<String> result = new ArrayList<>();
        RuleAnalyzer ruleAnalyzes = new RuleAnalyzer(xPath);
        ArrayList<String> rules = ruleAnalyzes.splitRule("&&", "||", "%%");

        if (rules.size() == 1) {
            List<JXNode> nodes = getResult(xPath);
            if (nodes != null) {
                for (JXNode n : nodes) result.add(n.asString());
            }
            return result;
        } else {
            ArrayList<List<String>> results = new ArrayList<>();
            for (String rl : rules) {
                List<String> temp = getStringList(rl);
                if (!temp.isEmpty()) {
                    results.add(temp);
                    if ("||".equals(ruleAnalyzes.elementsType)) break;
                }
            }
            if (!results.isEmpty()) {
                if ("%%".equals(ruleAnalyzes.elementsType)) {
                    for (int i = 0; i < results.get(0).size(); i++) {
                        for (List<String> temp : results) {
                            if (i < temp.size()) result.add(temp.get(i));
                        }
                    }
                } else {
                    for (List<String> temp : results) result.addAll(temp);
                }
            }
        }
        return result;
    }

    public String getString(String rule) {
        RuleAnalyzer ruleAnalyzes = new RuleAnalyzer(rule);
        ArrayList<String> rules = ruleAnalyzes.splitRule("&&", "||");
        if (rules.size() == 1) {
            List<JXNode> nodes = getResult(rule);
            if (nodes == null) return null;
            StringBuilder sb = new StringBuilder();
            for (int i = 0; i < nodes.size(); i++) {
                if (i > 0) sb.append("\n");
                sb.append(nodes.get(i).toString());
            }
            return sb.toString();
        } else {
            ArrayList<String> textList = new ArrayList<>();
            for (String rl : rules) {
                String temp = getString(rl);
                if (temp != null && !temp.isEmpty()) {
                    textList.add(temp);
                    if ("||".equals(ruleAnalyzes.elementsType)) break;
                }
            }
            return String.join("\n", textList);
        }
    }
}
