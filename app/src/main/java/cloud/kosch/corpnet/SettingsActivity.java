package cloud.kosch.corpnet;

import android.app.Activity;
import android.graphics.Color;
import android.os.Bundle;
import android.text.InputType;
import android.view.View;
import android.widget.ArrayAdapter;
import android.widget.Button;
import android.widget.CheckBox;
import android.widget.EditText;
import android.widget.LinearLayout;
import android.widget.ScrollView;
import android.widget.Spinner;
import android.widget.TextView;
import android.widget.Toast;

public class SettingsActivity extends Activity {
    private static final String[] PROVIDER_LABELS = {
            "Lokal · Browser WebLLM (kein API-Key)",
            "OpenAI",
            "Google Gemini",
            "Anthropic Claude",
            "OpenRouter",
            "Custom · OpenAI-kompatibel"
    };
    private static final String[] PROVIDER_IDS = {
            "local_webllm", "openai", "gemini", "anthropic", "openrouter", "custom"
    };
    private static final String[] LOCAL_MODELS = {
            "Llama-3.2-1B-Instruct-q4f16_1-MLC",
            "SmolLM2-360M-Instruct-q4f16_1-MLC",
            "SmolLM2-1.7B-Instruct-q4f16_1-MLC",
            "Phi-3.5-mini-instruct-q4f16_1-MLC-1k"
    };

    private Spinner providerSpinner;
    private Spinner localModelSpinner;
    private EditText cloudModel;
    private EditText endpoint;
    private EditText apiKey;
    private EditText authHeader;
    private EditText authPrefix;
    private CheckBox allowHttp;
    private TextView keyStatus;

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        getWindow().setStatusBarColor(Color.rgb(2, 6, 23));
        getWindow().setNavigationBarColor(Color.rgb(2, 6, 23));
        setTitle("CorpNet · KI-Einstellungen");

        ScrollView scroll = new ScrollView(this);
        LinearLayout root = new LinearLayout(this);
        root.setOrientation(LinearLayout.VERTICAL);
        root.setPadding(dp(20), dp(18), dp(20), dp(28));
        root.setBackgroundColor(Color.rgb(15, 23, 42));
        scroll.addView(root);

        TextView title = text("KI-ENGINE", 22, Color.WHITE);
        title.setTypeface(null, android.graphics.Typeface.BOLD);
        root.addView(title);
        TextView intro = text("Standard ist ein lokales Browser-LLM über WebGPU. Dafür wird kein API-Key benötigt. Cloud-Keys werden ausschließlich im Android Keystore verschlüsselt gespeichert und nie an die Web-App zurückgegeben.", 13, Color.rgb(148, 163, 184));
        intro.setPadding(0, dp(6), 0, dp(18));
        root.addView(intro);

        root.addView(label("Provider"));
        providerSpinner = spinner(PROVIDER_LABELS);
        root.addView(providerSpinner);

        root.addView(label("Lokales WebLLM-Modell"));
        localModelSpinner = spinner(LOCAL_MODELS);
        root.addView(localModelSpinner);
        TextView localHint = text("Das Modell wird beim ersten Einsatz heruntergeladen und anschließend im WebView-Cache gehalten. Llama 3.2 1B ist die mobile Standardwahl.", 12, Color.rgb(100, 116, 139));
        localHint.setPadding(0, 0, 0, dp(14));
        root.addView(localHint);

        root.addView(label("Cloud-/Custom-Modell"));
        cloudModel = edit("z. B. gpt-5-mini, gemini-2.5-flash, eigener Modellname");
        root.addView(cloudModel);

        root.addView(label("API-Endpunkt (optional bei Presets)"));
        endpoint = edit("https://…");
        root.addView(endpoint);

        root.addView(label("API-Key"));
        apiKey = edit("Leer lassen = vorhandenen Key behalten");
        apiKey.setInputType(InputType.TYPE_CLASS_TEXT | InputType.TYPE_TEXT_VARIATION_PASSWORD);
        root.addView(apiKey);
        keyStatus = text("", 12, Color.rgb(52, 211, 153));
        keyStatus.setPadding(0, dp(4), 0, dp(8));
        root.addView(keyStatus);

        Button clearKey = button("Gespeicherten Key löschen");
        clearKey.setOnClickListener(v -> clearCurrentKey());
        root.addView(clearKey);

        root.addView(label("Custom Auth Header"));
        authHeader = edit("Authorization");
        root.addView(authHeader);
        root.addView(label("Custom Auth Prefix"));
        authPrefix = edit("Bearer ");
        root.addView(authPrefix);

        allowHttp = new CheckBox(this);
        allowHttp.setText("HTTP für localhost / privates LAN erlauben (unsicher)");
        allowHttp.setTextColor(Color.rgb(251, 191, 36));
        allowHttp.setPadding(0, dp(10), 0, dp(14));
        root.addView(allowHttp);

        TextView customHint = text("Custom verwendet das OpenAI-kompatible Chat-Completions-Format. Der API-Key ist optional; damit funktionieren auch selbst gehostete oder keylose kompatible Endpunkte. HTTP wird nur nach ausdrücklicher Freigabe und nur für localhost/private IP-Bereiche akzeptiert.", 12, Color.rgb(148, 163, 184));
        customHint.setPadding(0, 0, 0, dp(18));
        root.addView(customHint);

