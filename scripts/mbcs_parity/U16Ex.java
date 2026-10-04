import java.nio.*; import java.nio.charset.*;
public class U16Ex {
  // Swift 新语义的模拟
  static String sim(byte[] b, boolean le) {
    StringBuilder sb=new StringBuilder();
    int i=0,n=b.length;
    while(i<n){
      int avail=n-i;
      if(avail<2){ sb.append('\uFFFD'); i=n; continue; }
      int u1 = le ? (b[i]&0xFF)|((b[i+1]&0xFF)<<8) : ((b[i]&0xFF)<<8)|(b[i+1]&0xFF);
      if(u1>=0xD800&&u1<=0xDBFF){
        if(avail>=4){
          int u2 = le ? (b[i+2]&0xFF)|((b[i+3]&0xFF)<<8) : ((b[i+2]&0xFF)<<8)|(b[i+3]&0xFF);
          if(u2>=0xDC00&&u2<=0xDFFF){
            int cp = 0x10000 + ((u1-0xD800)<<10) + (u2-0xDC00);
            sb.appendCodePoint(cp); i+=4; continue;
          }
          sb.append('\uFFFD'); i+=4; continue;
        } else { sb.append('\uFFFD'); i+=2; continue; }
      } else if(u1>=0xDC00&&u1<=0xDFFF){ sb.append('\uFFFD'); i+=2; continue; }
      else { sb.append((char)u1); i+=2; continue; }
    }
    return sb.toString();
  }
  public static void main(String[] a){
    String cs="UTF-16LE"; boolean le=true;
    int tot=0,bad=0; String first=null;
    // 1 字节
    for(int x=0;x<256;x++){ byte[] b={(byte)x};
      String jdk=new String(b,Charset.forName(cs)); String mir=sim(b,le);
      tot++; if(!jdk.equals(mir)){bad++; if(first==null) first=String.format("1B %02X jdk=%s sim=%s",x,esc(jdk),esc(mir));}}
    // 2 字节
    for(int x=0;x<256;x++) for(int y=0;y<256;y++){ byte[] b={(byte)x,(byte)y};
      String jdk=new String(b,Charset.forName(cs)); String mir=sim(b,le);
      tot++; if(!jdk.equals(mir)){bad++; if(first==null) first=String.format("2B %02X %02X jdk=%s sim=%s",x,y,esc(jdk),esc(mir));}}
    System.out.printf("UTF-16LE 1+2B  %d/%d%s %s%n", tot-bad, tot, bad==0?" ✅":" ✗", first==null?"":first);
    // 4 字节：只遍历「高代理开头」的 2 字节 + 全部 2 字节 → 采样
    int tot2=0,bad2=0; String first2=null;
    for(int x=0xD8;x<=0xDB;x++) for(int y=0;y<256;y++) for(int p=0;p<256;p++) for(int q=0;q<256;q++){
      byte[] b={(byte)y,(byte)x,(byte)q,(byte)p};  // LE: unit1 = x*256+y ... 用 LE 编码
      byte[] bb={(byte)y,(byte)x,(byte)p,(byte)q};
      String jdk=new String(bb,Charset.forName(cs)); String mir=sim(bb,le);
      tot2++; if(!jdk.equals(mir)){bad2++; if(first2==null) first2=String.format("4B %02X %02X %02X %02X jdk=%s sim=%s",y,x,p,q,esc(jdk),esc(mir));}
      if(tot2>3000000) break;
    }
    System.out.printf("UTF-16LE 高代理4B %d/%d%s %s%n", tot2-bad2, tot2, bad2==0?" ✅":" ✗", first2==null?"":first2);
  }
  static String esc(String s){StringBuilder r=new StringBuilder();for(char c:s.toCharArray())r.append(String.format("\\u%04X",(int)c));return r.toString();}
}
