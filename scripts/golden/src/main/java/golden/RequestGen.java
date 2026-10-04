package golden;

import com.google.gson.Gson;
import com.google.gson.GsonBuilder;
import com.google.gson.JsonArray;
import com.google.gson.JsonObject;
import com.sun.net.httpserver.HttpExchange;
import com.sun.net.httpserver.HttpServer;
import okhttp3.FormBody;
import okhttp3.Headers;
import okhttp3.MediaType;
import okhttp3.MultipartBody;
import okhttp3.OkHttpClient;
import okhttp3.Request;
import okhttp3.RequestBody;
import okhttp3.Response;
import okhttp3.ResponseBody;

import java.io.ByteArrayOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;
import java.net.InetSocketAddress;
import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.Base64;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.concurrent.TimeUnit;

/**
 * OkHttp 请求/重定向对照 golden 生成器（task 3）。
 *
 * <p>用<b>真实 OkHttp 5.3.2</b>（pom 里的 {@code okhttp-jvm}），按 legado
 * {@code help/http/OkHttpUtils.kt} 里 {@code get / postForm / postJson / postMultipart /
 * addHeaders} 的同样构造方式发请求，打到本地 {@link HttpServer}
 * （{@code com.sun.net.httpserver}）上；服务器把「实际收到的」内容记录下来：
 * <ul>
 *   <li>{@code method}；</li>
 *   <li>{@code path} + {@code query}（原始 query 串与会话化后的有序参数对）；</li>
 *   <li>有序显式头（排除 OkHttp 自动加入的 {@code Host/Connection/Accept-Encoding/User-Agent/
 *       Content-Length/Content-Type(自动)/Transfer-Encoding} 等，只保留用例显式 addHeader 的头）；</li>
 *   <li>{@code Cookie} 头（单独列出，便于 Swift 侧比对 Cookie 注入语义）；</li>
 *   <li>body 字节（Base64；multipart 的 {@code boundary} 归一化为 {@code --BOUNDARY--}）。</li>
 * </ul>
 *
 * <p>覆盖 4 组：
 * <ol>
 *   <li>{@code requestCases}：GET / POST form / POST json / POST raw / multipart / HEAD（≥40 条）；</li>
 *   <li>{@code redirectCases}：301/302/303/307/308、跨域重定向、重定向链中途 Set-Cookie、
 *       循环重定向上限（≥30 条）；</li>
 *   <li>{@code cookieCases}：Set-Cookie → CookieJar → 后续请求 Cookie 头（≥10 条）；</li>
 *   <li>{@code autoHeaderCases}：记录 OkHttp 自动头清单，供 README 差异表引用（若干条）。</li>
 * </ol>
 */
public final class RequestGen {

    private RequestGen() {}

    /** 总条目数（供 Main 累加 totalCases）。 */
    static int run(String outDir) throws Exception {
        HttpServer server = HttpServer.create(new InetSocketAddress("127.0.0.1", 0), 0);
        // 必须用 daemon 线程：HttpServer 的执行器线程不是守护线程，会让 JVM 在 main 结束后
        // 一直不退出（golden job 会卡到超时）。这里显式建守护线程池。
        server.setExecutor(java.util.concurrent.Executors.newFixedThreadPool(4, r -> {
            Thread t = new Thread(r, "golden-http");
            t.setDaemon(true);
            return t;
        }));
        ServerState state = new ServerState(server.getAddress().getPort());
        registerHandlers(server, state);
        server.start();
        try {
            int n = 0;
            n += runRequests(state, outDir);
            n += runRedirects(state, outDir);
            n += runCookies(state, outDir);
            n += runAutoHeaders(state, outDir);
            return n;
        } finally {
            server.stop(0);
        }
    }

    // --------------------------------------------------------------- 服务器

    /** 一次请求在服务端的完整记录。 */
    static final class Recorded {
        String method = "";
        String path = "";
        String rawQuery = "";
        final List<Map.Entry<String, String>> query = new ArrayList<>();
        final List<Map.Entry<String, String>> explicitHeaders = new ArrayList<>();
        final List<Map.Entry<String, String>> allHeaders = new ArrayList<>();
        String cookieHeader = "";
        byte[] body = new byte[0];
        int chainStep = 0;
    }

    /** 服务器共享状态（重定向链计数、Cookie 记录等）。 */
    static final class ServerState {
        final int port;
        final Map<String, List<Recorded>> records = new java.util.concurrent.ConcurrentHashMap<>();
        final Map<String, Integer> hitCount = new java.util.concurrent.ConcurrentHashMap<>();

        ServerState(int port) { this.port = port; }

        void record(String key, Recorded r) {
            records.computeIfAbsent(key, k -> java.util.Collections.synchronizedList(new ArrayList<>())).add(r);
        }

        List<Recorded> get(String key) {
            return records.getOrDefault(key, java.util.Collections.emptyList());
        }

        int hit(String key) {
            return hitCount.merge(key, 1, Integer::sum);
        }

        void reset() {
            records.clear();
            hitCount.clear();
        }
    }

    /** OkHttp 会自动加的请求头（比对「显式头」时排除；同时被 autoHeaderCases 记录）。 */
    private static final List<String> OKHTTP_AUTO_HEADERS = List.of(
            "host", "connection", "accept-encoding", "user-agent",
            "content-length", "transfer-encoding", "cookie");

