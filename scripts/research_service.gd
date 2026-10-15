extends Node
class_name ResearchService

signal progress(done: int, total: int, message: String)

const USER_AGENT := "CorpNetInsights3D/0.4 (+https://github.com/chekento/corpnet-insights-android)"
const VERIFIED_RELATIONS := ["parent", "subsidiary", "partner", "supplier", "competitor", "investor", "acquisition"]
const AUTHORITATIVE_IDS := ["gleif", "us_sec", "uk_ch", "de_handelsregister", "de_unternehmensregister", "eu_ted"]

func research_company(company_name: String, scan_depth: int = 120) -> Dictionary:
    return await research_selected({
        "name": company_name,
        "legal_name": company_name,
        "verified": false,
        "registry_id": "",
        "source_ids": []
    }, scan_depth)

func research_selected(selected: Dictionary, scan_depth: int = 120) -> Dictionary:
    var legal_name: String = str(selected.get("legal_name", selected.get("name", ""))).strip_edges()
    var started_at := Time.get_datetime_string_from_system(true)
    if legal_name.is_empty():
        return _empty_result("Please select a company.", started_at)

    var findings: Array = []
    var sources_used: Array = []
    var jurisdictions: Array = []
    var total_steps := 9
    var step := 0

    progress.emit(step, total_steps, "Confirming selected legal identity …")
    var identity: Dictionary = await _confirm_identity(selected)
    step += 1
    if not identity.is_empty():
        findings.append_array(identity.get("findings", []))
        sources_used.append_array(identity.get("sources", []))
        jurisdictions.append_array(identity.get("jurisdictions", []))

    progress.emit(step, total_steps, "Resolving legal entity and ownership data …")
    var gleif: Dictionary = await _gleif_lookup(selected)
    step += 1
    if not gleif.is_empty():
        findings.append_array(gleif.get("findings", []))
        sources_used.append_array(gleif.get("sources", []))
        for jurisdiction in gleif.get("jurisdictions", []):
            if not jurisdictions.has(jurisdiction):
                jurisdictions.append(jurisdiction)

    progress.emit(step, total_steps, "Checking market registrants and filings …")
    var sec: Dictionary = await _sec_lookup(selected)
    step += 1
    if not sec.is_empty():
        findings.append_array(sec.get("findings", []))
        sources_used.append_array(sec.get("sources", []))
        if not jurisdictions.has("US"):
            jurisdictions.append("US")

    progress.emit(step, total_steps, "Loading public knowledge context …")
    var context: Dictionary = await _context_lookup(legal_name)
    step += 1
    if not context.is_empty():
        findings.append_array(context.get("findings", []))
        sources_used.append_array(context.get("sources", []))

    progress.emit(step, total_steps, "Scanning current news for explicit relationships …")
    var news: Dictionary = await _gdelt_search(legal_name)
    step += 1
    findings.append_array(news.get("findings", []))
    sources_used.append_array(news.get("sources", []))

    progress.emit(step, total_steps, "Running broad web relationship discovery …")
    var web: Dictionary = await _broad_relationship_search(legal_name)
    step += 1
    findings.append_array(web.get("findings", []))
    sources_used.append_array(web.get("sources", []))

    var planned_sources: Array = SourceCatalog.prioritized(jurisdictions, scan_depth)
    progress.emit(step, total_steps, "Checking high-priority authoritative portals …")
    var portal: Dictionary = await _targeted_portal_scan(legal_name, planned_sources, scan_depth)
    step += 1
    findings.append_array(portal.get("findings", []))
    sources_used.append_array(portal.get("sources", []))

    progress.emit(step, total_steps, "Cross-validating entities and rejecting weak matches …")
    var graph: Dictionary = _build_verified_network(selected, findings)
    step += 1

    progress.emit(step, total_steps, "Finalising evidence index …")
    var deduped_sources := _dedupe_sources(sources_used)
    graph["sources"] = deduped_sources
    graph["source_plan"] = planned_sources
    graph["catalog_size"] = SourceCatalog.all_sources().size()
    graph["queried_source_count"] = deduped_sources.size()
    graph["scan_depth"] = scan_depth
    graph["jurisdictions"] = jurisdictions
    graph["started_at"] = started_at
    graph["completed_at"] = Time.get_datetime_string_from_system(true)
    graph["selected_company"] = selected
    graph["identity_verified"] = bool(selected.get("verified", false)) or bool(identity.get("verified", false))
    graph["freshness_note"] = "Findings are time-stamped at retrieval. Corporate records can change after retrieval."
    step += 1
    progress.emit(total_steps, total_steps, "Verified research graph ready")
    return graph

