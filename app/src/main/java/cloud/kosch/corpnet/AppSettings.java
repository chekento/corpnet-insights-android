package cloud.kosch.corpnet;

import android.content.Context;
import android.content.SharedPreferences;

import org.json.JSONObject;

public final class AppSettings {
    public static final String PREFS = "corpnet_ai_settings";
    public static final String DEFAULT_PROVIDER = "local_webllm";
    public static final String DEFAULT_LOCAL_MODEL = "Llama-3.2-1B-Instruct-q4f16_1-MLC";

    private AppSettings() {}

    public static SharedPreferences prefs(Context c) {
        return c.getSharedPreferences(PREFS, Context.MODE_PRIVATE);
    }

    public static String provider(Context c) { return prefs(c).getString("provider", DEFAULT_PROVIDER); }
    public static String localModel(Context c) { return prefs(c).getString("localModel", DEFAULT_LOCAL_MODEL); }
    public static String cloudModel(Context c) { return prefs(c).getString("cloudModel", ""); }
    public static String endpoint(Context c) { return prefs(c).getString("endpoint", ""); }
    public static String authHeader(Context c) { return prefs(c).getString("customAuthHeader", "Authorization"); }
    public static String authPrefix(Context c) { return prefs(c).getString("customAuthPrefix", "Bearer "); }
    public static boolean allowHttp(Context c) { return prefs(c).getBoolean("allowHttp", false); }

    public static String publicJson(Context c) {
        try {
            JSONObject o = new JSONObject();
            o.put("provider", provider(c));
            o.put("localModel", localModel(c));
            o.put("cloudModel", cloudModel(c));
            o.put("endpoint", endpoint(c));
            o.put("customAuthHeader", authHeader(c));
            o.put("customAuthPrefix", authPrefix(c));
            o.put("allowHttp", allowHttp(c));
            o.put("hasApiKey", SecureKeyStore.has(c, provider(c)));
            return o.toString();
        } catch (Exception e) {
            return "{}";
        }
    }
}
