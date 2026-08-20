# Security

## API credentials

CorpNet Insights does **not** store API keys in JavaScript, WebView localStorage, source files, Gradle files, or GitHub.

In the Android app, provider keys are encrypted with AES/GCM using a non-exportable Android Keystore key. Ciphertext and IV are stored in private app preferences. The JavaScript layer can only ask the native bridge to perform a request; it cannot read a previously stored API key back.

For the custom provider, HTTPS is the default. Cleartext HTTP is accepted only after the user explicitly enables it and only for localhost or RFC1918 private-network hosts. Do not use HTTP on untrusted networks.

## Local WebLLM

The default provider is WebLLM and requires no API key. Model weights are downloaded from the configured WebLLM model source on first use and cached by Android System WebView. Local inference requires a WebGPU-capable Android System WebView / Chromium implementation.

## Reporting

Do not open a public issue containing credentials, private company data, or personal data. Remove secrets from logs before sharing diagnostics.
