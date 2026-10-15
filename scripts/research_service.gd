extends Node
class_name ResearchService

signal progress(done: int, total: int, message: String)

const USER_AGENT := "CorpNetInsights3D/0.2 (+https://github.com/chekento/corpnet-insights-android)"
const CORE_DIRECT_SOURCE_IDS := ["gleif", "wikidata", "wikipedia", "us_sec", "eu_ted", "gdelt"]

func research_company(company_name: String, scan_depth: int = 120) -> Dictionary:
    company_name = company_name.strip_edges()
    var started_at := Time.get_datetime_string_from_system(true)
    if company_name.is_empty():
        return _empty_result("Please provide a company name.", started_at)

    var findings: Array = []
    var sources_used: Array = []
    var jurisdictions: Array = []
    var total_steps := 8
    var step := 0

    progress.emit(step, total_steps, "Resolving legal identity with GLEIF …")
    var gleif := await _gleif_lookup(company_name)
    step += 1
    if not gleif.is_empty():
        findings.append_array(gleif.get("findings", []))
        sources_used.append_array(gleif.get("sources", []))
        jurisdictions.append_array(gleif.get("jurisdictions", []))

    var planned_sources := SourceCatalog.prioritized(jurisdictions, scan_depth)

    progress.emit(step, total_steps, "Checking Wikidata entity graph …")
    var wikidata := await _wikidata_search(company_name)
    step += 1
    if not wikidata.is_empty():
        findings.append_array(wikidata.get("findings", []))
        sources_used.append_array(wikidata.get("sources", []))

    progress.emit(step, total_steps, "Loading encyclopedic context …")
    var wiki := await _wikipedia_summary(company_name)
    step += 1
    if not wiki.is_empty():
        findings.append_array(wiki.get("findings", []))
        sources_used.append_array(wiki.get("sources", []))

    progress.emit(step, total_steps, "Checking SEC EDGAR identifiers and filings …")
    var sec := await _sec_lookup(company_name)
    step += 1
    if not sec.is_empty():
        findings.append_array(sec.get("findings", []))
        sources_used.append_array(sec.get("sources", []))
        if not jurisdictions.has("US"):
            jurisdictions.append("US")

    progress.emit(step, total_steps, "Scanning public news and web references …")
    var gdelt := await _gdelt_search(company_name)
    step += 1
    if not gdelt.is_empty():
        findings.append_array(gdelt.get("findings", []))
        sources_used.append_array(gdelt.get("sources", []))

    progress.emit(step, total_steps, "Running broad web discovery …")
    var web_results := await _duckduckgo_search(company_name)
    step += 1
    findings.append_array(_results_to_findings(web_results, "web_discovery"))
    for item in web_results:
        sources_used.append(_source_record("duckduckgo", "DuckDuckGo web discovery", item.get("url", ""), item.get("title", "Web result"), "web"))

    progress.emit(step, total_steps, "Verifying high-priority authoritative portals …")
    var portal_scan := await _targeted_portal_scan(company_name, planned_sources, scan_depth)
    step += 1
    findings.append_array(portal_scan.get("findings", []))
    sources_used.append_array(portal_scan.get("sources", []))

    progress.emit(step, total_steps, "Building evidence-weighted network …")
    step += 1

    var graph := _build_network(company_name, findings)
    graph["sources"] = _dedupe_sources(sources_used)
    graph["source_plan"] = planned_sources
    graph["catalog_size"] = SourceCatalog.all_sources().size()
    graph["queried_source_count"] = graph["sources"].size()
    graph["scan_depth"] = scan_depth
    graph["jurisdictions"] = jurisdictions
    graph["started_at"] = started_at
    graph["completed_at"] = Time.get_datetime_string_from_system(true)
    graph["freshness_note"] = "Every displayed finding is time-stamped at retrieval. Corporate ownership and filings can change after retrieval."
    progress.emit(total_steps, total_steps, "Research graph ready")
    return graph

