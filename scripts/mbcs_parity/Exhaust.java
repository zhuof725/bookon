// 穷举：对每个编码，比较 Mir 模拟 与 真实 JDK 在 1/2/3 字节上的替换语义
import java.nio.charset.*; import java.lang.reflect.*;
public class Exhaust {
  public static void main(String[] a) throws Exception {
    Method M=Mir.class.getDeclaredMethod("decode", byte[].class, String.class); M.setAccessible(true);
    String[] css={"GBK","GB2312","BIG5","SHIFT-JIS","EUC-KR","EUC-JP"};
    for(String cs: css){
      int bad=0, tot=0; String firstMsg=null;
      // 1 字节
      for(int x=0;x<256;x++){
        byte[] b={(byte)x};
        String jdk=trunc(new String(b,Charset.forName(cs)));
        String mir=(String)M.invoke(null,b,cs); if(mir==null)mir="<null>";
        tot++; if(!jdk.equals(mir)){ bad++; if(firstMsg==null) firstMsg=String.format("1B %02X jdk=%s mir=%s",x,esc(jdk),esc(mir)); }
      }
      // 2 字节（全组合）
      for(int x=0;x<256;x++) for(int y=0;y<256;y++){
        byte[] b={(byte)x,(byte)y};
        String jdk=trunc(new String(b,Charset.forName(cs)));
        String mir=(String)M.invoke(null,b,cs); if(mir==null)mir="<null>";
        tot++; if(!jdk.equals(mir)){ bad++; if(firstMsg==null) firstMsg=String.format("2B %02X %02X jdk=%s mir=%s",x,y,esc(jdk),esc(mir)); }
      }
      System.out.printf("%-10s %d/%d%s  %s%n", cs, tot-bad, tot, bad==0?" ✅":" ✗", firstMsg==null?"":firstMsg);
    }
  }
  static String trunc(String s){ return s; }
  static String esc(String s){StringBuilder r=new StringBuilder();for(char c:s.toCharArray())r.append(String.format("\\u%04X",(int)c));return r.toString();}
}