    private static void registerHandlers(HttpServer server, ServerState state) {
        // 通用回声：记录后按用例要求返回
        server.createContext("/echo", ex -> {
            Recorded r = capture(ex);
            state.record("echo", r);
            byte[] resp = "ok".getBytes(StandardCharsets.UTF_8);
            respond(ex, 200, resp, null);
        });

        // 请求头回声（把收到的头以 JSON 形式返回，便于 Swift 侧观察服务器视角）
        server.createContext("/headers", ex -> {
            Recorded r = capture(ex);
            state.record("headers", r);
            JsonObject o = new JsonObject();
            o.addProperty("method", r.method);
            JsonArray hs = new JsonArray();
            for (Map.Entry<String, String> e : r.allHeaders) {
                JsonArray pair = new JsonArray();
                pair.add(e.getKey());
                pair.add(e.getValue());
                hs.add(pair);
            }
            o.add("headers", hs);
            respond(ex, 200, o.toString().getBytes(StandardCharsets.UTF_8),
                    "application/json; charset=UTF-8");
        });

        // 重定向：/redirect/<code>?to=<url>，按 code 语义发 Location
        server.createContext("/redirect", ex -> {
            Recorded r = capture(ex);
            state.record("redirect", r);
            String path = ex.getRequestURI().getPath();
            String[] parts = path.split("/");
            int code = 302;
            if (parts.length >= 3) {
                try { code = Integer.parseInt(parts[2]); } catch (NumberFormatException ignored) {}
            }
            Map<String, String> q = parseQuery(ex.getRequestURI().getRawQuery());
            String to = q.getOrDefault("to", "http://127.0.0.1:" + state.port + "/echo");
            if (q.containsKey("step")) {
                int step = Integer.parseInt(q.get("step"));
                int hits = state.hit("chain" + step);
                // 循环重定向：n 步后落到 /echo
                int max = q.containsKey("max") ? Integer.parseInt(q.get("max")) : 3;
                if (hits < max) {
                    to = "http://127.0.0.1:" + state.port + "/redirect/" + code
                            + "?to=" + urlEncode(to) + "&step=" + step + "&max=" + max;
                }
            }
            if (ex.getRequestMethod().equalsIgnoreCase("HEAD")) {
                respond(ex, code, new byte[0], null, to);
            } else {
                respond(ex, code, ("redirect " + code).getBytes(StandardCharsets.UTF_8), null, to);
            }
        });

        // 重定向链中途发 Set-Cookie
        server.createContext("/redirect-set-cookie", ex -> {
            Recorded r = capture(ex);
            state.record("redirect-set-cookie", r);
            String q = ex.getRequestURI().getRawQuery();
            Map<String, String> qm = parseQuery(q);
            String to = qm.getOrDefault("to", "http://127.0.0.1:" + state.port + "/headers");
            int code = qm.containsKey("code") ? Integer.parseInt(qm.get("code")) : 302;
            Map<String, String> headers = new LinkedHashMap<>();
            headers.put("Set-Cookie", "mid=hop1; Path=/");
            headers.put("Location", to);
            respond(ex, code, new byte[0], null, headers);
        });

        // 固定返回 Set-Cookie（CookieJar 语义）
        server.createContext("/set-cookie", ex -> {
            Recorded r = capture(ex);
            state.record("set-cookie", r);
            Map<String, String> q = parseQuery(ex.getRequestURI().getRawQuery());
            String cookie = q.getOrDefault("c", "sid=abc123");
            Map<String, String> headers = new LinkedHashMap<>();
            headers.put("Set-Cookie", cookie);
            respond(ex, 200, ("set " + cookie).getBytes(StandardCharsets.UTF_8), null, headers);
        });

        // 跨域（不同端口）目标：/cross-domain 由独立 server 提供（见 runCrossDomain）
        server.createContext("/", ex -> {
            Recorded r = capture(ex);
            state.record("root", r);
            respond(ex, 200, "ok".getBytes(StandardCharsets.UTF_8), null);
        });
    }

    private static Recorded capture(HttpExchange ex) throws IOException {
        Recorded r = new Recorded();
        r.method = ex.getRequestMethod();
        r.path = ex.getRequestURI().getPath();
        r.rawQuery = ex.getRequestURI().getRawQuery() == null ? "" : ex.getRequestURI().getRawQuery();
        for (Map.Entry<String, String> e : parseQuery(r.rawQuery).entrySet()) {
            r.query.add(new java.util.AbstractMap.SimpleEntry<>(e.getKey(), e.getValue()));
        }
        for (Map.Entry<String, List<String>> e : ex.getRequestHeaders().entrySet()) {
            String name = e.getKey();
            for (String v : e.getValue()) {
                r.allHeaders.add(new java.util.AbstractMap.SimpleEntry<>(name, v));
                String lower = name.toLowerCase(java.util.Locale.ROOT);
                if (lower.equals("cookie")) {
                    r.cookieHeader = v;
                } else if (!OKHTTP_AUTO_HEADERS.contains(lower)) {
                    r.explicitHeaders.add(new java.util.AbstractMap.SimpleEntry<>(name, v));
                }
            }
        }
        ByteArrayOutputStream buf = new ByteArrayOutputStream();
        try (InputStream in = ex.getRequestBody()) {
            byte[] tmp = new byte[8192];
            int n;
            while ((n = in.read(tmp)) > 0) buf.write(tmp, 0, n);
        }
        r.body = buf.toByteArray();
        return r;
    }

    private static void respond(HttpExchange ex, int code, byte[] body, String contentType) throws IOException {
        respond(ex, code, body, contentType, (Map<String, String>) null);
    }

