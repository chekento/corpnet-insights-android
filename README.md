# CorpNet Insights 3D — Godot Research Edition

CorpNet Insights is being rebuilt as a **native Godot 4.7 3D application**. The old WebView/Browser-LLM prototype remains in Git history, but this branch changes the product direction to **internet research first**.

## Product direction

- **Engine:** Godot 4.7.x
- **Primary UI:** interactive 3D company constellation
- **Default data mode:** live public-source internet research
- **Source catalog:** 200+ public registries, regulators, stock exchanges, procurement portals, sanctions lists, IP databases, open-data sources and news/open-web sources
- **Evidence model:** every finding carries source family, retrieval time, confidence and evidence count
- **Android-first:** GitHub Actions exports a debug APK directly from Godot

## Research model

The app does **not** claim perfect completeness. Corporate ownership, filings, sanctions, procurement and market information change continuously, and some national registers restrict automated access.

The research pipeline therefore distinguishes between:

1. **Direct keyless adapters** — GLEIF, SEC EDGAR, Wikidata, Wikipedia, GDELT and other machine-readable endpoints.
2. **Authoritative public portals** — national company registers, financial regulators, stock exchanges, sanctions, procurement and IP registers.
3. **Broad web discovery** — finds additional relationship signals and URLs.
4. **Source plan** — jurisdiction-aware ranking of the 200+ source catalog.

The UI exposes **Core**, **Deep** and **Exhaustive** research plans. A source being in the catalog does not mean it was queried successfully in a given run; the app separately reports planned sources and evidence sources actually returned.

## 3D experience

The Godot interface is designed as a corporate intelligence control room:

- glowing 3D nodes for companies and institutions
- animated rings and confidence-weighted relationship lines
- orbit/zoom camera
- data-grid floor and star-field environment
- left research console
- right evidence/detail panel
- source/evidence tabs
- mobile touch camera support

## Security and compliance

- No API key is required for the default research pipeline.
- Optional AI/provider integration can be added later without becoming the default.
- Do not treat inferred relationships as legal facts until verified against authoritative records.
- Use data minimization and a lawful basis when natural-person data appears in public corporate records.

## Branch

Development branch: `feature/godot-3d-research`

## Android build

The workflow `.github/workflows/godot-android.yml` downloads Godot 4.7.2 and matching export templates, validates the project, exports a debug APK and uploads it as an Actions artifact.

© KoSch / kosch.cloud.