func _gleif_lookup(company_name: String) -> Dictionary:
    var url := "https://api.gleif.org/api/v1/lei-records?filter[entity.legalName]=%s&page[size]=10" % company_name.uri_encode()
    var payload := await _request_json(url)
    if payload.is_empty() or not payload.has("data"):
        return {}
    var findings: Array = []
    var sources: Array = []
    var jurisdictions: Array = []
    for record in payload.get("data", []):
        var attrs: Dictionary = record.get("attributes", {})
        var entity: Dictionary = attrs.get("entity", {})
        var legal_name := str(entity.get("legalName", {}).get("name", ""))
        var jurisdiction := str(entity.get("jurisdiction", ""))
        var lei := str(attrs.get("lei", record.get("id", "")))
        if not jurisdiction.is_empty() and not jurisdictions.has(jurisdiction):
            jurisdictions.append(jurisdiction)
        findings.append({
            "entity": legal_name,
            "kind": "legal_identity",
            "relation": "identified_as",
            "detail": "LEI %s · jurisdiction %s" % [lei, jurisdiction],
            "confidence": 0.98,
            "source_id": "gleif"
        })
        var rels: Dictionary = record.get("relationships", {})
        for rel_key in ["direct-parent-relationship", "ultimate-parent-relationship"]:
            if rels.has(rel_key):
                var rel_wrapper = rels[rel_key]
                var rel_data: Dictionary = rel_wrapper.get("data", {}) if typeof(rel_wrapper) == TYPE_DICTIONARY else {}
                var parent_id := str(rel_data.get("id", ""))
                if not parent_id.is_empty():
                    findings.append({
                        "entity": parent_id,
                        "kind": "ownership",
                        "relation": "parent",
                        "detail": rel_key,
                        "confidence": 0.96,
                        "source_id": "gleif"
                    })
    if not findings.is_empty():
        sources.append(_source_record("gleif", "GLEIF LEI", url, "GLEIF legal entity search", "api"))
    return {"findings": findings, "sources": sources, "jurisdictions": jurisdictions}

func _wikidata_search(company_name: String) -> Dictionary:
    var url := "https://www.wikidata.org/w/api.php?action=wbsearchentities&search=%s&language=en&limit=8&format=json" % company_name.uri_encode()
    var payload := await _request_json(url)
    if payload.is_empty():
        return {}
    var findings: Array = []
    for item in payload.get("search", []):
        findings.append({
            "entity": str(item.get("label", "")),
            "kind": "knowledge_graph",
            "relation": "entity_match",
            "detail": str(item.get("description", "")),
            "confidence": 0.78,
            "source_id": "wikidata"
        })
    return {"findings": findings, "sources": [_source_record("wikidata", "Wikidata", url, "Wikidata entity search", "api")]}

func _wikipedia_summary(company_name: String) -> Dictionary:
    var title := company_name.replace(" ", "_").uri_encode()
    var url := "https://en.wikipedia.org/api/rest_v1/page/summary/%s" % title
    var payload := await _request_json(url)
    if payload.is_empty():
        return {}
    var extract := str(payload.get("extract", ""))
    if extract.is_empty():
        return {}
    return {
        "findings": [{
            "entity": company_name,
            "kind": "context",
            "relation": "summary",
            "detail": extract,
            "confidence": 0.72,
            "source_id": "wikipedia"
        }],
        "sources": [_source_record("wikipedia", "Wikipedia", str(payload.get("content_urls", {}).get("desktop", {}).get("page", url)), "Wikipedia summary", "api")]
    }