    private static void respond(HttpExchange ex, int code, byte[] body, String contentType,
                                String location) throws IOException {
        Map<String, String> headers = new LinkedHashMap<>();
        if (location != null) headers.put("Location", location);
        respond(ex, code, body, contentType, headers);
    }

    private static void respond(HttpExchange ex, int code, byte[] body, String contentType,
                                Map<String, String> extraHeaders) throws IOException {
        if (contentType != null) ex.getResponseHeaders().add("Content-Type", contentType);
        if (extraHeaders != null) {
            for (Map.Entry<String, String> e : extraHeaders.entrySet()) {
                ex.getResponseHeaders().add(e.getKey(), e.getValue());
            }
        }
        boolean head = ex.getRequestMethod().equalsIgnoreCase("HEAD");
        long len = head ? -1 : body.length;
        if (head) {
            // HEAD 必须显式给出 Content-Length 或 -1；用真正长度更贴近真实服务器
            ex.getResponseHeaders().add("Content-Length", String.valueOf(body.length));
            ex.sendResponseHeaders(code, -1);
        } else {
            ex.sendResponseHeaders(code, len == 0 ? -1 : len);
            if (body.length > 0) {
                try (OutputStream os = ex.getResponseBody()) { os.write(body); }
            }
        }
        ex.close();
    }

    // --------------------------------------------------------------- OkHttp 客户端（对齐 legado）

    private static OkHttpClient newClient(boolean followRedirects) {
        return newClient(followRedirects, 20);
    }

    /** maxRedirects：对齐 OkHttp 默认重定向上限 20（超过抛 ProtocolException）。 */
    private static OkHttpClient newClient(boolean followRedirects, int maxRedirects) {
        OkHttpClient.Builder b = new OkHttpClient.Builder()
                .followRedirects(followRedirects)
                .followSslRedirects(followRedirects)
                .connectTimeout(5, TimeUnit.SECONDS)
                .readTimeout(10, TimeUnit.SECONDS);
        if (!followRedirects) {
            b.followRedirects(false);
            b.followSslRedirects(false);
        }
        // OkHttp 5.x 暴露 maxRedirects 时设置；不暴露则用默认 20（并靠循环上限保护）
        try {
            java.lang.reflect.Method m = OkHttpClient.Builder.class.getMethod("maxRedirects", int.class);
            m.invoke(b, maxRedirects);
        } catch (Exception ignored) {
        }
        return b.build();
    }

    /** 对齐 legado {@code Request.Builder.addHeaders}：遍历 map 逐条 addHeader。 */
    private static void addHeaders(Request.Builder b, Map<String, String> headers) {
        if (headers == null) return;
        for (Map.Entry<String, String> e : headers.entrySet()) {
            b.addHeader(e.getKey(), e.getValue());
        }
    }

    /** 对齐 legado {@code Request.Builder.get(url, encodedQuery)}：用 encodedQuery 替换 query。 */
    private static String appendEncodedQuery(String url, String encodedQuery) {
        if (encodedQuery == null || encodedQuery.isEmpty()) return url;
        int hash = url.indexOf('#');
        String base = hash >= 0 ? url.substring(0, hash) : url;
        String frag = hash >= 0 ? url.substring(hash) : "";
        // 去掉原 query
        int q = base.indexOf('?');
        if (q >= 0) base = base.substring(0, q);
        return base + "?" + encodedQuery + frag;
    }

    // --------------------------------------------------------------- 用例 1：请求

