const DEFAULT_SETTINGS = {
  provider: 'local_webllm',
  localModel: 'Llama-3.2-1B-Instruct-q4f16_1-MLC',
  cloudModel: '',
  endpoint: '',
  customAuthHeader: 'Authorization',
  customAuthPrefix: 'Bearer ',
  allowHttp: false
};

let localEngine = null;
let localEngineModel = null;
let webllmModule = null;
let callbackCounter = 0;
const pending = new Map();

window.__corpnetAndroidResolve = (id, ok, payload) => {
  const item = pending.get(id);
  if (!item) return;
  pending.delete(id);
  if (ok) item.resolve(payload);
  else item.reject(new Error(payload || 'Android provider error'));
};

function androidBridge() {
  return typeof window.AndroidAI !== 'undefined' ? window.AndroidAI : null;
}

function normalizeSettings(raw) {
  return { ...DEFAULT_SETTINGS, ...(raw || {}) };
}

export class LLMProvider {
  constructor(onStatus = () => {}) {
    this.onStatus = onStatus;
  }

  async getSettings() {
    const bridge = androidBridge();
    if (bridge && typeof bridge.getSettings === 'function') {
      try {
        return normalizeSettings(JSON.parse(bridge.getSettings()));
      } catch (e) {
        console.warn('Could not read Android settings', e);
      }
    }
    try {
      return normalizeSettings(JSON.parse(localStorage.getItem('corpnet_llm_settings') || '{}'));
    } catch (_) {
      return { ...DEFAULT_SETTINGS };
    }
  }

  async providerLabel() {
    const s = await this.getSettings();
    const labels = {
      local_webllm: `LOCAL · ${this.shortModel(s.localModel)}`,
      openai: `OPENAI · ${s.cloudModel || 'default'}`,
      gemini: `GEMINI · ${s.cloudModel || 'default'}`,
      anthropic: `ANTHROPIC · ${s.cloudModel || 'default'}`,
      openrouter: `OPENROUTER · ${s.cloudModel || 'default'}`,
      custom: `CUSTOM · ${s.cloudModel || 'model'}`
    };
    return labels[s.provider] || s.provider;
  }

  shortModel(model) {
    if (!model) return 'WebLLM';
    return model.replace('-Instruct', '').replace('-q4f16_1-MLC', '').replace('-q4f32_1-MLC', '');
  }

  async isLocal() {
    return (await this.getSettings()).provider === 'local_webllm';
  }

  openSettings() {
    const bridge = androidBridge();
    if (bridge && typeof bridge.openSettings === 'function') {
      bridge.openSettings();
      return true;
    }
    alert('In der APK öffnet dieser Button die nativen KI-Einstellungen. Im Browser wird standardmäßig das lokale WebLLM verwendet.');
    return false;
  }

  async complete(messages, { json = false, maxTokens = 3800, temperature = 0.15 } = {}) {
    const settings = await this.getSettings();
    if (settings.provider === 'local_webllm') {
      return this.completeLocal(settings, messages, { json, maxTokens, temperature });
    }
    return this.completeAndroid(settings, messages, { json, maxTokens, temperature });
  }

  async completeLocal(settings, messages, opts) {
    if (!('gpu' in navigator)) {
      throw new Error('WebGPU ist in dieser WebView nicht verfügbar. Bitte Android System WebView/Chrome aktualisieren oder in den Einstellungen einen anderen Provider wählen.');
    }

    if (!webllmModule) {
      this.onStatus('Lade WebLLM Runtime…');
      webllmModule = await import('https://esm.run/@mlc-ai/web-llm@0.2.84');
    }

    const model = settings.localModel || DEFAULT_SETTINGS.localModel;
    if (!localEngine || localEngineModel !== model) {
      this.onStatus(`Lokales Modell wird geladen: ${this.shortModel(model)}…`);
      localEngine = await webllmModule.CreateMLCEngine(model, {
        initProgressCallback: (report) => this.onStatus(report?.text || 'Modell wird vorbereitet…')
      });
      localEngineModel = model;
      this.onStatus(`Lokales Modell bereit: ${this.shortModel(model)}`);
    }

    const request = {
      messages,
      temperature: opts.temperature,
      max_tokens: opts.maxTokens
    };
    if (opts.json) request.response_format = { type: 'json_object' };

    const result = await localEngine.chat.completions.create(request);
    const content = result?.choices?.[0]?.message?.content;
    if (!content) throw new Error('Das lokale Modell hat keine Antwort geliefert.');
    return { content, provider: 'local_webllm', model };
  }

  async completeAndroid(settings, messages, opts) {
    const bridge = androidBridge();
    if (!bridge || typeof bridge.complete !== 'function') {
      throw new Error('Cloud-Provider sind nur in der Android-App über die sichere native Bridge verfügbar.');
    }

    const id = `cb_${Date.now()}_${++callbackCounter}`;
    const payload = JSON.stringify({
      messages,
      json: !!opts.json,
      maxTokens: opts.maxTokens,
      temperature: opts.temperature
    });

    const raw = await new Promise((resolve, reject) => {
      pending.set(id, { resolve, reject });
      try {
        bridge.complete(payload, id);
      } catch (e) {
        pending.delete(id);
        reject(e);
      }
    });

    let parsed;
    try { parsed = JSON.parse(raw); } catch (_) { parsed = { content: raw }; }
    if (!parsed.content) throw new Error(parsed.error || 'Leere Provider-Antwort.');
    return parsed;
  }
}