func _sec_lookup(company_name: String) -> Dictionary:
    var tickers_url := "https://www.sec.gov/files/company_tickers.json"
    var tickers := await _request_json(tickers_url)
    if tickers.is_empty():
        return {}
    var best: Dictionary = {}
    var target := company_name.to_lower()
    for key in tickers.keys():
        var row: Dictionary = tickers[key]
        var title := str(row.get("title", ""))
        if title.to_lower() == target:
            best = row
            break
        if best.is_empty() and title.to_lower().contains(target):
            best = row
    if best.is_empty():
        return {}
    var cik := "%010d" % int(best.get("cik_str", 0))
    var submissions_url := "https://data.sec.gov/submissions/CIK%s.json" % cik
    var submissions := await _request_json(submissions_url)
    var recent_forms: Array = []
    if not submissions.is_empty():
        var recent: Dictionary = submissions.get("filings", {}).get("recent", {})
        var forms: Array = recent.get("form", [])
        for form in forms.slice(0, min(12, forms.size())):
            if not recent_forms.has(form):
                recent_forms.append(form)
    return {
        "findings": [{
            "entity": str(best.get("title", company_name)),
            "kind": "public_company",
            "relation": "sec_registrant",
            "detail": "CIK %s · ticker %s · recent forms %s" % [cik, best.get("ticker", ""), ", ".join(recent_forms)],
            "confidence": 0.99,
            "source_id": "us_sec"
        }],
        "sources": [
            _source_record("us_sec", "SEC company tickers", tickers_url, "SEC registrant index", "api"),
            _source_record("us_sec", "SEC EDGAR submissions", submissions_url, "SEC submissions", "api")
        ]
    }

func _gdelt_search(company_name: String) -> Dictionary:
    var url := "https://api.gdeltproject.org/api/v2/doc/doc?query=%22%s%22&mode=ArtList&maxrecords=12&format=json&sort=HybridRel" % company_name.uri_encode()
    var payload := await _request_json(url)
    if payload.is_empty():
        return {}
    var findings: Array = []
    var sources: Array = []
    for article in payload.get("articles", []):
        var title := str(article.get("title", ""))
        var article_url := str(article.get("url", ""))
        if title.is_empty():
            continue
        findings.append({
            "entity": _extract_org_name(title, company_name),
            "kind": "news",
            "relation": "mentioned_with",
            "detail": title,
            "confidence": 0.48,
            "source_id": "gdelt"
        })
        sources.append(_source_record("gdelt", str(article.get("domain", "GDELT article")), article_url, title, "news"))
    return {"findings": findings, "sources": sources}

func _duckduckgo_search(company_name: String) -> Array:
    var query := ("%s company parent subsidiaries owners investors acquisitions partnerships competitors suppliers" % company_name).uri_encode()
    var url := "https://duckduckgo.com/html/?q=%s" % query
    var body := await _request_text(url)
    if body.is_empty():
        return []
    var results: Array = []
    var regex := RegEx.new()
    regex.compile('<a[^>]*class="result__a"[^>]*href="([^"]+)"[^>]*>(.*?)</a>')
    var matches := regex.search_all(body)
    for match in matches.slice(0, min(20, matches.size())):
        var href := _html_unescape(match.get_string(1))
        var title := _strip_tags(_html_unescape(match.get_string(2))).strip_edges()
        if not title.is_empty():
            results.append({"title": title, "url": href, "snippet": "Public web search result"})
    return results

func _targeted_portal_scan(company_name: String, planned_sources: Array, scan_depth: int) -> Dictionary:
    var request_cap := 8
    if scan_depth >= 100:
        request_cap = 16
    if scan_depth >= 200:
        request_cap = 24

    var findings: Array = []
    var sources: Array = []
    var checked := 0
    for source in planned_sources:
        if checked >= request_cap:
            break
        var source_id := str(source.get("id", ""))
        if source_id in CORE_DIRECT_SOURCE_IDS:
            continue
        var domain := str(source.get("domain", ""))
        if domain.is_empty():
            continue
        checked += 1
        var results := await _duckduckgo_site_search(company_name, source)
        for item in results:
            var title := str(item.get("title", ""))
            var candidate := _extract_org_name(title, company_name)
            if candidate.is_empty():
                candidate = company_name
            findings.append({
                "entity": candidate,
                "kind": str(source.get("category", "portal")),
                "relation": _infer_relation(title),
                "detail": title,
                "confidence": min(0.90, 0.45 + float(source.get("priority", 50)) / 250.0),
                "source_id": source_id
            })
            sources.append(_source_record(
                source_id,
                str(source.get("name", source_id)),
                str(item.get("url", "")),
                title,
                str(source.get("category", "portal"))
            ))
    return {"findings": findings, "sources": sources, "checked": checked}

