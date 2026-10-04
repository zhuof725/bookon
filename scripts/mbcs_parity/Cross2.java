import java.nio.charset.*; import java.util.*; import java.io.*;
import com.google.gson.*;
public class Cross2 {
  static java.lang.reflect.Method M;
  public static void main(String[] a) throws Exception {
    M = Mir.class.getDeclaredMethod("decode", byte[].class, String.class); M.setAccessible(true);
    String json = new String(java.nio.file.Files.readAllBytes(
        java.nio.file.Path.of(System.getProperty("golden","/tmp/golden_out/charset_cases.json"))),
        java.nio.charset.StandardCharsets.UTF_8);
    JsonArray arr = JsonParser.parseString(json).getAsJsonObject().getAsJsonArray("charsetResults");
    String[] css = {"EUC-JP","SHIFT-JIS","EUC-KR","GBK","BIG5","GB18030"};
    Map<String,int[]> stat = new LinkedHashMap<>();
    for (String cs: css) stat.put(cs, new int[]{0,0});
    for (JsonElement e : arr) {
      JsonObject o = e.getAsJsonObject();
      String name = o.get("name").getAsString();
      byte[] bytes = Base64.getDecoder().decode(o.get("bytesBase64").getAsString());
      for (String cs : css) {
        String jdk;
        try { jdk = new String(bytes, Charset.forName(cs)); } catch (Exception ex) { jdk = "<ERR>"; }
        String mir = (String) M.invoke(null, bytes, cs);
        if (mir==null) mir="<null>";
        // golden 侧统一截断 400 UTF-16 单元
        jdk = trunc400(jdk); mir = trunc400(mir);
        stat.get(cs)[0]++;
        if (!jdk.equals(mir)) {
          stat.get(cs)[1]++;
          if (stat.get(cs)[1] <= 4)
            System.out.printf("DIFF[%s] %-28s%n  jdk=[%s]%n  mir=[%s]%n", cs, name, t(jdk), t(mir));
        }
      }
    }
    System.out.println("---- 汇总 ----");
    for (String cs: css) {
      int[] s = stat.get(cs);
      System.out.printf("%-10s %d/%d%s%n", cs, s[0]-s[1], s[0], s[1]==0?"  ✅":"");
    }
  }
  static String trunc400(String s){ return s.length()>400? s.substring(0,400): s; }
  static String t(String s){ StringBuilder b=new StringBuilder();
    for(char c: s.toCharArray()) b.append(c=='\n'? "\\n" : (c<0x20||c>0x7E? String.format("\\u%04X",(int)c): ""+c));
    String r=b.toString(); return r.length()>100? r.substring(0,100)+"…":r; }
}
