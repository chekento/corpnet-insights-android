extends Node
class_name CompanyResolver

signal progress(message: String)

const USER_AGENT := "CorpNetInsights3D/0.3 (+https://github.com/chekento/corpnet-insights-android)"

func resolve(query: String) -> Array:
    query = query.strip_edges()
    if query.is_empty():
        return []

    progress.emit("Resolving legal entities …")
    var candidates: Array = []
    var gleif: Array = await _gleif_candidates(query)
    candidates.append_array(gleif)

    progress.emit("Checking market registrants …")
    var sec: Array = await _sec_candidates(query)
    candidates.append_array(sec)

    progress.emit("Checking public knowledge graph …")
    var wikidata: Array = await _wikidata_candidates(query)
    candidates.append_array(wikidata)

    progress.emit("Cross-checking public web identity …")
    var web: Array = await _web_candidates(query)
    candidates.append_array(web)

    return _merge_and_rank(candidates, query)

func _gleif_candidates(query: String) -> Array:
    var url := "https://api.gleif.org/api/v1/lei-records?filter[entity.legalName]=%s&page[size]=12" % query.uri_encode()
    var payload: Dictionary = await _request_json(url)
    var out: Array = []
    for record in payload.get("data", []):
        var attrs: Dictionary = record.get("attributes", {})
        var entity: Dictionary = attrs.get("entity", {})
        var legal_name: String = str(entity.get("legalName", {}).get("name", "")).strip_edges()
        if legal_name.is_empty():
            continue
        var legal_address: Dictionary = entity.get("legalAddress", {})
        var hq_address: Dictionary = entity.get("headquartersAddress", {})
        var city: String = str(hq_address.get("city", legal_address.get("city", "")))
        var country: String = str(entity.get("jurisdiction", legal_address.get("country", "")))
        var lei: String = str(attrs.get("lei", record.get("id", "")))
        out.append({
            "name": legal_name,
            "legal_name": legal_name,
            "country": country,
            "city": city,
            "registry_id": lei,
            "identifier_label": "LEI",
            "type": "Legal entity",
            "description": "GLEIF legal entity record",
            "source_ids": ["gleif"],
            "source_count": 1,
            "identity_score": 0.96 if legal_name.to_lower() == query.to_lower() else 0.88
        })
    return out

func _sec_candidates(query: String) -> Array:
    var url := "https://www.sec.gov/files/company_tickers.json"
    var payload: Dictionary = await _request_json(url)
    if payload.is_empty():
        return []
    var out: Array = []
    var q := query.to_lower()
    for key in payload.keys():
        var row: Dictionary = payload[key]
        var title: String = str(row.get("title", "")).strip_edges()
        if title.is_empty():
            continue
        var lt := title.to_lower()
        if lt.contains(q) or q.contains(lt):
            out.append({
                "name": title,
                "legal_name": title,
                "country": "US",
                "city": "",
                "registry_id": "CIK %010d" % int(row.get("cik_str", 0)),
                "ticker": str(row.get("ticker", "")),
                "identifier_label": "SEC",
                "type": "Public company",
                "description": "SEC registrant",
                "source_ids": ["us_sec"],
                "source_count": 1,
                "identity_score": 0.98 if lt == q else 0.86
            })
            if out.size() >= 10:
                break
    return out

func _wikidata_candidates(query: String) -> Array:
    var url := "https://www.wikidata.org/w/api.php?action=wbsearchentities&search=%s&language=en&limit=12&format=json" % query.uri_encode()
    var payload: Dictionary = await _request_json(url)
    var out: Array = []
    for item in payload.get("search", []):
        var label: String = str(item.get("label", "")).strip_edges()
        if label.is_empty():
            continue
        var description: String = str(item.get("description", ""))
        var score := 0.72
        if label.to_lower() == query.to_lower():
            score = 0.82
        out.append({
            "name": label,
            "legal_name": label,
            "country": "",
            "city": "",
            "registry_id": str(item.get("id", "")),
            "identifier_label": "Wikidata",
            "type": "Organisation candidate",
            "description": description,
            "source_ids": ["wikidata"],
            "source_count": 1,
            "identity_score": score
        })
    return out