func _duckduckgo_site_search(company_name: String, source: Dictionary) -> Array:
    var domain := str(source.get("domain", ""))
    var query := ("\"%s\" site:%s" % [company_name, domain]).uri_encode()
    var url := "https://duckduckgo.com/html/?q=%s" % query
    var body := await _request_text(url)
    if body.is_empty():
        return []
    var regex := RegEx.new()
    regex.compile('<a[^>]*class="result__a"[^>]*href="([^"]+)"[^>]*>(.*?)</a>')
    var results: Array = []
    var matches := regex.search_all(body)
    for match in matches.slice(0, min(3, matches.size())):
        var href := _html_unescape(match.get_string(1))
        var title := _strip_tags(_html_unescape(match.get_string(2))).strip_edges()
        if not title.is_empty():
            results.append({"title": title, "url": href})
    return results

func _results_to_findings(results: Array, kind: String) -> Array:
    var out: Array = []
    for item in results:
        var candidate := _extract_org_name(str(item.get("title", "")), "")
        if candidate.is_empty():
            continue
        out.append({
            "entity": candidate,
            "kind": kind,
            "relation": _infer_relation(str(item.get("title", ""))),
            "detail": str(item.get("title", "")),
            "confidence": 0.42,
            "source_id": "duckduckgo"
        })
    return out

func _build_network(query_name: String, findings: Array) -> Dictionary:
    var main_id := _slugify(query_name)
    var entities: Array = [{
        "id": main_id,
        "name": query_name,
        "type": "main",
        "description": "Primary researched entity",
        "confidence": 1.0,
        "evidence_count": 0
    }]
    var links: Array = []
    var index := {main_id: 0}
    var main_context: Array = []

    for finding in findings:
        var name := str(finding.get("entity", "")).strip_edges()
        if name.is_empty():
            continue
        if name.to_lower() == query_name.to_lower() or finding.get("relation") == "summary":
            main_context.append(str(finding.get("detail", "")))
            entities[0]["evidence_count"] = int(entities[0].get("evidence_count", 0)) + 1
            continue

        var eid := _slugify(name)
        if not index.has(eid):
            index[eid] = entities.size()
            entities.append({
                "id": eid,
                "name": name,
                "type": _relation_to_type(str(finding.get("relation", "related"))),
                "description": str(finding.get("detail", "")),
                "confidence": float(finding.get("confidence", 0.4)),
                "evidence_count": 1,
                "source_ids": [str(finding.get("source_id", ""))]
            })
        else:
            var idx: int = index[eid]
            entities[idx]["evidence_count"] = int(entities[idx].get("evidence_count", 0)) + 1
            entities[idx]["confidence"] = min(0.99, max(float(entities[idx].get("confidence", 0.0)), float(finding.get("confidence", 0.0))) + 0.03)
            var sids: Array = entities[idx].get("source_ids", [])
            var sid := str(finding.get("source_id", ""))
            if not sid.is_empty() and not sids.has(sid):
                sids.append(sid)
            entities[idx]["source_ids"] = sids

        var relation := str(finding.get("relation", "related"))
        var existing := false
        for link in links:
            if link.get("source") == main_id and link.get("target") == eid and link.get("type") == relation:
                existing = true
                link["evidence_count"] = int(link.get("evidence_count", 1)) + 1
                link["confidence"] = min(0.99, float(link.get("confidence", 0.4)) + 0.04)
                break
        if not existing:
            links.append({
                "source": main_id,
                "target": eid,
                "type": relation,
                "label": relation.replace("_", " "),
                "confidence": float(finding.get("confidence", 0.4)),
                "evidence_count": 1
            })

    entities.sort_custom(func(a, b):
        if a.get("type") == "main":
            return true
        if b.get("type") == "main":
            return false
        return int(a.get("evidence_count", 0)) > int(b.get("evidence_count", 0))
    )

    if entities.size() > 36:
        entities = entities.slice(0, 36)
        var allowed := {}
        for entity in entities:
            allowed[entity.get("id")] = true
        links = links.filter(func(link): return allowed.has(link.get("source")) and allowed.has(link.get("target")))

    var summary := "Research completed from live public sources. Inspect each entity and source before relying on the relationship."
    if not main_context.is_empty():
        summary = "

