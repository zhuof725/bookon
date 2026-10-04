import java.nio.*; import java.nio.charset.*; import java.util.*; import java.io.*;


public class Mir {
  static Map<Integer,int[][]> E(int... p) {   // lead -> [[a,b],...]
    Map<Integer,int[][]> m = new HashMap<>(); return m;
  }
  static boolean in(int[][] rs, int v){ for(int[] r:rs) if(v>=r[0]&&v<=r[1]) return true; return false; }

  // ---- 与 Swift MBCSProfile 一一对应的画像 ----
  record P(int singleMax, int sbLo, int sbHi, int sbExtraLo, int sbExtraHi,
           int[][] lead, int[][] trail, int[][] u2, int[][] m2,
           Map<Integer,int[][]> exc, Map<Integer,int[][]> exc2, int[] three, Integer digit, boolean jdkBig5) {}

  static P profile(String name) {
    switch (name) {
      case "GBK": case "GB2312": case "CP936":
        return new P(0x7F,0,0,0,-1, new int[][]{{0x81,0xFE}}, new int[][]{{0x40,0x7E},{0x80,0xFE}},
                     new int[][]{{0xFF,0xFF}}, new int[][]{}, Map.of(), Map.of(), new int[]{}, null, false);
      case "GB18030":
        return new P(0x7F,0,0,0,-1, new int[][]{{0x81,0xFE}}, new int[][]{{0x40,0x7E},{0x80,0xFE}},
                     new int[][]{{0xFF,0xFF}}, new int[][]{{0x30,0x39}}, Map.of(), Map.of(), new int[]{}, 0x30, false);
      case "BIG5":
        Map<Integer,int[][]> exc = new HashMap<>();
        exc.put(0xA1,new int[][]{{0xC3,0xC3},{0xC5,0xC5}});
        exc.put(0xA3,new int[][]{{0xC0,0xC7},{0xC9,0xF9}});
        exc.put(0xF9,new int[][]{{0xD6,0xF9}});
        return new P(0x7F,0,0,0,-1, new int[][]{{0xA1,0xC7},{0xC9,0xF9}}, new int[][]{{0x40,0x7E},{0xA1,0xFE}},
                     new int[][]{{0x80,0xA0},{0xFF,0xFF}}, new int[][]{}, exc, Map.of(), new int[]{}, null, true);
      default: return null;
    }
  }


  static P profile2(String name) {
    switch (name) {
      case "GB2312":
        return new P(0x7F,0,0,0,-1, new int[][]{{0x81,0xFE}}, new int[][]{{0x40,0x7E},{0x80,0xFE}},
                     new int[][]{{0xFF,0xFF}}, new int[][]{}, Map.of(), Map.of(), new int[]{}, null, false);
      case "SHIFT-JIS":
        return new P(0x7F,0,0,0xA1,0xDF, new int[][]{{0x81,0x84},{0x88,0x9F},{0xE0,0xEA}}, new int[][]{{0x40,0x7E},{0x80,0xFC}},
                     new int[][]{{0xFD,0xFF}}, new int[][]{}, sjisMal(), sjisUn(), new int[]{}, null, false);
      case "EUC-KR":
        return new P(0x7F,0,0,0,-1, new int[][]{{0xA1,0xAC},{0xB0,0xC8},{0xCA,0xFD}}, new int[][]{{0xA1,0xFE}},
                     new int[][]{{0x80,0xA0},{0xFF,0xFF}}, new int[][]{}, krMal(), krUn(), new int[]{}, null, false);
      case "EUC-JP":
        return new P(0x7F,0,0,0,-1, new int[][]{{0x80,0xFF}}, new int[][]{{0xA1,0xFE}},
                     new int[][]{{0x00,0xA0},{0xFF,0xFF}}, new int[][]{}, Map.of(), eucJpHoles(), new int[]{0x8E,0x8F}, null, false);
      default: return profile(name);
    }
  }

