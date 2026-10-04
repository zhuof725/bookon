import java.nio.*;
import java.nio.charset.*;
public class G2312Prof {
  static String kind(String cs, int hi, int lo) {
    byte[] b={(byte)hi,(byte)lo};
    CharsetDecoder d=Charset.forName(cs).newDecoder()
      .onMalformedInput(CodingErrorAction.REPORT).onUnmappableCharacter(CodingErrorAction.REPORT);
    ByteBuffer in=ByteBuffer.wrap(b); CharBuffer out=CharBuffer.allocate(4);
    CoderResult r=d.decode(in,out,true);
    if (!r.isError()) return "MAP";
    return (r.isMalformed()?"MAL":"U") + r.length();
  }
  public static void main(String[] a) {
    // 对每个 lead，扫全部 lo，输出「分带」
    StringBuilder sb=new StringBuilder();
    for (int hi=0xA1; hi<=0xF7; hi++) {
      String prev=null; int start=0;
      StringBuilder line=new StringBuilder();
      for (int lo=0; lo<=0xFF; lo++) {
        String k=kind("GB2312",hi,lo);
        if (prev==null){prev=k;start=lo;continue;}
        if (!k.equals(prev)) { line.append(String.format("%s[%02X-%02X] ",prev,start,lo-1)); prev=k; start=lo; }
      }
      if (prev!=null) line.append(String.format("%s[%02X-%02X] ",prev,start,0xFF));
      sb.append(String.format("%02X: %s%n", hi, line.toString().trim()));
    }
    try { java.nio.file.Files.write(java.nio.file.Paths.get("gb2312_prof.txt"), sb.toString().getBytes("UTF-8")); } catch(Exception e){}
    System.out.println(sb.substring(0, 1200));
  }
}
