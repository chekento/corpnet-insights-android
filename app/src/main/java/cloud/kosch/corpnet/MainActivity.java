package cloud.kosch.corpnet;

import android.app.Activity;
import android.content.Intent;
import android.graphics.Color;
import android.net.Uri;
import android.os.Bundle;
import android.webkit.JavascriptInterface;
import android.webkit.MimeTypeMap;
import android.webkit.ValueCallback;
import android.webkit.WebChromeClient;
import android.webkit.WebResourceRequest;
import android.webkit.WebResourceResponse;
import android.webkit.WebSettings;
import android.webkit.WebView;
import android.webkit.WebViewClient;
import android.widget.Toast;

import org.json.JSONObject;

import java.io.FileNotFoundException;
import java.io.InputStream;
import java.io.OutputStream;
import java.net.URLDecoder;
import java.nio.charset.StandardCharsets;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

public class MainActivity extends Activity {
    private static final int REQ_OPEN_FILE = 401;
    private static final int REQ_SAVE_FILE = 402;
    private static final String APP_ORIGIN = "https://appassets.androidplatform.net";

    private WebView webView;
    private ValueCallback<Uri[]> fileChooserCallback;
    private String pendingExportContent;
    private String pendingExportName;
    private final ExecutorService executor = Executors.newSingleThreadExecutor();

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        getWindow().setStatusBarColor(Color.rgb(2, 6, 23));
        getWindow().setNavigationBarColor(Color.rgb(2, 6, 23));

        webView = new WebView(this);
        setContentView(webView);

        WebSettings s = webView.getSettings();
        s.setJavaScriptEnabled(true);
        s.setDomStorageEnabled(true);
        s.setDatabaseEnabled(true);
        s.setAllowFileAccess(false);
        s.setAllowContentAccess(true);
        s.setMediaPlaybackRequiresUserGesture(false);
        s.setBuiltInZoomControls(false);
        s.setDisplayZoomControls(false);
        s.setCacheMode(WebSettings.LOAD_DEFAULT);
        s.setUserAgentString(s.getUserAgentString() + " CorpNetInsights/1.0");

        WebView.setWebContentsDebuggingEnabled(BuildConfig.DEBUG);
        webView.addJavascriptInterface(new AndroidAIBridge(), "AndroidAI");
        webView.setWebViewClient(new AssetClient());
        webView.setWebChromeClient(new WebChromeClient() {
            @Override
            public boolean onShowFileChooser(WebView view, ValueCallback<Uri[]> callback, FileChooserParams params) {
                if (fileChooserCallback != null) fileChooserCallback.onReceiveValue(null);
                fileChooserCallback = callback;
                Intent intent = new Intent(Intent.ACTION_OPEN_DOCUMENT);
                intent.addCategory(Intent.CATEGORY_OPENABLE);
                intent.setType("application/json");
                try {
                    startActivityForResult(intent, REQ_OPEN_FILE);
                    return true;
                } catch (Exception e) {
                    fileChooserCallback = null;
                    return false;
                }
            }
        });

