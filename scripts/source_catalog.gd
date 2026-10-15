extends RefCounted
class_name SourceCatalog

const FILES := [
    "res://assets/sources_global.json",
    "res://assets/sources_europe.json",
    "res://assets/sources_americas.json",
    "res://assets/sources_apac.json",
    "res://assets/sources_mea.json"
]

static var _cache: Array = []

static func all_sources() -> Array:
    if not _cache.is_empty():
        return _cache
    for path in FILES:
        var text := FileAccess.get_file_as_string(path)
        if text.is_empty():
            continue
        var parsed = JSON.parse_string(text)
        if typeof(parsed) == TYPE_ARRAY:
            _cache.append_array(parsed)
    return _cache

static func by_id(source_id: String) -> Dictionary:
    for source in all_sources():
        if source.get("id") == source_id:
            return source
    return {}

static func prioritized(countries: Array = [], limit: int = 40) -> Array:
    var ranked := all_sources().duplicate(true)
    ranked.sort_custom(func(a, b):
        var a_bonus := 20 if _matches_country(a, countries) else 0
        var b_bonus := 20 if _matches_country(b, countries) else 0
        return int(a.get("priority", 0)) + a_bonus > int(b.get("priority", 0)) + b_bonus
    )
    return ranked.slice(0, min(limit, ranked.size()))

static func _matches_country(source: Dictionary, countries: Array) -> bool:
    if countries.is_empty():
        return false
    var source_countries: Array = source.get("countries", [])
    for country in countries:
        if source_countries.has(country):
            return true
    return false
