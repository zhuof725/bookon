// ⚠️ JVM 桩（golden 专用）：legado 的 Android 类若引用 android.util.Log，
// 这里提供最小可编译替代实现（输出到 stderr，仅为编译期兜底，golden 生成器不依赖日志）。
package android.util;

/**
 * 最小 Log 桩：仅提供 legado 源码用到的 d/i/w/e 静态方法。
 */
public final class Log {

    private Log() {
    }

    public static int d(String tag, String msg) {
        return log(tag, msg);
    }

    public static int d(String tag, String msg, Throwable tr) {
        return log(tag, msg + '\n' + (tr == null ? "null" : tr.toString()));
    }

    public static int i(String tag, String msg) {
        return log(tag, msg);
    }

    public static int i(String tag, String msg, Throwable tr) {
        return log(tag, msg + '\n' + (tr == null ? "null" : tr.toString()));
    }

    public static int w(String tag, String msg) {
        return log(tag, msg);
    }

    public static int w(String tag, String msg, Throwable tr) {
        return log(tag, msg + '\n' + (tr == null ? "null" : tr.toString()));
    }

    public static int w(String tag, Throwable tr) {
        return log(tag, tr == null ? "null" : tr.toString());
    }

    public static int e(String tag, String msg) {
        return log(tag, msg);
    }

    public static int e(String tag, String msg, Throwable tr) {
        return log(tag, msg + '\n' + (tr == null ? "null" : tr.toString()));
    }

    public static int e(String tag, Throwable tr) {
        return log(tag, tr == null ? "null" : tr.toString());
    }

    private static int log(String tag, String msg) {
        System.err.println("[stub-Log] " + tag + ": " + msg);
        return 0;
    }
}
