# CorpNet Insights — Company Network Mapper for Android

Android packaging of **CORPNET INTELLIGENCE by kosch.cloud** with a local, keyless AI engine as the default.

## AI architecture

**Default: Local Browser WebLLM — no API key.** The app runs the selected open model inside Android System WebView with WebGPU. The initial preset is `Llama-3.2-1B-Instruct-q4f16_1-MLC` and can be changed in the native Android settings.

Optional providers:

- OpenAI
- Google Gemini
- Anthropic Claude
- OpenRouter
- Custom OpenAI-compatible endpoint, including endpoints that intentionally require no API key

The provider and model can be changed from the gear icon in the app. The custom provider supports a custom endpoint, model name, auth header and auth prefix.

## Secure API-key handling

Cloud API keys are entered in a **native Android settings screen**. They are encrypted with AES/GCM using a non-exportable key held by **Android Keystore**. The browser/JavaScript layer does not get stored keys back. Cloud HTTP requests are executed by the native Android bridge, which attaches the credential internally.

No credential belongs in GitHub, JavaScript, localStorage, `BuildConfig`, or source control.

## Important data-quality note

The local WebLLM has no automatic live register/web-search capability. The application therefore no longer pretends that a live registry request happened when none did. Model-derived estimates should be treated as hypotheses and verified against authoritative sources before business, legal, compliance, credit, employment, or investment decisions.

The sidebar lists useful reference sources, but they are **not automatically queried** by the local model in this version.

## Android requirements

- Android 8.0+ (`minSdk 26`)
- Internet for first-time WebLLM runtime/model download and for optional cloud providers
- Current Android System WebView / Chrome with WebGPU support for local WebLLM
- More RAM/GPU memory is required for larger local models

## Build an installable APK

The repository includes `.github/workflows/android-apk.yml`.

1. Push the repository to GitHub.
2. Open **Actions → Build Android APK → Run workflow**, or push to `main`.
3. Open the completed workflow run.
4. Download the artifact **CorpNet-Insights-debug-apk**.
5. Install `app-debug.apk` on Android after allowing installation from the app you use to open the APK.

The workflow builds an installable debug APK. For Play Store/public release distribution, create a release keystore outside the repository and add a dedicated signed-release workflow using GitHub Actions secrets.

## Local build

Open the project in a current Android Studio, let Gradle sync, and build `app` with Java 17 / Android SDK 36.

## Project structure

- `app/src/main/assets/` — original CorpNet HTML/CSS/JS plus the new `llm-provider.js`
- `MainActivity.java` — secure HTTPS-like local asset origin, WebView bridge, import/export
- `SettingsActivity.java` — native model/provider/API settings
- `SecureKeyStore.java` — Android Keystore AES/GCM storage
- `CloudProviderClient.java` — native provider requests
- `.github/workflows/android-apk.yml` — reproducible APK build

## Privacy and compliance

The application can process company and person-related information. Use data minimization, purpose limitation, lawful processing and appropriate human verification. AI-generated risk scores are advisory estimates, not legal or financial determinations.

© KoSch / kosch.cloud. No license is granted unless explicitly added by the repository owner.