func _confirm_identity(selected: Dictionary) -> Dictionary:
    var name: String = str(selected.get("legal_name", selected.get("name", "")))
    var findings: Array = [{
        "entity": name,
        "kind": "identity",
        "relation": "identity",
        "detail": "User-selected legal entity",
        "confidence": float(selected.get("identity_score", 0.90)),
        "source_id": str(selected.get("identifier_label", "resolver")),
        "authoritative": bool(selected.get("verified", false))
    }]
    return {
        "verified": bool(selected.get("verified", false)),
        "findings": findings,
        "sources": [],
        "jurisdictions": [str(selected.get("country", ""))] if not str(selected.get("country", "")).is_empty() else []
    }

func _gleif_lookup(selected: Dictionary) -> Dictionary:
    var legal_name: String = str(selected.get("legal_name", selected.get("name", "")))
    var registry_id: String = str(selected.get("registry_id", ""))
    var url: String
    if registry_id.length() == 20 and not registry_id.contains(" "):
        url = "https://api.gleif.org/api/v1/lei-records/%s" % registry_id.uri_encode()
    else:
        url = "https://api.gleif.org/api/v1/lei-records?filter[entity.legalName]=%s&page[size]=10" % legal_name.uri_encode()
    var payload: Dictionary = await _request_json(url)
    if payload.is_empty():
        return {}

    var records: Array = []
    if typeof(payload.get("data")) == TYPE_ARRAY:
        records = payload.get("data", [])
    elif typeof(payload.get("data")) == TYPE_DICTIONARY:
        records = [payload.get("data")]

    var findings: Array = []
    var sources: Array = []
    var jurisdictions: Array = []
    for record in records:
        var attrs: Dictionary = record.get("attributes", {})
        var entity: Dictionary = attrs.get("entity", {})
        var found_name: String = str(entity.get("legalName", {}).get("name", "")).strip_edges()
        if found_name.is_empty() or not _same_company_name(found_name, legal_name):
            continue
        var jurisdiction := str(entity.get("jurisdiction", ""))
        if not jurisdiction.is_empty() and not jurisdictions.has(jurisdiction):
            jurisdictions.append(jurisdiction)
        var lei := str(attrs.get("lei", record.get("id", "")))
        findings.append({
            "entity": legal_name,
            "kind": "legal_identity",
            "relation": "identity",
            "detail": "GLEIF confirms %s · LEI %s · jurisdiction %s" % [found_name, lei, jurisdiction],
            "confidence": 0.99,
            "source_id": "gleif",
            "authoritative": true
        })

        var relationships: Dictionary = record.get("relationships", {})
        for rel_key in ["direct-parent-relationship", "ultimate-parent-relationship"]:
            if not relationships.has(rel_key):
                continue
            var wrapper = relationships.get(rel_key)
            if typeof(wrapper) != TYPE_DICTIONARY:
                continue
            var rel_data: Dictionary = wrapper.get("data", {})
            var parent_lei: String = str(rel_data.get("id", ""))
            if parent_lei.is_empty():
                continue
            var parent_name: String = await _gleif_name_by_lei(parent_lei)
            if parent_name.is_empty():
                continue
            findings.append({
                "entity": parent_name,
                "kind": "ownership",
                "relation": "parent",
                "detail": "GLEIF %s" % rel_key.replace("-", " "),
                "confidence": 0.99,
                "source_id": "gleif",
                "authoritative": true
            })

    if not findings.is_empty():
        sources.append(_source_record("gleif", "GLEIF LEI", url, "GLEIF legal entity and relationship data", "registry"))
    return {"findings": findings, "sources": sources, "jurisdictions": jurisdictions}