  static Map<Integer,int[][]> eucJpHoles() {
    Map<Integer,int[][]> m = new HashMap<>();
    m.put(0xFF, new int[][]{{0xA1,0xFE}});
    m.put(0xA2, new int[][]{{0xAF,0xB9},{0xC2,0xC9},{0xD1,0xDB},{0xEB,0xF1},{0xFA,0xFD}});
    m.put(0xA3, new int[][]{{0xA1,0xAF},{0xBA,0xC0},{0xDB,0xE0},{0xFB,0xFE}});
    m.put(0xA4, new int[][]{{0xF4,0xFE}});
    m.put(0xA5, new int[][]{{0xF7,0xFE}});
    m.put(0xA6, new int[][]{{0xB9,0xC0},{0xD9,0xFE}});
    m.put(0xA7, new int[][]{{0xC2,0xD0},{0xF2,0xFE}});
    m.put(0xA8, new int[][]{{0xC1,0xFE}});
    m.put(0xA9, new int[][]{{0xA1,0xFE}});
    m.put(0xAA, new int[][]{{0xA1,0xFE}});
    m.put(0xAB, new int[][]{{0xA1,0xFE}});
    m.put(0xAC, new int[][]{{0xA1,0xFE}});
    m.put(0xAD, new int[][]{{0xA1,0xFE}});
    m.put(0xAE, new int[][]{{0xA1,0xFE}});
    m.put(0xAF, new int[][]{{0xA1,0xFE}});
    m.put(0xCF, new int[][]{{0xD4,0xFE}});
    m.put(0xF4, new int[][]{{0xA7,0xFE}});
    m.put(0xF5, new int[][]{{0xA1,0xFE}});
    m.put(0xF6, new int[][]{{0xA1,0xFE}});
    m.put(0xF7, new int[][]{{0xA1,0xFE}});
    m.put(0xF8, new int[][]{{0xA1,0xFE}});
    m.put(0xF9, new int[][]{{0xA1,0xFE}});
    m.put(0xFA, new int[][]{{0xA1,0xFE}});
    m.put(0xFB, new int[][]{{0xA1,0xFE}});
    m.put(0xFC, new int[][]{{0xA1,0xFE}});
    m.put(0xFD, new int[][]{{0xA1,0xFE}});
    m.put(0xFE, new int[][]{{0xA1,0xFE}});
    return m;
  }

  static Map<Integer,int[][]> sjisMal() {
    Map<Integer,int[][]> m = new HashMap<>();
    m.put(0x81, new int[][]{{0xAD,0xB7},{0xC0,0xC7},{0xCF,0xD9},{0xE9,0xEA}});
    m.put(0x82, new int[][]{{0x40,0x4E},{0x59,0x5F},{0x7A,0x7E},{0x9B,0x9E}});
    m.put(0x83, new int[][]{{0x97,0x9E},{0xB7,0xBE},{0xD7,0xEA}});
    m.put(0x84, new int[][]{{0x61,0x6F},{0x92,0x9E},{0xBF,0xEA}});
    m.put(0x88, new int[][]{{0x40,0x7E},{0x81,0x84},{0x88,0x9E}});
    m.put(0x98, new int[][]{{0x73,0x7E},{0x81,0x84},{0x88,0x9E}});
    m.put(0xEA, new int[][]{{0xA5,0xEA}});
    return m;
  }
  static Map<Integer,int[][]> sjisUn() {
    Map<Integer,int[][]> m = new HashMap<>();
    m.put(0x81, new int[][]{{0xEB,0xEF},{0xF8,0xFB}});
    m.put(0x82, new int[][]{{0x80,0x80},{0xF2,0xFC}});
    m.put(0x83, new int[][]{{0xEB,0xFC}});
    m.put(0x84, new int[][]{{0xEB,0xFC}});
    m.put(0x88, new int[][]{{0x80,0x80},{0x85,0x87}});
    m.put(0x98, new int[][]{{0x80,0x80},{0x85,0x87}});
    m.put(0xEA, new int[][]{{0xEB,0xFC}});
    return m;
  }

  static Map<Integer,int[][]> krMal() {
    Map<Integer,int[][]> m = new HashMap<>();
    m.put(0xA2, new int[][]{{0xE9,0xFD}});
    m.put(0xA5, new int[][]{{0xAB,0xAC},{0xBA,0xC0},{0xD9,0xE0},{0xF9,0xFD}});
    m.put(0xA6, new int[][]{{0xE5,0xFD}});
    m.put(0xA7, new int[][]{{0xF0,0xFD}});
    m.put(0xA8, new int[][]{{0xA5,0xA5},{0xA7,0xA7},{0xB0,0xB0}});
    m.put(0xAA, new int[][]{{0xF4,0xFD}});
    m.put(0xAB, new int[][]{{0xF7,0xFD}});
    m.put(0xAC, new int[][]{{0xC2,0xC8},{0xCA,0xD0},{0xF2,0xFD}});
    return m;
  }
  static Map<Integer,int[][]> krUn() {
    Map<Integer,int[][]> m = new HashMap<>();
    m.put(0xA2, new int[][]{{0xFE,0xFE}});
    m.put(0xA5, new int[][]{{0xAD,0xAF},{0xFE,0xFE}});
    m.put(0xA6, new int[][]{{0xFE,0xFE}});
    m.put(0xA7, new int[][]{{0xFE,0xFE}});
    m.put(0xAA, new int[][]{{0xFE,0xFE}});
    m.put(0xAB, new int[][]{{0xFE,0xFE}});
    m.put(0xAC, new int[][]{{0xC9,0xC9},{0xFE,0xFE}});
    return m;
  }

