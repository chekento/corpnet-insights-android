package cloud.kosch.corpnet;

import android.content.Context;

import org.json.JSONArray;
import org.json.JSONObject;

import java.io.BufferedReader;
import java.io.InputStream;
import java.io.InputStreamReader;
import java.io.OutputStream;
import java.net.HttpURLConnection;
import java.net.URI;
import java.net.URL;
import java.nio.charset.StandardCharsets;

public final class CloudProviderClient {
    private CloudProviderClient() {}

    public static String complete(Context context, String requestJson) throws Exception {
        String provider = AppSettings.provider(context);
        JSONObject req = new JSONObject(requestJson);
        JSONArray messages = req.getJSONArray("messages");
        int maxTokens = req.optInt("maxTokens", 4096);
        double temperature = req.optDouble("temperature", 0.15);
        boolean json = req.optBoolean("json", false);

        switch (provider) {
            case "openai": return openAiCompatible(context, provider, defaultIfEmpty(AppSettings.endpoint(context), "https://api.openai.com/v1/chat/completions"), defaultIfEmpty(AppSettings.cloudModel(context), "gpt-5-mini"), messages, maxTokens, temperature, json, "Authorization", "Bearer ");
            case "openrouter": return openAiCompatible(context, provider, defaultIfEmpty(AppSettings.endpoint(context), "https://openrouter.ai/api/v1/chat/completions"), defaultIfEmpty(AppSettings.cloudModel(context), "openai/gpt-4.1-mini"), messages, maxTokens, temperature, json, "Authorization", "Bearer ");
            case "gemini": return gemini(context, messages, maxTokens, temperature, json);
            case "anthropic": return anthropic(context, messages, maxTokens, temperature);
            case "custom": return openAiCompatible(context, provider, AppSettings.endpoint(context), AppSettings.cloudModel(context), messages, maxTokens, temperature, json, AppSettings.authHeader(context), AppSettings.authPrefix(context));
            default: throw new IllegalStateException("Provider ist lokal und muss in WebLLM ausgeführt werden.");
        }
    }

    private static String openAiCompatible(Context c, String provider, String endpoint, String model,
                                           JSONArray messages, int maxTokens, double temperature, boolean json,
                                           String authHeader, String authPrefix) throws Exception {
        validateEndpoint(c, endpoint);
        if (model == null || model.isEmpty()) throw new IllegalArgumentException("Kein Modell konfiguriert.");
        JSONObject body = new JSONObject();
        body.put("model", model);
        body.put("messages", messages);
        body.put("temperature", temperature);
        body.put("max_tokens", maxTokens);
        if (json) body.put("response_format", new JSONObject().put("type", "json_object"));

        HttpURLConnection conn = connection(endpoint);
        String key = SecureKeyStore.load(c, provider);
        if (!key.isEmpty() && authHeader != null && !authHeader.trim().isEmpty()) {
            conn.setRequestProperty(authHeader.trim(), (authPrefix == null ? "" : authPrefix) + key);
        }
        if ("openrouter".equals(provider)) {
            conn.setRequestProperty("HTTP-Referer", "https://kosch.cloud");
            conn.setRequestProperty("X-Title", "CorpNet Insights Android");
        }
        JSONObject response = postJson(conn, body);
        JSONArray choices = response.optJSONArray("choices");
        if (choices == null || choices.length() == 0) throw new Exception("Provider-Antwort enthält keine choices.");
        String content = choices.getJSONObject(0).optJSONObject("message").optString("content", "");
        return result(content, provider, model);
    }

    private static String gemini(Context c, JSONArray messages, int maxTokens, double temperature, boolean json) throws Exception {
        String model = defaultIfEmpty(AppSettings.cloudModel(c), "gemini-2.5-flash");
        String endpoint = AppSettings.endpoint(c);
        if (endpoint == null || endpoint.isEmpty()) endpoint = "https://generativelanguage.googleapis.com/v1beta/models/" + model + ":generateContent";
        validateEndpoint(c, endpoint);

        JSONObject body = new JSONObject();
        JSONArray contents = new JSONArray();
        StringBuilder system = new StringBuilder();
        for (int i = 0; i < messages.length(); i++) {
            JSONObject m = messages.getJSONObject(i);
            String role = m.optString("role", "user");
            String content = m.optString("content", "");
            if ("system".equals(role)) { system.append(content).append('\n'); continue; }
            JSONObject item = new JSONObject();
            item.put("role", "assistant".equals(role) ? "model" : "user");
            item.put("parts", new JSONArray().put(new JSONObject().put("text", content)));
            contents.put(item);
        }
        if (system.length() > 0) body.put("systemInstruction", new JSONObject().put("parts", new JSONArray().put(new JSONObject().put("text", system.toString()))));
        body.put("contents", contents);
        JSONObject gen = new JSONObject().put("temperature", temperature).put("maxOutputTokens", maxTokens);
        if (json) gen.put("responseMimeType", "application/json");
        body.put("generationConfig", gen);

        HttpURLConnection conn = connection(endpoint);
        String key = SecureKeyStore.load(c, "gemini");
        if (!key.isEmpty()) conn.setRequestProperty("x-goog-api-key", key);
        JSONObject response = postJson(conn, body);
        JSONArray candidates = response.optJSONArray("candidates");
        if (candidates == null || candidates.length() == 0) throw new Exception("Gemini-Antwort enthält keine candidates.");
        JSONArray parts = candidates.getJSONObject(0).getJSONObject("content").getJSONArray("parts");
        StringBuilder out = new StringBuilder();
        for (int i = 0; i < parts.length(); i++) out.append(parts.getJSONObject(i).optString("text", ""));
        return result(out.toString(), "gemini", model);
    }