        webView.loadUrl(APP_ORIGIN + "/index.html");
    }

    @Override
    protected void onResume() {
        super.onResume();
        if (webView != null) {
            webView.postDelayed(() -> webView.evaluateJavascript(
                    "window.dispatchEvent(new Event('corpnet-settings-changed'));", null), 250);
        }
    }

    @Override
    public void onBackPressed() {
        if (webView != null && webView.canGoBack()) webView.goBack();
        else super.onBackPressed();
    }

    @Override
    protected void onDestroy() {
        executor.shutdownNow();
        if (webView != null) webView.destroy();
        super.onDestroy();
    }

    @Override
    protected void onActivityResult(int requestCode, int resultCode, Intent data) {
        super.onActivityResult(requestCode, resultCode, data);
        if (requestCode == REQ_OPEN_FILE) {
            if (fileChooserCallback != null) {
                Uri[] result = null;
                if (resultCode == RESULT_OK && data != null && data.getData() != null) {
                    result = new Uri[]{data.getData()};
                }
                fileChooserCallback.onReceiveValue(result);
                fileChooserCallback = null;
            }
            return;
        }
        if (requestCode == REQ_SAVE_FILE) {
            if (resultCode == RESULT_OK && data != null && data.getData() != null && pendingExportContent != null) {
                try (OutputStream out = getContentResolver().openOutputStream(data.getData())) {
                    if (out != null) out.write(pendingExportContent.getBytes(StandardCharsets.UTF_8));
                    Toast.makeText(this, "Export gespeichert", Toast.LENGTH_SHORT).show();
                } catch (Exception e) {
                    Toast.makeText(this, "Export fehlgeschlagen: " + e.getMessage(), Toast.LENGTH_LONG).show();
                }
            }
            pendingExportContent = null;
            pendingExportName = null;
        }
    }

    private final class AndroidAIBridge {
        @JavascriptInterface
        public String getSettings() {
            return AppSettings.publicJson(MainActivity.this);
        }

        @JavascriptInterface
        public void openSettings() {
            runOnUiThread(() -> startActivity(new Intent(MainActivity.this, SettingsActivity.class)));
        }

        @JavascriptInterface
        public void complete(String requestJson, String callbackId) {
            executor.execute(() -> {
                try {
                    String response = CloudProviderClient.complete(MainActivity.this, requestJson);
                    resolveJs(callbackId, true, response);
                } catch (Exception e) {
                    resolveJs(callbackId, false, e.getMessage() == null ? e.toString() : e.getMessage());
                }
            });
        }

        @JavascriptInterface
        public void saveExport(String content, String filename) {
            pendingExportContent = content;
            pendingExportName = filename == null || filename.isEmpty() ? "corpnet_intelligence.json" : filename;
            runOnUiThread(() -> {
                Intent intent = new Intent(Intent.ACTION_CREATE_DOCUMENT);
                intent.addCategory(Intent.CATEGORY_OPENABLE);
                intent.setType("application/json");
                intent.putExtra(Intent.EXTRA_TITLE, pendingExportName);
                startActivityForResult(intent, REQ_SAVE_FILE);
            });
        }

        @JavascriptInterface
        public String platformInfo() {
            try {
                return new JSONObject()
                        .put("android", true)
                        .put("sdk", android.os.Build.VERSION.SDK_INT)
                        .put("webViewPackage", WebView.getCurrentWebViewPackage() == null ? "unknown" : WebView.getCurrentWebViewPackage().versionName)
                        .toString();
            } catch (Exception e) {
                return "{}";
            }
        }
    }

    private void resolveJs(String callbackId, boolean ok, String payload) {
        runOnUiThread(() -> {
            String js = "window.__corpnetAndroidResolve(" + JSONObject.quote(callbackId) + "," + ok + "," + JSONObject.quote(payload == null ? "" : payload) + ");";
            webView.evaluateJavascript(js, null);
        });
    }

    private final class AssetClient extends WebViewClient {
        @Override
        public WebResourceResponse shouldInterceptRequest(WebView view, WebResourceRequest request) {
            Uri uri = request.getUrl();
            if (!"appassets.androidplatform.net".equalsIgnoreCase(uri.getHost())) return null;
            try {
                String path = URLDecoder.decode(uri.getPath(), "UTF-8");
                if (path == null || path.equals("/") || path.isEmpty()) path = "/index.html";
                if (path.contains("..")) return new WebResourceResponse("text/plain", "UTF-8", null);
                path = path.substring(1);
                InputStream in = getAssets().open(path);
                return new WebResourceResponse(mime(path), "UTF-8", in);
            } catch (FileNotFoundException e) {
                return null;
            } catch (Exception e) {
                return null;
            }
        }

        @Override
        public boolean shouldOverrideUrlLoading(WebView view, WebResourceRequest request) {
            Uri uri = request.getUrl();
            if ("appassets.androidplatform.net".equalsIgnoreCase(uri.getHost())) return false;
            if (!request.isForMainFrame()) return false;
            String scheme = uri.getScheme();
            if ("http".equalsIgnoreCase(scheme) || "https".equalsIgnoreCase(scheme)) {
                try { startActivity(new Intent(Intent.ACTION_VIEW, uri)); } catch (Exception ignored) {}
                return true;
            }
            return false;
        }

        private String mime(String path) {
            String ext = MimeTypeMap.getFileExtensionFromUrl(path);
            String guessed = MimeTypeMap.getSingleton().getMimeTypeFromExtension(ext);
            if (guessed != null) return guessed;
            if (path.endsWith(".js")) return "application/javascript";
            if (path.endsWith(".css")) return "text/css";
            if (path.endsWith(".html")) return "text/html";
            if (path.endsWith(".mp3")) return "audio/mpeg";
            return "application/octet-stream";
        }
    }
}
