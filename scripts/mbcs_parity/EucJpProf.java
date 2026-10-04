// 生成 EUC-JP 的 A1-FE lead 的 trail 分带（映射区间 vs 无映射区间）
import java.nio.*; import java.nio.charset.*; import java.util.*;
public class EucJpProf {
  static String res(int hi,int lo){
    CharsetDecoder d=Charset.forName("EUC-JP").newDecoder()
      .onMalformedInput(CodingErrorAction.REPORT).onUnmappableCharacter(CodingErrorAction.REPORT);
    ByteBuffer bb=ByteBuffer.wrap(new byte[]{(byte)hi,(byte)lo}); CharBuffer cb=CharBuffer.allocate(8);
    CoderResult r=d.decode(bb,cb,true);
    if(r.isUnderflow()&&cb.position()==1) return "MAP";
    if(r.isUnmappable()) return "U"+r.length();
    if(r.isMalformed()) return "M"+r.length();
    return "?";
  }
  static int mcount=0, ucount=0, umax=0; static String umaxHi="";
  public static void main(String[] a){
    System.out.println("// lead: [MAP 区间] [UNMAPPABLE 区间] [MALFORMED 区间]");
    for(int hi=0xA1;hi<=0xFE;hi++){
      List<int[]> map=new ArrayList<>(), un=new ArrayList<>(), mal=new ArrayList<>();
      int s=-1, kind=-1;
      for(int lo=0x00;lo<=0xFF;lo++){
        String r=res(hi,lo);
        int k = r.equals("MAP")?0 : (r.startsWith("U")?1:2);
        if(k!=kind){ if(kind>=0) add(kind,s,lo-1,map,un,mal); s=lo; kind=k; }
      }
      if(kind>=0) add(kind,s,0xFF,map,un,mal);
      StringBuilder b=new StringBuilder();
      b.append(String.format("%02X ",hi));
      b.append("M").append(fmt(map)).append(" U").append(fmt(un)).append(" X").append(fmt(mal));
      System.out.println(b);
      if(!mal.isEmpty()){ System.out.println("  !! MALFORMED non-empty for "+hi); }
    }
  }
  static void add(int k,int s,int e,List<int[]> m,List<int[]> u,List<int[]> x){
    if(s>e) return;
    if(k==0) m.add(new int[]{s,e}); else if(k==1) u.add(new int[]{s,e}); else x.add(new int[]{s,e});
  }
  static String fmt(List<int[]> l){ StringBuilder b=new StringBuilder(); for(int[] r:l){
    if(r[0]==r[1]) b.append(String.format("%02X ",r[0])); else b.append(String.format("%02X-%02X ",r[0],r[1])); }
    return b.toString().trim(); }
}