    private static String anthropic(Context c, JSONArray messages, int maxTokens, double temperature) throws Exception {
        String model = defaultIfEmpty(AppSettings.cloudModel(c), "claude-sonnet-4-5");
        String endpoint = defaultIfEmpty(AppSettings.endpoint(c), "https://api.anthropic.com/v1/messages");
        validateEndpoint(c, endpoint);
        JSONArray filtered = new JSONArray();
        StringBuilder system = new StringBuilder();
        for (int i = 0; i < messages.length(); i++) {
            JSONObject m = messages.getJSONObject(i);
            if ("system".equals(m.optString("role"))) system.append(m.optString("content")).append('\n');
            else filtered.put(m);
        }
        JSONObject body = new JSONObject()
                .put("model", model)
                .put("messages", filtered)
                .put("max_tokens", maxTokens)
                .put("temperature", temperature);
        if (system.length() > 0) body.put("system", system.toString());

        HttpURLConnection conn = connection(endpoint);
        String key = SecureKeyStore.load(c, "anthropic");
        if (!key.isEmpty()) conn.setRequestProperty("x-api-key", key);
        conn.setRequestProperty("anthropic-version", "2023-06-01");
        JSONObject response = postJson(conn, body);
        JSONArray content = response.optJSONArray("content");
        if (content == null || content.length() == 0) throw new Exception("Anthropic-Antwort enthält keinen Content.");
        StringBuilder out = new StringBuilder();
        for (int i = 0; i < content.length(); i++) if ("text".equals(content.getJSONObject(i).optString("type"))) out.append(content.getJSONObject(i).optString("text"));
        return result(out.toString(), "anthropic", model);
    }

    private static HttpURLConnection connection(String endpoint) throws Exception {
        HttpURLConnection conn = (HttpURLConnection) new URL(endpoint).openConnection();
        conn.setConnectTimeout(20000);
        conn.setReadTimeout(120000);
        conn.setRequestMethod("POST");
        conn.setDoOutput(true);
        conn.setRequestProperty("Content-Type", "application/json; charset=utf-8");
        conn.setRequestProperty("Accept", "application/json");
        return conn;
    }

    private static JSONObject postJson(HttpURLConnection conn, JSONObject body) throws Exception {
        try (OutputStream os = conn.getOutputStream()) {
            os.write(body.toString().getBytes(StandardCharsets.UTF_8));
        }
        int code = conn.getResponseCode();
        InputStream stream = code >= 200 && code < 300 ? conn.getInputStream() : conn.getErrorStream();
        String raw = read(stream);
        if (code < 200 || code >= 300) throw new Exception("HTTP " + code + ": " + truncate(raw, 700));
        return new JSONObject(raw);
    }

    private static String read(InputStream in) throws Exception {
        if (in == null) return "";
        StringBuilder sb = new StringBuilder();
        try (BufferedReader br = new BufferedReader(new InputStreamReader(in, StandardCharsets.UTF_8))) {
            String line; while ((line = br.readLine()) != null) sb.append(line);
        }
        return sb.toString();
    }

    private static void validateEndpoint(Context c, String endpoint) throws Exception {
        if (endpoint == null || endpoint.trim().isEmpty()) throw new IllegalArgumentException("Kein API-Endpunkt konfiguriert.");
        URI uri = new URI(endpoint.trim());
        String scheme = uri.getScheme();
        if ("https".equalsIgnoreCase(scheme)) return;
        if ("http".equalsIgnoreCase(scheme) && AppSettings.allowHttp(c) && isLocalHost(uri.getHost())) return;
        throw new SecurityException("Nur HTTPS ist erlaubt. HTTP kann optional ausschließlich für localhost/private LAN-Adressen freigegeben werden.");
    }

    private static boolean isLocalHost(String host) {
        if (host == null) return false;
        if (host.equals("localhost") || host.equals("127.0.0.1") || host.equals("10.0.2.2")) return true;
        return host.startsWith("10.") || host.startsWith("192.168.") || host.matches("172\\.(1[6-9]|2[0-9]|3[0-1])\\..*");
    }

    private static String result(String content, String provider, String model) throws Exception {
        return new JSONObject().put("content", content).put("provider", provider).put("model", model).toString();
    }

    private static String defaultIfEmpty(String v, String d) { return v == null || v.trim().isEmpty() ? d : v.trim(); }
    private static String truncate(String s, int n) { return s == null ? "" : (s.length() <= n ? s : s.substring(0, n) + "…"); }
}