func _gleif_name_by_lei(lei: String) -> String:
    var url := "https://api.gleif.org/api/v1/lei-records/%s" % lei.uri_encode()
    var payload: Dictionary = await _request_json(url)
    var data: Dictionary = payload.get("data", {})
    var attrs: Dictionary = data.get("attributes", {})
    return str(attrs.get("entity", {}).get("legalName", {}).get("name", "")).strip_edges()

func _sec_lookup(selected: Dictionary) -> Dictionary:
    var legal_name: String = str(selected.get("legal_name", selected.get("name", "")))
    var tickers_url := "https://www.sec.gov/files/company_tickers.json"
    var tickers: Dictionary = await _request_json(tickers_url)
    if tickers.is_empty():
        return {}
    var best: Dictionary = {}
    var target := _normalise_name(legal_name)
    for key in tickers.keys():
        var row: Dictionary = tickers[key]
        var title := str(row.get("title", ""))
        if _normalise_name(title) == target:
            best = row
            break
    if best.is_empty():
        return {}

    var cik := "%010d" % int(best.get("cik_str", 0))
    var submissions_url := "https://data.sec.gov/submissions/CIK%s.json" % cik
    var submissions: Dictionary = await _request_json(submissions_url)
    var recent_forms: Array = []
    var recent: Dictionary = submissions.get("filings", {}).get("recent", {})
    for form in recent.get("form", []).slice(0, min(16, recent.get("form", []).size())):
        if not recent_forms.has(form):
            recent_forms.append(form)

    return {
        "findings": [{
            "entity": legal_name,
            "kind": "public_company",
            "relation": "identity",
            "detail": "SEC registrant · CIK %s · ticker %s · recent forms %s" % [cik, best.get("ticker", ""), ", ".join(recent_forms)],
            "confidence": 0.99,
            "source_id": "us_sec",
            "authoritative": true
        }],
        "sources": [
            _source_record("us_sec", "SEC company index", tickers_url, "SEC registrant identity", "filing"),
            _source_record("us_sec", "SEC EDGAR submissions", submissions_url, "SEC submissions", "filing")
        ]
    }

func _context_lookup(company_name: String) -> Dictionary:
    var findings: Array = []
    var sources: Array = []

    var wd_url := "https://www.wikidata.org/w/api.php?action=wbsearchentities&search=%s&language=en&limit=5&format=json" % company_name.uri_encode()
    var wd: Dictionary = await _request_json(wd_url)
    for item in wd.get("search", []):
        if _same_company_name(str(item.get("label", "")), company_name):
            findings.append({
                "entity": company_name,
                "kind": "context",
                "relation": "summary",
                "detail": str(item.get("description", "")),
                "confidence": 0.75,
                "source_id": "wikidata",
                "authoritative": false
            })
            sources.append(_source_record("wikidata", "Wikidata", wd_url, "Wikidata entity context", "knowledge"))
            break

    var wiki_url := "https://en.wikipedia.org/api/rest_v1/page/summary/%s" % company_name.replace(" ", "_").uri_encode()
    var wiki: Dictionary = await _request_json(wiki_url)
    var extract := str(wiki.get("extract", ""))
    if not extract.is_empty():
        findings.append({
            "entity": company_name,
            "kind": "context",
            "relation": "summary",
            "detail": extract,
            "confidence": 0.72,
            "source_id": "wikipedia",
            "authoritative": false
        })
        sources.append(_source_record("wikipedia", "Wikipedia", str(wiki.get("content_urls", {}).get("desktop", {}).get("page", wiki_url)), "Wikipedia summary", "knowledge"))
    return {"findings": findings, "sources": sources}