    private static int runRequests(ServerState state, String outDir) throws Exception {
        JsonArray arr = new JsonArray();
        String base = "http://127.0.0.1:" + state.port;

        // ---- GET ----
        addRequest(arr, state, "get-plain", base + "/echo", "GET", null, null, null, null, true, false);
        addRequest(arr, state, "get-query-simple", base + "/echo?a=1&b=2", "GET", null, null, null, null, true, false);
        addRequest(arr, state, "get-query-with-encoded",
                base + "/echo?q=%E4%B8%AD%E6%96%87&lang=zh", "GET", null, null, null, null, true, false);
        addRequest(arr, state, "get-query-encoded-flag",
                base + "/echo", "GET", "q=%E4%B8%AD%E6%96%87&x=1%202", null, "encodedQuery", null, true, false);
        addRequest(arr, state, "get-query-empty-value", base + "/echo?a=&b=2", "GET", null, null, null, null, true, false);
        addRequest(arr, state, "get-query-special-chars",
                base + "/echo?a=%21%24%26%28%29%2A%2B%2C%2F%3A%3B%3D%3F%40", "GET", null, null, null, null, true, false);
        addRequest(arr, state, "get-query-plus-space", base + "/echo?q=a+b+c", "GET", null, null, null, null, true, false);
        addRequest(arr, state, "get-query-repeat-key", base + "/echo?k=1&k=2&k=3", "GET", null, null, null, null, true, false);
        addRequest(arr, state, "get-query-unicode-raw",
                base + "/echo?q=中文测试", "GET", null, null, null, null, true, false);
        addRequest(arr, state, "get-query-fragment", base + "/echo?a=1#frag", "GET", null, null, null, null, true, false);

        Map<String, String> h1 = new LinkedHashMap<>();
        h1.put("Accept", "text/html,application/xhtml+xml");
        addRequest(arr, state, "get-headers-accept", base + "/echo", "GET", null, null, null, h1, true, false);

        Map<String, String> h2 = new LinkedHashMap<>();
        h2.put("User-Agent", "legado/1.0 (Android)");
        addRequest(arr, state, "get-headers-user-agent-override", base + "/echo", "GET", null, null, null, h2, true, false);

        Map<String, String> h3 = new LinkedHashMap<>();
        h3.put("X-A", "1");
        h3.put("X-B", "2");
        h3.put("X-C", "3");
        addRequest(arr, state, "get-headers-ordered", base + "/echo", "GET", null, null, null, h3, true, false);

        Map<String, String> h4 = new LinkedHashMap<>();
        h4.put("Cookie", "a=1; b=2");
        addRequest(arr, state, "get-headers-explicit-cookie", base + "/echo", "GET", null, null, null, h4, true, false);

        Map<String, String> h5 = new LinkedHashMap<>();
        h5.put("Referer", "https://www.example.com/chapter/1");
        addRequest(arr, state, "get-headers-referer", base + "/echo", "GET", null, null, null, h5, true, false);

        Map<String, String> h6 = new LinkedHashMap<>();
        h6.put("Accept-Encoding", "gzip, deflate");
        addRequest(arr, state, "get-headers-accept-encoding", base + "/echo", "GET", null, null, null, h6, true, false);

        // ---- POST form（对齐 legado postForm(encodedForm)）----
        addRequest(arr, state, "post-form-simple", base + "/echo", "POST",
                "a=1&b=2", null, null, null, false, false);
        addRequest(arr, state, "post-form-encoded-cn", base + "/echo", "POST",
                "q=%E4%B8%AD%E6%96%87&page=1", null, null, null, false, false);
        addRequest(arr, state, "post-form-empty", base + "/echo", "POST", "", null, null, null, false, false);
        addRequest(arr, state, "post-form-repeat", base + "/echo", "POST",
                "k=1&k=2&k=3", null, null, null, false, false);
        addRequest(arr, state, "post-form-special", base + "/echo", "POST",
                "a=%21%40%23%24&b=%26%3D", null, null, null, false, false);
        addRequest(arr, state, "post-form-with-headers", base + "/echo", "POST",
                "x=1", null, null, h5, false, false);
        addRequest(arr, state, "post-form-large", base + "/echo", "POST",
                "data=" + repeat("A", 2000), null, null, null, false, false);

        Map<String, String> formMap = new LinkedHashMap<>();
        formMap.put("user", "alice");
        formMap.put("pass", "p@ss word");
        addRequest(arr, state, "post-form-map", base + "/echo", "POST",
                null, formMap, "formMap", null, false, false);

        // ---- POST json（对齐 legado postJson(json)）----
        addRequest(arr, state, "post-json-object", base + "/echo", "POST",
                "{\"a\":1,\"b\":\"中文\"}", null, "json", null, false, false);
        addRequest(arr, state, "post-json-array", base + "/echo", "POST",
                "[1,2,3]", null, "json", null, false, false);
        addRequest(arr, state, "post-json-unicode-escape", base + "/echo", "POST",
                "{\"name\":\"\\u4e2d\\u6587\"}", null, "json", null, false, false);
        addRequest(arr, state, "post-json-empty-object", base + "/echo", "POST",
                "{}", null, "json", null, false, false);
        addRequest(arr, state, "post-json-nested", base + "/echo", "POST",
                "{\"list\":[{\"id\":1},{\"id\":2}],\"ok\":true}", null, "json", null, false, false);
        addRequest(arr, state, "post-json-with-headers", base + "/echo", "POST",
                "{\"q\":\"x\"}", null, "json", h3, false, false);

        // ---- POST raw（对齐 legado post(body.toRequestBody(contentType))）----
        addRequest(arr, state, "post-raw-text-plain", base + "/echo", "POST",
                "raw body text", null, "text/plain", null, false, false);
        addRequest(arr, state, "post-raw-xml", base + "/echo", "POST",
                "<?xml version=\"1.0\"?><root><a>1</a></root>", null,
                "application/xml; charset=UTF-8", null, false, false);
        addRequest(arr, state, "post-raw-form-charset-gbk", base + "/echo", "POST",
                "key=%D6%D0%CE%C4", null, "application/x-www-form-urlencoded; charset=GBK",
                null, false, false);

        // ---- multipart（对齐 legado postMultipart）----
        Map<String, String> mp1 = new LinkedHashMap<>();
        mp1.put("field1", "value1");
        mp1.put("field2", "value2");
        addRequest(arr, state, "post-multipart-fields", base + "/echo", "POST",
                null, mp1, "multipart", null, false, false);

        Map<String, String> mp2 = new LinkedHashMap<>();
        mp2.put("file", "FILE:upload.txt:text/plain:hello file content");
        mp2.put("name", "attachment");
        addRequest(arr, state, "post-multipart-file-text", base + "/echo", "POST",
                null, mp2, "multipart", null, false, false);

        Map<String, String> mp3 = new LinkedHashMap<>();
        mp3.put("file", "FILE:pic.png:image/png:PNGDATA");
        addRequest(arr, state, "post-multipart-file-binary", base + "/echo", "POST",
                null, mp3, "multipart", null, false, false);

        Map<String, String> mp4 = new LinkedHashMap<>();
        mp4.put("a", "1");
        mp4.put("b", "中文值");
        addRequest(arr, state, "post-multipart-unicode-value", base + "/echo", "POST",
                null, mp4, "multipart", null, false, false);

        Map<String, String> mp5 = new LinkedHashMap<>();
        mp5.put("file", "FILE:doc.json:application/json:{\"k\":1}");
        addRequest(arr, state, "post-multipart-json-part", base + "/echo", "POST",
                null, mp5, "multipart", null, false, false);

        Map<String, String> mp6 = new LinkedHashMap<>();
        mp6.put("f", "v");
        addRequest(arr, state, "post-multipart-with-headers", base + "/echo", "POST",
                null, mp6, "multipart", h4, false, false);

        // ---- HEAD（对齐 legado get(urlNoQuery, encodedQuery) + head()）----
        addRequest(arr, state, "head-plain", base + "/echo", "HEAD", null, null, null, null, true, false);
        addRequest(arr, state, "head-with-query", base + "/echo?a=1", "HEAD", null, null, null, null, true, false);
        addRequest(arr, state, "head-with-headers", base + "/echo", "HEAD", null, null, null, h5, true, false);

        // ---- 不跟随重定向的 GET（对照 followRedirects=false）----
        addRequest(arr, state, "get-no-follow-redirect", base + "/redirect/302?to="
                + urlEncode(base + "/echo"), "GET", null, null, null, null, false, false);

        JsonObject root = new JsonObject();
        root.add("requestResults", arr);
        writeJson(outDir, "request_cases.json", root, "requestResults");
        System.out.println("OkHttp 请求对照: " + arr.size() + " 条（真实 OkHttp 5.3.2 → 本地 HttpServer）");
        return arr.size();
    }