  /** CF 模拟：用 JDK 表（对 GB 系与 JDK 一致）。 */
  static String cf(byte[] b, String cs) { return new String(b, Charset.forName(cs)); }

  static int[] b2i(byte[] b){ int[] r=new int[b.length]; for(int i=0;i<b.length;i++) r[i]=b[i]&0xFF; return r; }

  static String decode(byte[] raw, String csName) {
    P p = profile2(csName);
    if (p==null) return null;
    int[] b = b2i(raw); int n = b.length;
    Charset cs = Charset.forName(csName);
    StringBuilder out = new StringBuilder();
    int i = 0;
    while (i < n) {
      int x = b[i];
      // 单字节
      boolean single = (x <= p.singleMax) || (p.sbExtraHi>=0 && x>=p.sbExtraLo && x<=p.sbExtraHi);
      if (single) {
        String s = cf(new byte[]{(byte)x}, csName);
        if (s.length()==1) { out.append(s); i++; continue; }
        out.append('\uFFFD'); i++; continue;
      }
      int seqLen = 0; boolean u2 = false;
      boolean isSpecial = false;
      for (int tl : p.three) if (x==tl) isSpecial = true;
      if (in(p.lead, x) && !isSpecial) {
        if (i+1 < n) {
          int t = b[i+1];
          if (in(p.trail, t)) {
            if (p.exc.containsKey(x) && in(p.exc.get(x), t)) { out.append('\uFFFD'); i++; continue; }
            if (p.exc2.containsKey(x) && in(p.exc2.get(x), t)) { out.append('\uFFFD'); i+=2; continue; }
            if (p.digit != null && t>=p.digit && t<=p.digit+9 && i+3<n
                && in(p.lead, b[i+2]) && b[i+3]>=p.digit && b[i+3]<=p.digit+9) seqLen = 4;
            else seqLen = 2;
          } else if (in(p.u2, t)) { seqLen = 2; u2 = true; }
          else if (in(p.m2, t)) { seqLen = 2; u2 = true; }
        }
      }
      if (seqLen == 0 && p.three.length>0 && i+1<n) {
        for (int tl : p.three) if (x==tl) {
          if (x==0x8E) {
            int t2=b[i+1]; seqLen=2; if(!(t2>=0xA1&&t2<=0xDF)) u2=true;
          } else {
            if (i+2<n) { seqLen=3; int y=b[i+2];
              boolean shape = in(p.trail,b[i+1]) && in(p.trail,y);
              if(!shape) u2=true; }
            else { seqLen=2; u2=true; }
          }
          break;
        }
      }
      if (seqLen > 0) {
        if (!u2) {
          byte[] s = new byte[seqLen];
          for (int k=0;k<seqLen;k++) s[k]=raw[i+k];
          String r = cf(s, csName);
          if (r!=null && r.length()==1) { out.append(r); i+=seqLen; continue; }
        }
        out.append('\uFFFD'); i+=seqLen; continue;
      }
      out.append('\uFFFD'); i++;
    }
    return out.toString();
  }
  static boolean hasPua(String s){ for(int i=0;i<s.length();i++){int c=s.charAt(i); if(c>=0xE000&&c<=0xF8FF)return true;} return false; }

  public static void main(String[] args) throws Exception {
    // args: <charsetName> <hexbytes...>  -> 打印结果
    String cs = args[0];
    byte[] in = hex2b(args[1]);
    System.out.print(decode(in, cs));
  }
  static byte[] hex2b(String h){ String[] p=h.trim().split("\\s+"); byte[] r=new byte[p.length];
    for(int i=0;i<p.length;i++) r[i]=(byte)Integer.parseInt(p[i],16); return r; }
}