func _gdelt_search(company_name: String) -> Dictionary:
    var url := "https://api.gdeltproject.org/api/v2/doc/doc?query=%22%s%22&mode=ArtList&maxrecords=24&format=json&sort=HybridRel" % company_name.uri_encode()
    var payload: Dictionary = await _request_json(url)
    var findings: Array = []
    var sources: Array = []
    for article in payload.get("articles", []):
        var title := str(article.get("title", ""))
        var relation := _infer_relation(title)
        if not relation in VERIFIED_RELATIONS:
            continue
        var other := _extract_relation_entity(title, company_name)
        if other.is_empty():
            continue
        findings.append({
            "entity": other,
            "kind": "news",
            "relation": relation,
            "detail": title,
            "confidence": 0.62,
            "source_id": "gdelt",
            "authoritative": false
        })
        sources.append(_source_record("gdelt", str(article.get("domain", "GDELT article")), str(article.get("url", "")), title, "news"))
    return {"findings": findings, "sources": sources}

func _broad_relationship_search(company_name: String) -> Dictionary:
    var relation_terms := ["parent", "subsidiary", "partner", "supplier", "competitor", "investor", "acquisition"]
    var findings: Array = []
    var sources: Array = []
    for relation_term in relation_terms:
        var query := ("\"%s\" %s company" % [company_name, relation_term]).uri_encode()
        var search_url := "https://duckduckgo.com/html/?q=%s" % query
        var results := await _parse_ddg(search_url, 6)
        for item in results:
            var title: String = str(item.get("title", ""))
            var relation := _infer_relation(title)
            if relation != relation_term and not (relation_term == "acquisition" and relation == "acquisition"):
                continue
            var other := _extract_relation_entity(title, company_name)
            if other.is_empty():
                continue
            findings.append({
                "entity": other,
                "kind": "web",
                "relation": relation,
                "detail": title,
                "confidence": 0.58,
                "source_id": "web_discovery",
                "authoritative": false
            })
            sources.append(_source_record("web_discovery", "Public web discovery", str(item.get("url", "")), title, "web"))
    return {"findings": findings, "sources": sources}

func _targeted_portal_scan(company_name: String, planned_sources: Array, scan_depth: int) -> Dictionary:
    var request_cap := 8
    if scan_depth >= 100:
        request_cap = 18
    if scan_depth >= 200:
        request_cap = 30
    var findings: Array = []
    var sources: Array = []
    var checked := 0

    for source in planned_sources:
        if checked >= request_cap:
            break
        var source_id := str(source.get("id", ""))
        if source_id in ["gleif", "us_sec", "wikidata", "wikipedia", "gdelt"]:
            continue
        var domain := str(source.get("domain", ""))
        if domain.is_empty():
            continue
        checked += 1
        var query := ("\"%s\" site:%s" % [company_name, domain]).uri_encode()
        var search_url := "https://duckduckgo.com/html/?q=%s" % query
        var results := await _parse_ddg(search_url, 4)
        for item in results:
            var title: String = str(item.get("title", ""))
            var relation := _infer_relation(title)
            var is_authoritative := int(source.get("priority", 0)) >= 88 and str(source.get("category", "")) in ["company_registry", "filings", "financial_regulator", "procurement", "sanctions"]
            if relation in VERIFIED_RELATIONS:
                var other := _extract_relation_entity(title, company_name)
                if not other.is_empty():
                    findings.append({
                        "entity": other,
                        "kind": str(source.get("category", "portal")),
                        "relation": relation,
                        "detail": title,
                        "confidence": 0.84 if is_authoritative else 0.67,
                        "source_id": source_id,
                        "authoritative": is_authoritative
                    })
            elif _title_mentions_company(title, company_name):
                findings.append({
                    "entity": company_name,
                    "kind": str(source.get("category", "portal")),
                    "relation": "evidence",
                    "detail": title,
                    "confidence": 0.90 if is_authoritative else 0.68,
                    "source_id": source_id,
                    "authoritative": is_authoritative
                })
            sources.append(_source_record(source_id, str(source.get("name", source_id)), str(item.get("url", "")), title, str(source.get("category", "portal"))))
    return {"findings": findings, "sources": sources, "checked": checked}