    private static void addRequest(JsonArray arr, ServerState state, String name, String url,
                                   String method, String body, Map<String, String> formMap,
                                   String bodyKind, Map<String, String> headers,
                                   boolean followRedirects, boolean unused) throws Exception {
        state.reset();
        OkHttpClient client = newClient(followRedirects);

        Request.Builder rb = new Request.Builder();
        if ("GET".equals(method) || "HEAD".equals(method)) {
            if ("encodedQuery".equals(bodyKind)) {
                rb.url(appendEncodedQuery(url, body));
            } else {
                rb.url(url);
            }
            if ("HEAD".equals(method)) {
                rb.head();
            } else {
                rb.get();
            }
        } else if ("POST".equals(method)) {
            rb.url(url);
            if ("formMap".equals(bodyKind) && formMap != null) {
                FormBody.Builder fb = new FormBody.Builder();
                for (Map.Entry<String, String> e : formMap.entrySet()) fb.add(e.getKey(), e.getValue());
                rb.post(fb.build());
            } else if ("json".equals(bodyKind)) {
                rb.post(body.getBytes(StandardCharsets.UTF_8) == null ? null
                        : RequestBody.create(body.getBytes(StandardCharsets.UTF_8),
                        MediaType.get("application/json; charset=UTF-8")));
            } else if ("multipart".equals(bodyKind)) {
                MultipartBody.Builder mb = new MultipartBody.Builder();
                mb.setType(MediaType.get("multipart/form-data"));
                for (Map.Entry<String, String> e : formMap.entrySet()) {
                    String v = e.getValue();
                    if (v.startsWith("FILE:")) {
                        String[] parts = v.split(":", 4);
                        String fileName = parts[1];
                        String ct = parts[2];
                        String content = parts.length > 3 ? parts[3] : "";
                        mb.addFormDataPart(e.getKey(), fileName,
                                RequestBody.create(content.getBytes(StandardCharsets.UTF_8),
                                        MediaType.get(ct)));
                    } else {
                        mb.addFormDataPart(e.getKey(), v);
                    }
                }
                rb.post(mb.build());
            } else if (bodyKind != null && bodyKind.startsWith("text/")) {
                rb.post(RequestBody.create(body.getBytes(StandardCharsets.UTF_8),
                        MediaType.get(bodyKind)));
            } else {
                // postForm(encodedForm)：Content-Type 固定为 x-www-form-urlencoded（无 charset 参数）
                rb.post(RequestBody.create(body.getBytes(StandardCharsets.UTF_8),
                        MediaType.get("application/x-www-form-urlencoded")));
            }
        } else {
            rb.url(url);
        }

        addHeaders(rb, headers);

        JsonObject o = new JsonObject();
        o.addProperty("name", name);
        o.addProperty("kind", "request");
        o.addProperty("requestMethod", method);
        o.addProperty("requestUrl", url);
        o.addProperty("bodyKind", bodyKind);
        o.addProperty("followRedirects", followRedirects);
        JsonObject reqHeaders = new JsonObject();
        if (headers != null) for (Map.Entry<String, String> e : headers.entrySet()) reqHeaders.addProperty(e.getKey(), e.getValue());
        o.add("requestHeaders", reqHeaders);
        if (body != null) o.addProperty("requestBody", body);
        if (formMap != null) {
            JsonObject fm = new JsonObject();
            for (Map.Entry<String, String> e : formMap.entrySet()) fm.addProperty(e.getKey(), e.getValue());
            o.add("requestForm", fm);
        }

        OkHttpClient execClient = client;
        try {
            Response resp = execClient.newCall(rb.build()).execute();
            try (ResponseBody rb2 = resp.body()) {
                o.addProperty("responseCode", resp.code());
                o.addProperty("responseProtocol", resp.protocol().toString());
                if (rb2 != null) rb2.bytes();
            }
        } catch (Exception e) {
            o.addProperty("exception", e.getClass().getSimpleName() + ": " + e.getMessage());
        }

        fillServerView(o, state);
        arr.add(o);
    }

