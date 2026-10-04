// 权威：对每个 (lead,trail) 给出 JDK 的真实 CoderResult 与消耗长度
import java.nio.*; import java.nio.charset.*;
public class JdkProf {
  static String res(String cs,int...bs){
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
    String cs=a[0];
    if(a[1].equals("single")){
      for(int h=0x80;h<=0xFF;h++){ String r=res(cs,h); System.out.printf("%02X %s%n",h,r); }
      return;
    }
    int hi=Integer.parseInt(a[1],16);
    StringBuilder m=new StringBuilder(), u=new StringBuilder(), bad=new StringBuilder();
    for(int lo=0x20;lo<=0xFF;lo++){
      String r=res(cs,hi,lo);
      if(r.equals("MAP")) m.append(String.format("%02X ",lo));
      else if(r.startsWith("U")) u.append(String.format("%02X ",lo));
      else if(r.startsWith("M")) bad.append(String.format("%02X:",lo)).append(r).append(" ");
    }
    System.out.println("MAP "+m); System.out.println("U  "+u); System.out.println("M  "+bad);
  }
}