        Button save = button("Einstellungen speichern");
        save.setBackgroundColor(Color.rgb(37, 99, 235));
        save.setTextColor(Color.WHITE);
        save.setOnClickListener(v -> save());
        root.addView(save);

        Button cancel = button("Zurück");
        cancel.setOnClickListener(v -> finish());
        root.addView(cancel);

        providerSpinner.setOnItemSelectedListener(new android.widget.AdapterView.OnItemSelectedListener() {
            @Override public void onItemSelected(android.widget.AdapterView<?> parent, View view, int position, long id) { refreshKeyStatus(); }
            @Override public void onNothingSelected(android.widget.AdapterView<?> parent) {}
        });

        load();
        setContentView(scroll);
    }

    private void load() {
        String provider = AppSettings.provider(this);
        providerSpinner.setSelection(indexOf(PROVIDER_IDS, provider));
        localModelSpinner.setSelection(indexOf(LOCAL_MODELS, AppSettings.localModel(this)));
        cloudModel.setText(AppSettings.cloudModel(this));
        endpoint.setText(AppSettings.endpoint(this));
        authHeader.setText(AppSettings.authHeader(this));
        authPrefix.setText(AppSettings.authPrefix(this));
        allowHttp.setChecked(AppSettings.allowHttp(this));
        refreshKeyStatus();
    }

    private void save() {
        String provider = currentProvider();
        AppSettings.prefs(this).edit()
                .putString("provider", provider)
                .putString("localModel", LOCAL_MODELS[localModelSpinner.getSelectedItemPosition()])
                .putString("cloudModel", cloudModel.getText().toString().trim())
                .putString("endpoint", endpoint.getText().toString().trim())
                .putString("customAuthHeader", authHeader.getText().toString().trim())
                .putString("customAuthPrefix", authPrefix.getText().toString())
                .putBoolean("allowHttp", allowHttp.isChecked())
                .apply();
        String enteredKey = apiKey.getText().toString().trim();
        if (!enteredKey.isEmpty()) {
            try {
                SecureKeyStore.save(this, provider, enteredKey);
                apiKey.setText("");
            } catch (Exception e) {
                Toast.makeText(this, "Key konnte nicht gespeichert werden: " + e.getMessage(), Toast.LENGTH_LONG).show();
                return;
            }
        }
        Toast.makeText(this, "KI-Einstellungen gespeichert", Toast.LENGTH_SHORT).show();
        finish();
    }

    private void clearCurrentKey() {
        try {
            SecureKeyStore.save(this, currentProvider(), "");
            apiKey.setText("");
            refreshKeyStatus();
            Toast.makeText(this, "Key gelöscht", Toast.LENGTH_SHORT).show();
        } catch (Exception e) {
            Toast.makeText(this, "Key konnte nicht gelöscht werden", Toast.LENGTH_LONG).show();
        }
    }

    private void refreshKeyStatus() {
        if (keyStatus == null || providerSpinner == null) return;
        String p = currentProvider();
        if ("local_webllm".equals(p)) keyStatus.setText("Lokaler Provider: kein API-Key erforderlich.");
        else keyStatus.setText(SecureKeyStore.has(this, p) ? "✓ Für diesen Provider ist ein Key sicher gespeichert." : "Kein Key gespeichert. Bei Custom darf das absichtlich so sein.");
    }

    private String currentProvider() {
        int pos = providerSpinner.getSelectedItemPosition();
        return PROVIDER_IDS[Math.max(0, Math.min(pos, PROVIDER_IDS.length - 1))];
    }

    private Spinner spinner(String[] values) {
        Spinner s = new Spinner(this);
        ArrayAdapter<String> a = new ArrayAdapter<>(this, android.R.layout.simple_spinner_item, values);
        a.setDropDownViewResource(android.R.layout.simple_spinner_dropdown_item);
        s.setAdapter(a);
        s.setPadding(0, 0, 0, dp(10));
        return s;
    }

    private TextView label(String t) {
        TextView v = text(t, 12, Color.rgb(148, 163, 184));
        v.setTypeface(null, android.graphics.Typeface.BOLD);
        v.setPadding(0, dp(10), 0, dp(5));
        return v;
    }

    private EditText edit(String hint) {
        EditText e = new EditText(this);
        e.setHint(hint);
        e.setTextColor(Color.WHITE);
        e.setHintTextColor(Color.rgb(71, 85, 105));
        e.setSingleLine(true);
        e.setPadding(dp(10), dp(8), dp(10), dp(8));
        e.setBackgroundColor(Color.rgb(30, 41, 59));
        LinearLayout.LayoutParams lp = new LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, LinearLayout.LayoutParams.WRAP_CONTENT);
        lp.setMargins(0, 0, 0, dp(6));
        e.setLayoutParams(lp);
        return e;
    }

    private Button button(String t) {
        Button b = new Button(this);
        b.setText(t);
        LinearLayout.LayoutParams lp = new LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, LinearLayout.LayoutParams.WRAP_CONTENT);
        lp.setMargins(0, dp(6), 0, dp(6));
        b.setLayoutParams(lp);
        return b;
    }

    private TextView text(String t, int sp, int color) {
        TextView v = new TextView(this);
        v.setText(t);
        v.setTextSize(sp);
        v.setTextColor(color);
        return v;
    }

    private int dp(int v) { return Math.round(v * getResources().getDisplayMetrics().density); }
    private int indexOf(String[] arr, String value) {
        for (int i = 0; i < arr.length; i++) if (arr[i].equals(value)) return i;
        return 0;
    }
}
