// 通用：为任一 MBCS 编码导出「单字节集 + lead/trail 分带 + 例外表」
import java.nio.*; import java.nio.charset.*; import java.util.*;
public class GenProf2 {
  static String cs;
  static String res(int...bs){
    if(bs.length==1){ // 单字节判映射
      byte[] in={(byte)bs[0]};
      CharsetDecoder d=Charset.forName(cs).newDecoder()
        .onMalformedInput(CodingErrorAction.REPORT).onUnmappableCharacter(CodingErrorAction.REPORT);
      ByteBuffer bb=ByteBuffer.wrap(in); CharBuffer cb=CharBuffer.allocate(8);
      CoderResult r=d.decode(bb,cb,true);
      if(r.isUnderflow()&&cb.position()==1) return "MAP";
      if(r.isMalformed()) return "M"+r.length();
      return "?";
    }
    byte[] in=new byte[bs.length]; for(int i=0;i<bs.length;i++)in[i]=(byte)bs[i];
    CharsetDecoder d=Charset.forName(cs).newDecoder()
      .onMalformedInput(CodingErrorAction.REPORT).onUnmappableCharacter(CodingErrorAction.REPORT);
    ByteBuffer bb=ByteBuffer.wrap(in); CharBuffer cb=CharBuffer.allocate(8);
    CoderResult r=d.decode(bb,cb,true);
    if(r.isUnderflow()&&cb.position()==1) return "MAP";
    if(r.isUnmappable()) return "U"+r.length();
    if(r.isMalformed()) return "M"+r.length();
    return "?";
  }
  public static void main(String[] a){
    cs=a[0];
    // 1) 单字节
    List<int[]> sb=new ArrayList<>(); int s=-1;
    for(int b=0;b<=0x7F;b++){} // ASCII 恒单字节
    // 单字节额外段（0x80+）
    StringBuilder sbext=new StringBuilder();
    s=-1; int prev=-2; List<int[]> ex=new ArrayList<>();
    for(int b=0x80;b<=0xFF;b++){
      boolean isMap = res(b).equals("MAP");
      if(isMap){ if(s<0) s=b; prev=b; }
      else { if(s>=0){ ex.add(new int[]{s,prev}); s=-1; } }
    }
    if(s>=0) ex.add(new int[]{s,prev});
    System.out.println("SINGLE_EXTRA "+fmt(ex));
    // 2) lead 判定：该字节作 lead 是否「有非 M1 行为」→ 视为 lead
    //    用 (hi, 0x40) 与 (hi, 0xA1) 试探
    List<int[]> leads=new ArrayList<>(); s=-1; prev=-2;
    for(int hi=0x80;hi<=0xFF;hi++){
      // 跳过纯单字节映射字节
      boolean single=false; for(int[] r:ex) if(hi>=r[0]&&hi<=r[1]) single=true;
      if(single){ if(s>=0){leads.add(new int[]{s,prev}); s=-1;} continue; }
      String r1=res(hi,0x40), r2=res(hi,0xA1);
      // lead 的定义：该字节 + 一个合法/半合法尾字节时，JDK 不是"只吃 1 字节"（M1）。
      boolean isLead = r1.equals("MAP") || r1.startsWith("U") || r1.equals("M2")
                    || r2.equals("MAP") || r2.startsWith("U") || r2.equals("M2");
      if(isLead){ if(s<0) s=hi; prev=hi; }
      else { if(s>=0){ leads.add(new int[]{s,prev}); s=-1; } }
    }
    if(s>=0) leads.add(new int[]{s,prev});
    System.out.println("LEAD "+fmt(leads));
    // 3) 对每个 lead 求 trail 分带（用 U/M 判定）
    System.out.println("--- per-lead ---");
    for(int[] lr: leads){
      for(int hi=lr[0];hi<=lr[1];hi++){
        StringBuilder map=new StringBuilder(), u=new StringBuilder(), m=new StringBuilder();
        int ss=-1, kind=-1, pv=-1;
        for(int lo=0x00;lo<=0xFF;lo++){
          String r=res(hi,lo);
          int k = r.equals("MAP")?0 : (r.startsWith("U")?1:2);
          if(k!=kind){ flush(kind,ss,pv,map,u,m); ss=lo; kind=k; }
          pv=lo;
        }
        flush(kind,ss,pv,map,u,m);
        System.out.printf("%02X M%s U%s X%s%n",hi,map,u,m);
      }
    }
  }
  static void flush(int k,int s,int e,StringBuilder m,StringBuilder u,StringBuilder x){
    if(k<0||s<0||s>e) return;
    (k==0?m:(k==1?u:x)).append((s==e)?String.format("%02X ",s):String.format("%02X-%02X ",s,e));
  }
  static String fmt(List<int[]> l){ StringBuilder b=new StringBuilder(); for(int[] r:l){
    if(r[0]==r[1]) b.append(String.format("%02X ",r[0])); else b.append(String.format("%02X-%02X ",r[0],r[1])); }
    return b.toString().trim(); }
}