    /** 把服务器视角（method/path/query/显式头/cookie/body）写进输出对象。 */
    private static void fillServerView(JsonObject o, ServerState state) {
        List<Recorded> all = new ArrayList<>();
        for (List<Recorded> v : state.records.values()) all.addAll(v);
        JsonArray sv = new JsonArray();
        for (Recorded r : all) {
            JsonObject j = new JsonObject();
            j.addProperty("method", r.method);
            j.addProperty("path", r.path);
            j.addProperty("rawQuery", r.rawQuery);
            JsonArray qa = new JsonArray();
            for (Map.Entry<String, String> e : r.query) {
                JsonArray p = new JsonArray();
                p.add(e.getKey());
                p.add(e.getValue());
                qa.add(p);
            }
            j.add("query", qa);
            JsonArray ha = new JsonArray();
            for (Map.Entry<String, String> e : r.explicitHeaders) {
                JsonArray p = new JsonArray();
                p.add(e.getKey());
                p.add(e.getValue());
                ha.add(p);
            }
            j.add("explicitHeaders", ha);
            JsonArray allHa = new JsonArray();
            for (Map.Entry<String, String> e : r.allHeaders) {
                JsonArray p = new JsonArray();
                p.add(e.getKey());
                p.add(e.getValue());
                allHa.add(p);
            }
            j.add("allHeaders", allHa);
            j.addProperty("cookieHeader", r.cookieHeader);
            j.addProperty("bodyBase64", Base64.getEncoder().encodeToString(r.body));
            j.addProperty("bodyText", normalizeBoundary(new String(r.body, StandardCharsets.ISO_8859_1)));
            sv.add(j);
        }
        o.add("serverView", sv);
    }

    // --------------------------------------------------------------- 用例 2：重定向

    private static int runRedirects(ServerState state, String outDir) throws Exception {
        JsonArray arr = new JsonArray();
        String base = "http://127.0.0.1:" + state.port;

        int[] codes = {301, 302, 303, 307, 308};
        String[] methods = {"GET", "HEAD"};
        for (int code : codes) {
            for (String m : methods) {
                addRedirectCase(arr, state, "redirect-" + code + "-" + m.toLowerCase(), base,
                        "/redirect/" + code + "?to=" + urlEncode(base + "/echo"),
                        m, null, null, null, true);
            }
        }
        // POST 在各 code 下的 method/body 保持语义（303/301/302 会转 GET，307/308 保持 POST）
        for (int code : codes) {
            addRedirectCase(arr, state, "redirect-" + code + "-post-form", base,
                    "/redirect/" + code + "?to=" + urlEncode(base + "/echo"),
                    "POST", "a=1&b=2", null, null, true);
        }
        for (int code : codes) {
            addRedirectCase(arr, state, "redirect-" + code + "-post-json", base,
                    "/redirect/" + code + "?to=" + urlEncode(base + "/echo"),
                    "POST", "{\"k\":1}", "json", null, true);
        }

        // 跨域重定向（不同端口，模拟跨域）
        HttpServer other = HttpServer.create(new InetSocketAddress("127.0.0.1", 0), 0);
        other.setExecutor(java.util.concurrent.Executors.newFixedThreadPool(4, r -> {
            Thread t = new Thread(r, "golden-http-other");
            t.setDaemon(true);
            return t;
        }));
        ServerState otherState = new ServerState(other.getAddress().getPort());
        other.createContext("/echo", ex -> {
            Recorded r = capture(ex);
            otherState.record("echo", r);
            respond(ex, 200, "ok".getBytes(StandardCharsets.UTF_8), null);
        });
        other.createContext("/redirect", ex -> {
            Recorded r = capture(ex);
            otherState.record("redirect", r);
            String q = ex.getRequestURI().getRawQuery();
            Map<String, String> qm = parseQuery(q);
            respond(ex, 302, new byte[0], null,
                    qm.getOrDefault("to", "http://127.0.0.1:" + otherState.port + "/echo"));
        });
        other.start();
        try {
            String cross = "http://127.0.0.1:" + otherState.port;
            for (int code : new int[]{301, 302, 303, 307, 308}) {
                addRedirectCase(arr, state, "cross-domain-" + code, base,
                        "/redirect/" + code + "?to=" + urlEncode(cross + "/echo"),
                        "GET", null, null, null, true);
            }
            // 跨域 + POST（307/308 应带 body 到新域）
            for (int code : new int[]{307, 308}) {
                addRedirectCase(arr, state, "cross-domain-" + code + "-post-form", base,
                        "/redirect/" + code + "?to=" + urlEncode(cross + "/echo"),
                        "POST", "a=1&b=2", null, null, true);
            }
            // 跨域请求时显式头是否保留（含 Referer 行为）
            Map<String, String> hx = new LinkedHashMap<>();
            hx.put("X-Custom", "keep-me");
            addRedirectCase(arr, state, "cross-domain-302-explicit-header", base,
                    "/redirect/302?to=" + urlEncode(cross + "/echo"),
                    "GET", null, null, hx, true);
        } finally {
            other.stop(0);
        }

        // 重定向链中途 Set-Cookie（CookieJar 是否在后续请求带上）
        for (int code : new int[]{301, 302, 303, 307, 308}) {
            addRedirectCase(arr, state, "redirect-chain-set-cookie-" + code, base,
                    "/redirect-set-cookie?code=" + code + "&to="
                            + urlEncode(base + "/echo"),
                    "GET", null, null, null, true);
        }
        // 两跳：第一跳 Set-Cookie，第二跳再重定向到 /echo
        addRedirectCase(arr, state, "redirect-two-hop-set-cookie", base,
                "/redirect-set-cookie?code=302&to="
                        + urlEncode(base + "/redirect/302?to=" + urlEncode(base + "/echo")),
                "GET", null, null, null, true);

        // 循环重定向上限
        for (int max : new int[]{1, 3, 5, 8}) {
            addRedirectCase(arr, state, "redirect-loop-max-" + max, base,
                    "/redirect/302?step=1&max=" + max + "&to="
                            + urlEncode(base + "/echo"),
                    "GET", null, null, null, true);
        }
        // 超过重定向上限：服务器持续重定向 25 次（> OkHttp 默认 20）→ 期望抛 ProtocolException
        addRedirectCase(arr, state, "redirect-exceed-limit-25", base,
                "/redirect/302?step=99&max=25&to=" + urlEncode(base + "/echo"),
                "GET", null, null, null, true);

        // followRedirects=false：应原样收到 3xx
        for (int code : new int[]{301, 302, 303, 307, 308}) {
            addRedirectCase(arr, state, "no-follow-" + code, base,
                    "/redirect/" + code + "?to=" + urlEncode(base + "/echo"),
                    "GET", null, null, null, false);
        }

        JsonObject root = new JsonObject();
        root.add("redirectResults", arr);
        writeJson(outDir, "redirect_cases.json", root, "redirectResults");
        System.out.println("OkHttp 重定向/Cookie 链对照: " + arr.size() + " 条");
        return arr.size();
    }

