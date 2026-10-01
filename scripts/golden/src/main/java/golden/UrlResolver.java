package golden;

import java.net.URL;

/**
 * Kotlin io.legado.app.utils.NetworkUtils.getAbsoluteURL 的调度逻辑手工移植到 Java，
 * 内部的相对 URL 解析用真实 java.net.URL（真实库）。golden 对照的是 Kotlin
 * NetworkUtils.getAbsoluteURL 的最终行为（而非裸 java.net.URL）。
 *
 * Kotlin 原文（NetworkUtils.kt）：
 *   fun getAbsoluteURL(baseURL: String?, relativePath: String): String {
 *       if (baseURL.isNullOrEmpty()) return relativePath.trim()
 *       var absoluteUrl: URL? = null
 *       try { absoluteUrl = URL(baseURL.substringBefore(",")) } catch (e) { }
 *       return getAbsoluteURL(absoluteUrl, relativePath)
 *   }
 *   fun getAbsoluteURL(baseURL: URL?, relativePath: String): String {
 *       val relativePathTrim = relativePath.trim()
 *       if (baseURL == null) return relativePathTrim
 *       if (relativePathTrim.isAbsUrl()) return relativePathTrim
 *       if (relativePathTrim.isDataUrl()) return relativePathTrim
 *       if (relativePathTrim.startsWith("javascript")) return ""
 *       var relativeUrl = relativePathTrim
 *       try { relativeUrl = URL(baseURL, relativePath).toString(); return relativeUrl } catch (e) { }
 *       return relativeUrl
 *   }
 *
 * isAbsUrl / isDataUrl 复刻 Kotlin StringExtensions（legado 里 isAbsUrl 判定 http(s) 开头，
 * isDataUrl 判定 data: 开头）。
 */
public final class UrlResolver {

    // Kotlin String.isAbsUrl()：以 http:// 或 https:// 开头（忽略大小写）。
    static boolean isAbsUrl(String s) {
        if (s == null) return false;
        String l = s.toLowerCase();
        return l.startsWith("http://") || l.startsWith("https://");
    }

    // Kotlin String.isDataUrl()：以 data: 开头（忽略大小写，允许 data:xxx;base64,）。
    static boolean isDataUrl(String s) {
        if (s == null) return false;
        return s.matches("(?i)^data:.*;base64,.*");
    }

    static String substringBefore(String s, String delim) {
        int idx = s.indexOf(delim);
        return idx < 0 ? s : s.substring(0, idx);
    }

    /** 对应 Kotlin getAbsoluteURL(baseURL: String?, relativePath). */
    public static String getAbsoluteURL(String baseURL, String relativePath) {
        if (baseURL == null || baseURL.isEmpty()) {
            return relativePath.trim();
        }
        URL absoluteUrl = null;
        try {
            absoluteUrl = new URL(substringBefore(baseURL, ","));
        } catch (Exception e) {
            // Kotlin: e.printOnDebug() —— 吞异常，absoluteUrl 保持 null
        }
        return getAbsoluteURL(absoluteUrl, relativePath);
    }

    /** 对应 Kotlin getAbsoluteURL(baseURL: URL?, relativePath). */
    static String getAbsoluteURL(URL baseURL, String relativePath) {
        String relativePathTrim = relativePath.trim();
        if (baseURL == null) return relativePathTrim;
        if (isAbsUrl(relativePathTrim)) return relativePathTrim;
        if (isDataUrl(relativePathTrim)) return relativePathTrim;
        if (relativePathTrim.startsWith("javascript")) return "";
        String relativeUrl = relativePathTrim;
        try {
            // 注意：Kotlin 用未 trim 的 relativePath
            URL parseUrl = new URL(baseURL, relativePath);
            relativeUrl = parseUrl.toString();
            return relativeUrl;
        } catch (Exception e) {
            // Kotlin: AppLog.put(...) —— 吞异常
        }
        return relativeUrl;
    }
}