".join(main_context.slice(0, min(main_context.size(), 4)))

    return {
        "query": query_name,
        "summary": summary,
        "entities": entities,
        "links": links,
        "finding_count": findings.size()
    }

func _request_json(url: String) -> Dictionary:
    var body := await _request_text(url, "application/json")
    if body.is_empty():
        return {}
    var parsed = JSON.parse_string(body)
    return parsed if typeof(parsed) == TYPE_DICTIONARY else {}

func _request_text(url: String, accept: String = "text/html, application/json;q=0.9, */*;q=0.8") -> String:
    var http := HTTPRequest.new()
    http.timeout = 15.0
    add_child(http)
    var headers := PackedStringArray([
        "User-Agent: %s" % USER_AGENT,
        "Accept: %s" % accept
    ])
    var err := http.request(url, headers, HTTPClient.METHOD_GET)
    if err != OK:
        http.queue_free()
        return ""
    var result = await http.request_completed
    http.queue_free()
    if result.size() < 4:
        return ""
    var response_code: int = result[1]
    var body: PackedByteArray = result[3]
    if response_code < 200 or response_code >= 300:
        return ""
    return body.get_string_from_utf8()

func _source_record(id: String, name: String, url: String, title: String, evidence_type: String) -> Dictionary:
    return {
        "id": id,
        "name": name,
        "url": url,
        "title": title,
        "evidence_type": evidence_type,
        "retrieved_at": Time.get_datetime_string_from_system(true)
    }

func _dedupe_sources(items: Array) -> Array:
    var seen := {}
    var out: Array = []
    for item in items:
        var key := str(item.get("url", item.get("id", "")))
        if key.is_empty() or seen.has(key):
            continue
        seen[key] = true
        out.append(item)
    return out

func _empty_result(message: String, started_at: String) -> Dictionary:
    return {
        "query": "",
        "summary": message,
        "entities": [],
        "links": [],
        "sources": [],
        "source_plan": [],
        "catalog_size": SourceCatalog.all_sources().size(),
        "started_at": started_at,
        "completed_at": Time.get_datetime_string_from_system(true)
    }

func _extract_org_name(title: String, fallback: String) -> String:
    var clean := _strip_tags(title)
    for sep in [" - ", " | ", " — ", " – ", ": "]:
        if clean.contains(sep):
            clean = clean.split(sep)[0]
            break
    clean = clean.strip_edges()
    if not fallback.is_empty() and clean.to_lower() == fallback.to_lower():
        return ""
    if clean.length() > 120:
        clean = clean.left(120)
    return clean

func _infer_relation(text: String) -> String:
    var t := text.to_lower()
    if t.contains("subsidiar") or t.contains("daughter company"):
        return "subsidiary"
    if t.contains("acquir") or t.contains("bought"):
        return "acquisition"
    if t.contains("parent") or t.contains("owner") or t.contains("holding"):
        return "parent"
    if t.contains("invest") or t.contains("funding"):
        return "investor"
    if t.contains("partner") or t.contains("alliance"):
        return "partner"
    if t.contains("supplier") or t.contains("vendor"):
        return "supplier"
    if t.contains("competitor") or t.contains("rival"):
        return "competitor"
    return "related"

func _relation_to_type(relation: String) -> String:
    if relation in ["parent", "subsidiary", "partner", "competitor", "supplier"]:
        return relation
    if relation in ["investor", "acquisition"]:
        return "ownership"
    return "related"

func _slugify(value: String) -> String:
    var s := value.to_lower().strip_edges()
    var out := ""
    var allowed := "abcdefghijklmnopqrstuvwxyz0123456789"
    for ch in s:
        if allowed.contains(ch):
            out += ch
        elif ch in [" ", "-", "_"]:
            out += "_"
    return out if not out.is_empty() else "entity_%d" % Time.get_unix_time_from_system()

func _strip_tags(text: String) -> String:
    var regex := RegEx.new()
    regex.compile("<[^>]*>")
    return regex.sub(text, "", true)

func _html_unescape(text: String) -> String:
    return text.replace("&amp;", "&").replace("&quot;", "\"").replace("&#39;", "'").replace("&lt;", "<").replace("&gt;", ">")