    private static void addRedirectCase(JsonArray arr, ServerState state, String name, String base,
                                        String pathAndQuery, String method, String body,
                                        String bodyKind, Map<String, String> headers,
                                        boolean followRedirects) throws Exception {
        state.reset();
        OkHttpClient client = newClient(followRedirects, 20);
        Request.Builder rb = new Request.Builder().url(base + pathAndQuery);
        if ("POST".equals(method)) {
            if ("json".equals(bodyKind)) {
                rb.post(RequestBody.create(body.getBytes(StandardCharsets.UTF_8),
                        MediaType.get("application/json; charset=UTF-8")));
            } else {
                rb.post(RequestBody.create(body.getBytes(StandardCharsets.UTF_8),
                        MediaType.get("application/x-www-form-urlencoded")));
            }
        } else if ("HEAD".equals(method)) {
            rb.head();
        } else {
            rb.get();
        }
        addHeaders(rb, headers);

        JsonObject o = new JsonObject();
        o.addProperty("name", name);
        o.addProperty("kind", "redirect");
        o.addProperty("requestMethod", method);
        o.addProperty("requestUrl", base + pathAndQuery);
        o.addProperty("followRedirects", followRedirects);
        try {
            Response resp = client.newCall(rb.build()).execute();
            try (ResponseBody rb2 = resp.body()) {
                o.addProperty("responseCode", resp.code());
                if (rb2 != null) rb2.bytes();
                // 最终落地 URL（含重定向后的地址）
                o.addProperty("finalUrl", resp.request().url().toString());
            }
        } catch (Exception e) {
            o.addProperty("exception", e.getClass().getSimpleName() + ": " + e.getMessage());
        }
        fillServerView(o, state);
        arr.add(o);
    }

    // --------------------------------------------------------------- 用例 3：Cookie

    private static int runCookies(ServerState state, String outDir) throws Exception {
        JsonArray arr = new JsonArray();
        String base = "http://127.0.0.1:" + state.port;

        // 使用 OkHttp 默认（无 CookieJar）→ 不会自动回传 Cookie
        String[][] cases = {
                {"cookie-no-jar-single", "sid=abc123"},
                {"cookie-no-jar-multi", "a=1; b=2; c=3"},
                {"cookie-no-jar-chinese", "name=%E4%B8%AD%E6%96%87"},
                {"cookie-no-jar-empty-value", "k="},
                {"cookie-no-jar-path", "t=1; Path=/"},
                {"cookie-no-jar-expires", "t=1; Expires=Wed, 21 Oct 2099 07:28:00 GMT"},
                {"cookie-no-jar-domain", "t=1; Domain=127.0.0.1"},
                {"cookie-no-jar-secure", "t=1; Secure"},
                {"cookie-no-jar-httponly", "t=1; HttpOnly"},
                {"cookie-no-jar-samesite", "t=1; SameSite=Lax"},
        };
        for (String[] c : cases) {
            state.reset();
            OkHttpClient client = newClient(true);
            Request req1 = new Request.Builder()
                    .url(base + "/set-cookie?c=" + urlEncode(c[1])).build();
            JsonObject o = new JsonObject();
            o.addProperty("name", c[0]);
            o.addProperty("kind", "cookie");
            o.addProperty("setCookie", c[1]);
            try (Response r = client.newCall(req1).execute()) {
                o.addProperty("firstCode", r.code());
                r.body().bytes();
            }
            Request req2 = new Request.Builder().url(base + "/echo").build();
            try (Response r = client.newCall(req2).execute()) {
                o.addProperty("secondCode", r.code());
                r.body().bytes();
            }
            fillServerView(o, state);
            arr.add(o);
        }

        // CookieJar（内存实现，模拟 legado 的 CookieStore 行为）：第一次 Set-Cookie → 第二次自动带上
        for (String[] c : new String[][]{
                {"cookie-with-jar-single", "sid=abc123"},
                {"cookie-with-jar-multi", "a=1; b=2"},
                {"cookie-with-jar-path-root", "p=1; Path=/"},
        }) {
            state.reset();
            java.util.Map<String, List<okhttp3.Cookie>> store = new java.util.concurrent.ConcurrentHashMap<>();
            okhttp3.CookieJar jar = new okhttp3.CookieJar() {
                @Override public void saveFromResponse(okhttp3.HttpUrl url, List<okhttp3.Cookie> cookies) {
                    store.put(url.host(), new ArrayList<>(cookies));
                }
                @Override public List<okhttp3.Cookie> loadForRequest(okhttp3.HttpUrl url) {
                    return store.getOrDefault(url.host(), new ArrayList<>());
                }
            };
            OkHttpClient client = new OkHttpClient.Builder().cookieJar(jar)
                    .followRedirects(true).build();
            JsonObject o = new JsonObject();
            o.addProperty("name", c[0]);
            o.addProperty("kind", "cookie");
            o.addProperty("setCookie", c[1]);
            o.addProperty("withJar", true);
            try (Response r = client.newCall(new Request.Builder()
                    .url(base + "/set-cookie?c=" + urlEncode(c[1])).build()).execute()) {
                o.addProperty("firstCode", r.code());
                r.body().bytes();
            }
            try (Response r = client.newCall(new Request.Builder()
                    .url(base + "/echo").build()).execute()) {
                o.addProperty("secondCode", r.code());
                r.body().bytes();
            }
            fillServerView(o, state);
            arr.add(o);
        }

        JsonObject root = new JsonObject();
        root.add("cookieResults2", arr);
        writeJson(outDir, "request_cookie_cases.json", root, "cookieResults2");
        System.out.println("OkHttp Cookie 对照: " + arr.size() + " 条");
        return arr.size();
    }

