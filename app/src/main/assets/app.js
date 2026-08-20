import { createIcons, Network, Upload, Download, Settings, MousePointer2, Menu, X, Plus, Minus, Maximize, Sparkles, GitFork, ShieldCheck, AlertTriangle, Building2, Globe2, Link2 } from 'lucide';
import { NetworkGraph } from './network.js';
import { LLMProvider } from './llm-provider.js';

const ICONS = { Network, Upload, Download, Settings, MousePointer2, Menu, X, Plus, Minus, Maximize, Sparkles, GitFork, ShieldCheck, AlertTriangle, Building2, Globe2, Link2 };
const $ = (id) => document.getElementById(id);
const state = { companies: [], links: [], summary: '', selected: null };
let graph;

const llm = new LLMProvider((text) => {
  $('ai-status').textContent = text || 'Arbeite …';
  if (!$('busy').classList.contains('hidden')) $('busy-text').textContent = text || 'Arbeite …';
});

function icons() {
  try { createIcons({ icons: ICONS }); } catch (e) { console.warn(e); }
}

function esc(value = '') {
  return String(value).replace(/[&<>'"]/g, (c) => ({'&':'&amp;','<':'&lt;','>':'&gt;',"'":'&#39;','"':'&quot;'}[c]));
}

function clamp(n, min = 0, max = 100) {
  n = Number(n);
  return Number.isFinite(n) ? Math.max(min, Math.min(max, n)) : 0;
}

function uid(prefix = 'c') {
  return `${prefix}_${Math.random().toString(36).slice(2, 9)}`;
}

function normalize(raw, targetName = '') {
  const srcCompanies = Array.isArray(raw?.companies) ? raw.companies : Array.isArray(raw?.nodes) ? raw.nodes : [];
  const ids = new Set();
  const companies = srcCompanies.slice(0, 30).map((c, i) => {
    let id = String(c.id || uid('c')).replace(/[^a-zA-Z0-9_-]/g, '_');
    while (ids.has(id)) id = uid('c');
    ids.add(id);
    return {
      id,
      name: String(c.name || (i === 0 ? targetName : `Entity ${i + 1}`)).trim(),
      type: ['main','parent','sister','subsidiary','partner','competitor','supplier'].includes(c.type) ? c.type : (i === 0 ? 'main' : 'partner'),
      country: String(c.country || ''),
      industry: String(c.industry || ''),
      description: String(c.description || c.summary || ''),
      risk: clamp(c.risk),
      confidence: clamp(c.confidence ?? 50),
      basis: String(c.basis || c.reason || 'KI-Hypothese; extern verifizieren.')
    };
  });
  if (companies.length && !companies.some(c => c.type === 'main')) companies[0].type = 'main';
  const valid = new Set(companies.map(c => c.id));
  const links = (Array.isArray(raw?.links) ? raw.links : []).slice(0, 60).map((l) => {
    const source = typeof l.source === 'object' ? l.source.id : l.source;
    const target = typeof l.target === 'object' ? l.target.id : l.target;
    return {
      source: String(source || ''), target: String(target || ''),
      type: ['parent','sister','subsidiary','partner','competitor','supplier'].includes(l.type) ? l.type : 'partner',
      label: String(l.label || l.relationship || ''), confidence: clamp(l.confidence ?? 50),
      basis: String(l.basis || l.reason || 'KI-Hypothese; extern verifizieren.')
    };
  }).filter(l => valid.has(l.source) && valid.has(l.target) && l.source !== l.target);
  return { companies, links, summary: String(raw?.summary || '') };
}

function serialize() {
  return {
    version: 1,
    app: 'CorpNet Insights Android',
    exportedAt: new Date().toISOString(),
    summary: state.summary,
    companies: state.companies.map(({x,y,vx,vy,fx,fy,index,...c}) => c),
    links: state.links.map(l => ({...l, source: typeof l.source === 'object' ? l.source.id : l.source, target: typeof l.target === 'object' ? l.target.id : l.target}))
  };
}

function persist() {
  try { localStorage.setItem('corpnet_last_network', JSON.stringify(serialize())); } catch (_) {}
}

function restore() {
  try {
    const raw = JSON.parse(localStorage.getItem('corpnet_last_network') || 'null');
    if (raw?.companies?.length) applyNetwork(raw, false);
  } catch (_) {}
}

function showBusy(show, text = 'Modell wird vorbereitet …') {
  $('busy').classList.toggle('hidden', !show);
  $('busy').classList.toggle('flex', show);
  $('busy-text').textContent = text;
}

function setSidebar(open) {
  $('sidebar').classList.toggle('-translate-x-full', !open);
}

async function refreshProvider() {
  try { $('provider').textContent = await llm.providerLabel(); }
  catch (_) { $('provider').textContent = 'LOCAL · WEBLLM'; }
}

function renderGraph() {
  $('empty-state').classList.toggle('hidden', state.companies.length > 0);
  if (!graph) graph = new NetworkGraph('network-container', selectCompany);
  graph.render(state.companies, state.links);
}

function relationCount(id) {
  return state.links.filter(l => (typeof l.source === 'object' ? l.source.id : l.source) === id || (typeof l.target === 'object' ? l.target.id : l.target) === id).length;
}

function selectCompany(company) {
  state.selected = company;
  const risk = clamp(company.risk);
  const confidence = clamp(company.confidence);
  $('details').innerHTML = `
    <div class="space-y-5">
      <div>
        <div class="mb-2 flex items-start justify-between gap-3">
          <div><div class="text-[10px] font-bold uppercase tracking-widest text-blue-400">${esc(company.type)}</div><h2 class="mt-1 text-xl font-bold text-white">${esc(company.name)}</h2></div>
          <div class="rounded-full border border-slate-700 bg-slate-900 px-2 py-1 text-[10px] text-slate-400">${relationCount(company.id)} Links</div>
        </div>
        <p class="text-sm leading-relaxed text-slate-400">${esc(company.description || 'Keine Beschreibung vorhanden.')}</p>
      </div>
      <div class="grid grid-cols-2 gap-2 text-xs">
        <div class="rounded-lg border border-slate-800 bg-slate-900 p-3"><div class="text-slate-500">Land</div><div class="mt-1 font-semibold">${esc(company.country || '—')}</div></div>
        <div class="rounded-lg border border-slate-800 bg-slate-900 p-3"><div class="text-slate-500">Branche</div><div class="mt-1 font-semibold">${esc(company.industry || '—')}</div></div>
      </div>
      <div class="space-y-3 rounded-lg border border-slate-800 bg-slate-900 p-4">
        <div><div class="flex justify-between text-[11px]"><span class="text-slate-400">KI-Konfidenz</span><span>${confidence}%</span></div><div class="mt-1 h-1.5 overflow-hidden rounded bg-slate-800"><div class="h-full bg-emerald-500" style="width:${confidence}%"></div></div></div>
        <div><div class="flex justify-between text-[11px]"><span class="text-slate-400">Risikoindikator</span><span>${risk}%</span></div><div class="mt-1 h-1.5 overflow-hidden rounded bg-slate-800"><div class="h-full bg-amber-500" style="width:${risk}%"></div></div></div>
      </div>
      <div class="rounded-lg border border-blue-900/40 bg-blue-950/30 p-4 text-xs leading-relaxed text-slate-300"><div class="mb-1 flex items-center gap-2 font-bold text-blue-300"><i data-lucide="shield-check" class="h-4 w-4"></i> Evidenzhinweis</div>${esc(company.basis)}</div>
      ${state.summary ? `<div><div class="mb-2 text-[10px] font-bold uppercase tracking-widest text-slate-500">Netzwerk-Summary</div><p class="text-xs leading-relaxed text-slate-400">${esc(state.summary)}</p></div>` : ''}
    </div>`;
  icons();
  if (innerWidth < 768) setSidebar(true);
}

function applyNetwork(raw, save = true) {
  const net = normalize(raw);
  state.companies = net.companies;
  state.links = net.links;
  state.summary = net.summary;
  state.selected = null;
  renderGraph();
  if (state.companies[0]) selectCompany(state.companies.find(c => c.type === 'main') || state.companies[0]);
  if (save) persist();
}

function extractJson(text) {
  const clean = String(text || '').trim().replace(/^```(?:json)?\s*/i, '').replace(/\s*```$/,'');
  try { return JSON.parse(clean); } catch (_) {}
  const start = clean.indexOf('{'), end = clean.lastIndexOf('}');
  if (start >= 0 && end > start) return JSON.parse(clean.slice(start, end + 1));
  throw new Error('Die KI-Antwort enthält kein gültiges JSON.');
}

async function analyze(name) {
  name = name.trim();
  if (!name) return;
  showBusy(true, 'KI-Engine wird gestartet …');
  $('ai-status').textContent = 'Analysiere …';
  try {
    const system = `Du bist CorpNet Insights, ein vorsichtiger Analyst für Unternehmensnetzwerke. Erzeuge ausschließlich plausible HYPOTHESEN aus deinem Modellwissen. Behaupte niemals, gerade live Handelsregister, Websites, News, LinkedIn oder APIs abgefragt zu haben. Kennzeichne Unsicherheit über confidence und basis. Keine erfundenen Quellen, URLs, Registereinträge oder exakten Beteiligungsquoten. Antworte NUR als gültiges JSON-Objekt ohne Markdown. Schema: {"companies":[{"id":"c1","name":"Name","type":"main|parent|sister|subsidiary|partner|competitor|supplier","country":"","industry":"","description":"","risk":0,"confidence":0,"basis":"warum diese Hypothese"}],"links":[{"source":"c1","target":"c2","type":"parent|sister|subsidiary|partner|competitor|supplier","label":"","confidence":0,"basis":""}],"summary":""}. Erzeuge 6 bis 14 sinnvolle Knoten. Der Zielknoten muss type=main sein.`;
    const user = `Analysiere das Unternehmensnetzwerk rund um: ${name}. Fokus auf bekannte oder plausible Konzern-, Tochter-, Schwester-, Partner-, Wettbewerber- und Lieferantenbeziehungen. Wenn du etwas nicht sicher weißt, senke confidence und schreibe das explizit in basis.`;
    const result = await llm.complete([{role:'system',content:system},{role:'user',content:user}], { json: true, maxTokens: 4200, temperature: 0.12 });
    const net = normalize(extractJson(result.content), name);
    if (!net.companies.length) throw new Error('Keine Entitäten erhalten.');
    applyNetwork(net);
    $('ai-status').textContent = `Bereit · ${result.model || result.provider}`;
    await refreshProvider();
  } catch (e) {
    console.error(e);
    $('ai-status').textContent = 'Fehler';
    alert(`Analyse fehlgeschlagen: ${e.message || e}`);
  } finally {
    showBusy(false);
  }
}

function exportData() {
  const text = JSON.stringify(serialize(), null, 2);
  const filename = `corpnet-${new Date().toISOString().slice(0,10)}.json`;
  if (window.AndroidAI?.saveExport) {
    window.AndroidAI.saveExport(text, filename);
    return;
  }
  const url = URL.createObjectURL(new Blob([text], {type:'application/json'}));
  const a = document.createElement('a'); a.href = url; a.download = filename; a.click();
  setTimeout(() => URL.revokeObjectURL(url), 500);
}

async function importFile(file) {
  try {
    const raw = JSON.parse(await file.text());
    applyNetwork(raw);
    $('ai-status').textContent = 'Import geladen';
  } catch (e) { alert(`Import fehlgeschlagen: ${e.message}`); }
}

function initConsent() {
  const accepted = localStorage.getItem('corpnet_consent') === 'accepted';
  $('consent').classList.toggle('hidden', accepted);
  $('consent').classList.toggle('flex', !accepted);
  $('consent-ok').addEventListener('click', () => {
    if (!$('consent-check').checked) { alert('Bitte bestätige den Hinweis.'); return; }
    localStorage.setItem('corpnet_consent','accepted');
    $('consent').classList.add('hidden'); $('consent').classList.remove('flex');
  });
}

function wire() {
  $('search-form').addEventListener('submit', (e) => { e.preventDefault(); analyze($('company-input').value); });
  $('settings-btn').addEventListener('click', () => llm.openSettings());
  $('export-btn').addEventListener('click', exportData);
  $('import-btn').addEventListener('click', () => $('file-input').click());
  $('file-input').addEventListener('change', (e) => { const f = e.target.files?.[0]; if (f) importFile(f); e.target.value=''; });
  $('zoom-in').addEventListener('click', () => graph?.zoomIn());
  $('zoom-out').addEventListener('click', () => graph?.zoomOut());
  $('reset-view').addEventListener('click', () => graph?.resetZoom());
  $('open-sidebar').addEventListener('click', () => setSidebar(true));
  $('close-sidebar').addEventListener('click', () => setSidebar(false));
  window.addEventListener('corpnet-settings-changed', refreshProvider);
}

function init() {
  icons(); initConsent(); wire(); refreshProvider(); restore();
  if (!state.companies.length) renderGraph();
}

init();
