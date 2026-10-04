import java.nio.charset.*; import java.lang.reflect.*;
public class Ex3 {
  public static void main(String[] a) throws Exception {
    Method M=Mir.class.getDeclaredMethod("decode", byte[].class, String.class); M.setAccessible(true);
    int bad=0,tot=0; String first=null;
    // EUC-JP 三字节：8F x y（全覆盖）+ 8E/8F 前缀与后续
    for(int y=0;y<256;y++) for(int z=0;z<256;z++){
      byte[] b={(byte)0x8F,(byte)y,(byte)z};
      String jdk=new String(b,Charset.forName("EUC-JP"));
      String mir=(String)M.invoke(null,b,"EUC-JP"); if(mir==null)mir="<null>";
      tot++; if(!jdk.equals(mir)){ bad++; if(first==null) first=String.format("8F %02X %02X jdk=%s mir=%s",y,z,esc(jdk),esc(mir)); }
    }
    System.out.printf("EUC-JP 3B(8F**) %d/%d%s  %s%n", tot-bad, tot, bad==0?" ✅":" ✗", first==null?"":first);
  }
  static String esc(String s){StringBuilder r=new StringBuilder();for(char c:s.toCharArray())r.append(String.format("\\u%04X",(int)c));return r.toString();}
}