func _build_verified_network(selected: Dictionary, findings: Array) -> Dictionary:
    var main_name: String = str(selected.get("legal_name", selected.get("name", "")))
    var main_id := _slugify(main_name)
    var main_context: Array = []
    var relationship_buckets := {}

    var main_evidence := 0
    for finding in findings:
        var relation: String = str(finding.get("relation", ""))
        var entity_name: String = str(finding.get("entity", "")).strip_edges()
        if entity_name.is_empty():
            continue
        if entity_name.to_lower() == main_name.to_lower() or relation in ["summary", "identity", "evidence"]:
            main_evidence += 1
            if relation in ["summary", "evidence"] and not str(finding.get("detail", "")).is_empty():
                main_context.append(str(finding.get("detail", "")))
            continue
        if not relation in VERIFIED_RELATIONS:
            continue
        if _same_company_name(entity_name, main_name):
            continue

        var key := "%s|%s" % [_normalise_name(entity_name), relation]
        if not relationship_buckets.has(key):
            relationship_buckets[key] = {
                "name": entity_name,
                "relation": relation,
                "details": [],
                "sources": [],
                "max_confidence": 0.0,
                "authoritative": false
            }
        var bucket: Dictionary = relationship_buckets[key]
        bucket["details"].append(str(finding.get("detail", "")))
        var sid := str(finding.get("source_id", ""))
        if not sid.is_empty() and not bucket["sources"].has(sid):
            bucket["sources"].append(sid)
        bucket["max_confidence"] = max(float(bucket.get("max_confidence", 0.0)), float(finding.get("confidence", 0.0)))
        bucket["authoritative"] = bool(bucket.get("authoritative", false)) or bool(finding.get("authoritative", false))

    var entities: Array = [{
        "id": main_id,
        "name": main_name,
        "type": "main",
        "description": _best_context(main_context),
        "confidence": 1.0 if bool(selected.get("verified", false)) else max(0.86, float(selected.get("identity_score", 0.86))),
        "evidence_count": main_evidence,
        "source_ids": selected.get("source_ids", [])
    }]
    var links: Array = []
    var rejected := 0

    for bucket in relationship_buckets.values():
        var source_count: int = bucket.get("sources", []).size()
        var authoritative: bool = bool(bucket.get("authoritative", false))
        var confidence: float = float(bucket.get("max_confidence", 0.0))
        var accepted := (authoritative and confidence >= 0.80) or (source_count >= 2 and confidence >= 0.58)
        if not accepted:
            rejected += 1
            continue
        var name: String = str(bucket.get("name", ""))
        var relation: String = str(bucket.get("relation", "related"))
        var eid := _slugify(name)
        var fused_confidence := min(0.99, confidence + max(0, source_count - 1) * 0.08)
        entities.append({
            "id": eid,
            "name": name,
            "type": _relation_to_type(relation),
            "description": _best_context(bucket.get("details", [])),
            "confidence": fused_confidence,
            "evidence_count": source_count,
            "source_ids": bucket.get("sources", []),
            "verified_relation": true
        })
        links.append({
            "source": main_id,
            "target": eid,
            "type": relation,
            "label": relation.replace("_", " "),
            "confidence": fused_confidence,
            "evidence_count": source_count
        })

    entities.sort_custom(func(a, b):
        if a.get("type") == "main":
            return true
        if b.get("type") == "main":
            return false
        return float(a.get("confidence", 0.0)) > float(b.get("confidence", 0.0))
    )
    if entities.size() > 30:
        entities = entities.slice(0, 30)
        var allowed := {}
        for entity in entities:
            allowed[entity.get("id")] = true
        links = links.filter(func(link): return allowed.has(link.get("source")) and allowed.has(link.get("target")))

    var summary := _best_context(main_context)
    if summary.is_empty():
        summary = "Identity resolved before analysis. Only cross-validated relationships are displayed."
    summary += "\n\n%d weak or ambiguous relationship candidates were rejected." % rejected

    return {
        "query": main_name,
        "summary": summary,
        "entities": entities,
        "links": links,
        "finding_count": findings.size(),
        "rejected_relationship_candidates": rejected
    }