    // --------------------------------------------------------------- 用例 4：自动头清单

    private static int runAutoHeaders(ServerState state, String outDir) throws Exception {
        JsonArray arr = new JsonArray();
        String base = "http://127.0.0.1:" + state.port;
        String[][] cases = {
                {"autoheaders-get", base + "/headers", "GET", null},
                {"autoheaders-post-form", base + "/headers", "POST", "a=1"},
                {"autoheaders-post-json", base + "/headers", "POST", "{\"k\":1}"},
                {"autoheaders-head", base + "/headers", "HEAD", null},
        };
        for (String[] c : cases) {
            state.reset();
            OkHttpClient client = newClient(true);
            Request.Builder rb = new Request.Builder().url(c[1]);
            if ("POST".equals(c[2])) {
                rb.post(RequestBody.create(c[3].getBytes(StandardCharsets.UTF_8),
                        MediaType.parse(c[3].startsWith("{")
                                ? "application/json; charset=UTF-8"
                                : "application/x-www-form-urlencoded")));
            } else if ("HEAD".equals(c[2])) {
                rb.head();
            } else {
                rb.get();
            }
            JsonObject o = new JsonObject();
            o.addProperty("name", c[0]);
            o.addProperty("kind", "autoHeaders");
            o.addProperty("requestMethod", c[2]);
            try (Response r = client.newCall(rb.build()).execute()) {
                o.addProperty("responseCode", r.code());
                r.body().bytes();
            }
            fillServerView(o, state);
            // 抽取出 OkHttp 自动加入的头名（服务器视角里的小写名）
            List<Recorded> all = new ArrayList<>();
            for (List<Recorded> v : state.records.values()) all.addAll(v);
            JsonArray auto = new JsonArray();
            if (!all.isEmpty()) {
                for (Map.Entry<String, String> e : all.get(0).allHeaders) {
                    if (OKHTTP_AUTO_HEADERS.contains(e.getKey().toLowerCase(java.util.Locale.ROOT))) {
                        auto.add(e.getKey());
                    }
                }
            }
            o.add("okhttpAutoHeaders", auto);
            arr.add(o);
        }
        JsonObject root = new JsonObject();
        root.add("autoHeaderResults", arr);
        writeJson(outDir, "auto_header_cases.json", root, "autoHeaderResults");
        System.out.println("OkHttp 自动头清单: " + arr.size() + " 条");
        return arr.size();
    }

    // --------------------------------------------------------------- 工具

    private static void writeJson(String outDir, String fileName, JsonObject root, String key)
            throws IOException {
        Gson gson = new GsonBuilder().disableHtmlEscaping().setPrettyPrinting().create();
        try (java.io.FileWriter w = new java.io.FileWriter(
                java.nio.file.Paths.get(outDir, fileName).toFile(), StandardCharsets.UTF_8)) {
            gson.toJson(root, w);
        }
    }

    /** multipart boundary 归一化：任何 {@code --xxx} 分隔符统一成 {@code --BOUNDARY--}。 */
    static String normalizeBoundary(String body) {
        if (body == null) return "";
        return body.replaceAll("(?m)--[0-9a-zA-Z]{16,}--", "--BOUNDARY----")
                .replaceAll("(?m)--[0-9a-zA-Z]{16,}", "--BOUNDARY--");
    }

    static Map<String, String> parseQuery(String raw) {
        Map<String, String> out = new LinkedHashMap<>();
        if (raw == null || raw.isEmpty()) return out;
        for (String pair : raw.split("&")) {
            if (pair.isEmpty()) continue;
            int eq = pair.indexOf('=');
            String k = eq >= 0 ? pair.substring(0, eq) : pair;
            String v = eq >= 0 ? pair.substring(eq + 1) : "";
            out.put(decodeUrl(k), decodeUrl(v));
        }
        return out;
    }

    static String decodeUrl(String s) {
        try {
            return java.net.URLDecoder.decode(s, StandardCharsets.UTF_8);
        } catch (Exception e) {
            return s;
        }
    }

    static String urlEncode(String s) {
        return java.net.URLEncoder.encode(s, StandardCharsets.UTF_8);
    }

    static String repeat(String s, int n) {
        StringBuilder sb = new StringBuilder(s.length() * n);
        for (int i = 0; i < n; i++) sb.append(s);
        return sb.toString();
    }
}