func _web_candidates(query: String) -> Array:
    var q := ("%s company official registry headquarters" % query).uri_encode()
    var url := "https://duckduckgo.com/html/?q=%s" % q
    var body: String = await _request_text(url, "text/html")
    if body.is_empty():
        return []
    var regex := RegEx.new()
    regex.compile('<a[^>]*class="result__a"[^>]*href="([^"]+)"[^>]*>(.*?)</a>')
    var out: Array = []
    for match in regex.search_all(body).slice(0, 12):
        var title := _strip_tags(_html_unescape(match.get_string(2))).strip_edges()
        if title.is_empty():
            continue
        var candidate := _extract_candidate_name(title)
        if candidate.is_empty():
            continue
        out.append({
            "name": candidate,
            "legal_name": candidate,
            "country": "",
            "city": "",
            "registry_id": "",
            "identifier_label": "Web",
            "type": "Web candidate",
            "description": title,
            "source_ids": ["web_discovery"],
            "source_count": 1,
            "identity_score": 0.50
        })
    return out

func _merge_and_rank(candidates: Array, query: String) -> Array:
    var merged := {}
    for candidate in candidates:
        var name: String = str(candidate.get("legal_name", candidate.get("name", ""))).strip_edges()
        if name.is_empty():
            continue
        var key := _normalise_name(name)
        if not merged.has(key):
            merged[key] = candidate.duplicate(true)
            continue
        var existing: Dictionary = merged[key]
        existing["identity_score"] = min(0.995, max(float(existing.get("identity_score", 0.0)), float(candidate.get("identity_score", 0.0))) + 0.06)
        var ids: Array = existing.get("source_ids", [])
        for sid in candidate.get("source_ids", []):
            if not ids.has(sid):
                ids.append(sid)
        existing["source_ids"] = ids
        existing["source_count"] = ids.size()
        for field in ["country", "city", "registry_id", "ticker", "description", "type"]:
            if str(existing.get(field, "")).is_empty() and not str(candidate.get(field, "")).is_empty():
                existing[field] = candidate.get(field)

    var result: Array = merged.values()
    var qnorm := _normalise_name(query)
    for candidate in result:
        var name_norm := _normalise_name(str(candidate.get("legal_name", candidate.get("name", ""))))
        var lexical := _name_similarity(qnorm, name_norm)
        var source_bonus := min(0.12, float(candidate.get("source_count", 1) - 1) * 0.04)
        candidate["identity_score"] = min(0.995, float(candidate.get("identity_score", 0.5)) * 0.72 + lexical * 0.28 + source_bonus)
        candidate["verified"] = float(candidate.get("identity_score", 0.0)) >= 0.86 and (
            not str(candidate.get("registry_id", "")).is_empty()
            or int(candidate.get("source_count", 1)) >= 2
        )

    result.sort_custom(func(a, b):
        return float(a.get("identity_score", 0.0)) > float(b.get("identity_score", 0.0))
    )
    return result.slice(0, min(10, result.size()))

func _normalise_name(value: String) -> String:
    var s := value.to_lower()
    for suffix in [" corporation", " corp.", " corp", " incorporated", " inc.", " inc", " limited", " ltd.", " ltd", " gmbh", " ag", " s.a.", " sa", " plc", " llc", " se"]:
        if s.ends_with(suffix):
            s = s.trim_suffix(suffix)
    var regex := RegEx.new()
    regex.compile("[^a-z0-9]+")
    return regex.sub(s, "", true)

func _name_similarity(a: String, b: String) -> float:
    if a.is_empty() or b.is_empty():
        return 0.0
    if a == b:
        return 1.0
    if a.contains(b) or b.contains(a):
        return 0.88
    var common := 0
    for ch in a:
        if b.contains(ch):
            common += 1
    return float(common) / float(max(a.length(), b.length()))

func _request_json(url: String) -> Dictionary:
    var body := await _request_text(url, "application/json")
    if body.is_empty():
        return {}
    var parsed = JSON.parse_string(body)
    return parsed if typeof(parsed) == TYPE_DICTIONARY else {}

func _request_text(url: String, accept: String) -> String:
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
    var code: int = int(result[1])
    if code < 200 or code >= 300:
        return ""
    var body: PackedByteArray = result[3]
    return body.get_string_from_utf8()

func _extract_candidate_name(title: String) -> String:
    var clean := title
    for sep in [" - ", " | ", " — ", " – ", ": "]:
        if clean.contains(sep):
            clean = clean.split(sep)[0]
            break
    return clean.strip_edges().left(100)

func _strip_tags(text: String) -> String:
    var regex := RegEx.new()
    regex.compile("<[^>]*>")
    return regex.sub(text, "", true)

func _html_unescape(text: String) -> String:
    return text.replace("&amp;", "&").replace("&quot;", "\"").replace("&#39;", "'").replace("&lt;", "<").replace("&gt;", ">")