func _parse_ddg(url: String, limit: int) -> Array:
    var body: String = await _request_text(url, "text/html")
    if body.is_empty():
        return []
    var regex := RegEx.new()
    regex.compile('<a[^>]*class="result__a"[^>]*href="([^"]+)"[^>]*>(.*?)</a>')
    var out: Array = []
    var matches := regex.search_all(body)
    for match in matches.slice(0, min(limit, matches.size())):
        var title := _strip_tags(_html_unescape(match.get_string(2))).strip_edges()
        if not title.is_empty():
            out.append({"title": title, "url": _html_unescape(match.get_string(1))})
    return out

func _extract_relation_entity(title: String, company_name: String) -> String:
    var clean := _strip_tags(title).strip_edges()
    var relation_words := ["subsidiary", "parent", "partner", "supplier", "competitor", "investor", "acquires", "acquired", "acquisition", "owned by", "partners with"]
    var lower := clean.to_lower()
    if not _title_mentions_company(clean, company_name):
        return ""
    for sep in [" - ", " | ", " — ", " – ", ": "]:
        if clean.contains(sep):
            var parts := clean.split(sep)
            for part in parts:
                var p := str(part).strip_edges()
                if not _same_company_name(p, company_name) and p.length() >= 3:
                    var p_lower := p.to_lower()
                    var is_relation_phrase := false
                    for rw in relation_words:
                        if p_lower == rw:
                            is_relation_phrase = true
                    if not is_relation_phrase:
                        return p.left(110)
    var company_pos := lower.find(company_name.to_lower())
    if company_pos >= 0:
        var before := clean.left(company_pos).strip_edges(" -:|")
        var after := clean.substr(company_pos + company_name.length()).strip_edges(" -:|")
        if before.length() >= 3 and before.length() <= 100:
            return before
        if after.length() >= 3 and after.length() <= 100:
            return after
    return ""

func _infer_relation(text: String) -> String:
    var t := text.to_lower()
    if t.contains("subsidiar") or t.contains("daughter company") or t.contains("owned subsidiary"):
        return "subsidiary"
    if t.contains("parent company") or t.contains("owned by") or t.contains("holding company"):
        return "parent"
    if t.contains("acquir") or t.contains("bought"):
        return "acquisition"
    if t.contains("investor") or t.contains("investment in") or t.contains("stake in"):
        return "investor"
    if t.contains("partner") or t.contains("alliance") or t.contains("collaboration"):
        return "partner"
    if t.contains("supplier") or t.contains("vendor") or t.contains("supply agreement"):
        return "supplier"
    if t.contains("competitor") or t.contains("rival"):
        return "competitor"
    return ""

func _relation_to_type(relation: String) -> String:
    if relation in ["parent", "subsidiary", "partner", "competitor", "supplier"]:
        return relation
    if relation in ["investor", "acquisition"]:
        return "ownership"
    return "related"

func _same_company_name(a: String, b: String) -> bool:
    var na := _normalise_name(a)
    var nb := _normalise_name(b)
    return not na.is_empty() and na == nb

func _title_mentions_company(title: String, company_name: String) -> bool:
    return _normalise_name(title).contains(_normalise_name(company_name))

func _normalise_name(value: String) -> String:
    var s := value.to_lower()
    var regex := RegEx.new()
    regex.compile("[^a-z0-9]+")
    return regex.sub(s, "", true)

func _best_context(items: Array) -> String:
    var seen := {}
    var usable: Array = []
    for item in items:
        var text := str(item).strip_edges()
        if text.is_empty() or seen.has(text):
            continue
        seen[text] = true
        usable.append(text)
        if usable.size() >= 4:
            break
    return "\n\n".join(usable)

func _request_json(url: String) -> Dictionary:
    var body: String = await _request_text(url, "application/json")
    if body.is_empty():
        return {}
    var parsed = JSON.parse_string(body)
    return parsed if typeof(parsed) == TYPE_DICTIONARY else {}

func _request_text(url: String, accept: String) -> String:
    var http := HTTPRequest.new()
    http.timeout = 18.0
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
    var response_code: int = int(result[1])
    if response_code < 200 or response_code >= 300:
        return ""
    var body: PackedByteArray = result[3]
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
