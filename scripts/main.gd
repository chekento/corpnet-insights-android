extends Node3D

const TYPE_COLORS := {
    "main": Color("1aa8ff"),
    "parent": Color("b54cff"),
    "subsidiary": Color("22e6a1"),
    "partner": Color("2997ff"),
    "competitor": Color("ff496c"),
    "supplier": Color("ff9f2f"),
    "ownership": Color("ff4fd8"),
    "related": Color("c1d9ff")
}

@onready var graph_root: Node3D = $GraphRoot
@onready var camera_rig: Node3D = $CameraRig
@onready var camera: Camera3D = $CameraRig/Camera3D
@onready var research_service: ResearchService = $ResearchService
@onready var company_resolver: CompanyResolver = $CompanyResolver

@onready var search_input: LineEdit = $CanvasLayer/RootUI/LeftPanel/LeftMargin/LeftVBox/SearchHBox/SearchInput
@onready var resolve_button: Button = $CanvasLayer/RootUI/LeftPanel/LeftMargin/LeftVBox/SearchHBox/ResolveButton
@onready var identity_status: Label = $CanvasLayer/RootUI/LeftPanel/LeftMargin/LeftVBox/IdentityStatus
@onready var selected_text: RichTextLabel = $CanvasLayer/RootUI/LeftPanel/LeftMargin/LeftVBox/SelectedCompany/SelectedMargin/SelectedText
@onready var scan_depth: OptionButton = $CanvasLayer/RootUI/LeftPanel/LeftMargin/LeftVBox/ScanDepth
@onready var research_button: Button = $CanvasLayer/RootUI/LeftPanel/LeftMargin/LeftVBox/ResearchButton
@onready var status_label: Label = $CanvasLayer/RootUI/LeftPanel/LeftMargin/LeftVBox/StatusLabel
@onready var coverage_label: Label = $CanvasLayer/RootUI/LeftPanel/LeftMargin/LeftVBox/CoverageLabel
@onready var summary_text: RichTextLabel = $CanvasLayer/RootUI/LeftPanel/LeftMargin/LeftVBox/ResultTabs/Summary/SummaryText
@onready var entity_list: ItemList = $CanvasLayer/RootUI/LeftPanel/LeftMargin/LeftVBox/ResultTabs/Entities/EntityList
@onready var source_list: ItemList = $CanvasLayer/RootUI/LeftPanel/LeftMargin/LeftVBox/ResultTabs/Evidence/SourceList

@onready var details_text: RichTextLabel = $CanvasLayer/RootUI/RightPanel/RightMargin/RightVBox/DetailsText
@onready var open_source_button: Button = $CanvasLayer/RootUI/RightPanel/RightMargin/RightVBox/OpenSourceButton

@onready var orbit_button: Button = $CanvasLayer/RootUI/GraphHint/HintMargin/HintVBox/NavHBox/OrbitButton
@onready var pan_button: Button = $CanvasLayer/RootUI/GraphHint/HintMargin/HintVBox/NavHBox/PanButton
@onready var zoom_in_button: Button = $CanvasLayer/RootUI/GraphHint/HintMargin/HintVBox/NavHBox/ZoomInButton
@onready var zoom_out_button: Button = $CanvasLayer/RootUI/GraphHint/HintMargin/HintVBox/NavHBox/ZoomOutButton
@onready var reset_button: Button = $CanvasLayer/RootUI/GraphHint/HintMargin/HintVBox/NavHBox/ResetButton

@onready var candidate_overlay: Control = $CanvasLayer/RootUI/CandidateOverlay
@onready var candidate_title: Label = $CanvasLayer/RootUI/CandidateOverlay/Center/Card/CardMargin/VBox/CandidateTitle
@onready var candidate_help: Label = $CanvasLayer/RootUI/CandidateOverlay/Center/Card/CardMargin/VBox/CandidateHelp
@onready var candidate_list: ItemList = $CanvasLayer/RootUI/CandidateOverlay/Center/Card/CardMargin/VBox/CandidateList
@onready var candidate_preview: RichTextLabel = $CanvasLayer/RootUI/CandidateOverlay/Center/Card/CardMargin/VBox/CandidatePreview
@onready var cancel_candidate: Button = $CanvasLayer/RootUI/CandidateOverlay/Center/Card/CardMargin/VBox/Actions/CancelCandidate
@onready var use_candidate: Button = $CanvasLayer/RootUI/CandidateOverlay/Center/Card/CardMargin/VBox/Actions/UseCandidate

var current_data: Dictionary = {}
var selected_company: Dictionary = {}
var candidate_results: Array = []
var candidate_selection := -1
var entity_index: Array = []
var source_index: Array = []
var selected_source_url := ""
var graph_nodes: Dictionary = {}
var selected_graph_id := ""

var yaw := 0.0
var pitch := -0.28
var distance := 15.0
var focus_point := Vector3.ZERO
var drag_active := false
var nav_mode := "orbit"
var time_value := 0.0

func _ready() -> void:
    _build_visual_environment()
    _style_ui()
    _connect_signals()
    coverage_label.text = "%d public sources catalogued · Deep mode plans 120" % SourceCatalog.all_sources().size()
    _seed_initial_graph()
    _update_camera()

func _connect_signals() -> void:
    resolve_button.pressed.connect(_resolve_company)
    search_input.text_submitted.connect(func(_text: String): _resolve_company())
    research_button.pressed.connect(_start_research)
    research_service.progress.connect(_on_research_progress)
    company_resolver.progress.connect(func(message: String): identity_status.text = message)

    candidate_list.item_selected.connect(_on_candidate_selected)
    candidate_list.item_activated.connect(func(index: int): _on_candidate_selected(index); _use_selected_candidate())
    cancel_candidate.pressed.connect(_close_candidate_overlay)
    use_candidate.pressed.connect(_use_selected_candidate)

    entity_list.item_selected.connect(_on_entity_selected)
    entity_list.item_activated.connect(_on_entity_selected)
    source_list.item_selected.connect(_on_source_selected)
    source_list.item_activated.connect(_on_source_activated)
    open_source_button.pressed.connect(_open_selected_source)

    orbit_button.pressed.connect(func(): _set_nav_mode("orbit"))
    pan_button.pressed.connect(func(): _set_nav_mode("pan"))
    zoom_in_button.pressed.connect(func(): _zoom(-1.8))
    zoom_out_button.pressed.connect(func(): _zoom(1.8))
    reset_button.pressed.connect(_reset_view)

func _process(delta: float) -> void:
    time_value += delta
    for node in graph_nodes.values():
        if is_instance_valid(node) and node is CorpGraphNode:
            node.animate(time_value)

func _resolve_company() -> void:
    var query := search_input.text.strip_edges()
    if query.is_empty():
        identity_status.text = "Enter a company or organisation name."
        return

    resolve_button.disabled = true
    research_button.disabled = true
    selected_company.clear()
    selected_text.text = "[color=#8099ac]Resolving company identity…[/color]"
    identity_status.text = "Searching legal identities, registrants and public records …"

    candidate_results = await company_resolver.resolve(query)
    resolve_button.disabled = false

    if candidate_results.is_empty():
        identity_status.text = "No reliable company candidates found. Try the full legal name, city, ticker or register ID."
        selected_text.text = "[color=#ff718d]No verified match selected[/color]"
        return

    if _can_auto_select(candidate_results):
        _select_company(candidate_results[0])
        identity_status.text = "Identity resolved with high confidence."
        return

    _show_candidate_overlay(query)

func _can_auto_select(results: Array) -> bool:
    if results.size() == 1:
        return bool(results[0].get("verified", false)) and float(results[0].get("identity_score", 0.0)) >= 0.92
    var first: Dictionary = results[0]
    var second: Dictionary = results[1]
    return bool(first.get("verified", false)) and float(first.get("identity_score", 0.0)) >= 0.96 and (
        float(first.get("identity_score", 0.0)) - float(second.get("identity_score", 0.0)) >= 0.12
    )

func _show_candidate_overlay(query: String) -> void:
    candidate_selection = -1
    candidate_list.clear()
    use_candidate.disabled = true
    candidate_overlay.visible = true
    candidate_title.text = "Multiple companies found for “%s”" % query
    candidate_help.text = "Select the exact legal entity. CorpNet will not mix similarly named companies into the analysis."
    candidate_preview.text = "[color=#90a8bc]Choose a result to inspect its identity evidence.[/color]"
    for candidate in candidate_results:
        var score := int(round(float(candidate.get("identity_score", 0.0)) * 100.0))
        var country := str(candidate.get("country", ""))
        var city := str(candidate.get("city", ""))
        var location := " · ".join([x for x in [country, city] if not x.is_empty()])
        var identifier := str(candidate.get("registry_id", ""))
        var ticker := str(candidate.get("ticker", ""))
        var suffix_parts: Array = []
        if not location.is_empty():
            suffix_parts.append(location)
        if not ticker.is_empty():
            suffix_parts.append("Ticker %s" % ticker)
        if not identifier.is_empty():
            suffix_parts.append(identifier)
        suffix_parts.append("%d%% match" % score)
        candidate_list.add_item("%s\n%s" % [
            candidate.get("legal_name", candidate.get("name", "Unknown")),
            "  •  ".join(suffix_parts)
        ])

func _on_candidate_selected(index: int) -> void:
    if index < 0 or index >= candidate_results.size():
        return
    candidate_selection = index
    use_candidate.disabled = false
    var candidate: Dictionary = candidate_results[index]
    var verified_text := "[color=#39efb5]Identity verified[/color]" if bool(candidate.get("verified", false)) else "[color=#ffbe55]Needs cautious verification[/color]"
    candidate_preview.text = "[b][font_size=20]%s[/font_size][/b]\n%s · %s\n%s\n[b]Identity score[/b] %.0f%% · [b]Sources[/b] %s" % [
        candidate.get("legal_name", candidate.get("name", "Unknown")),
        candidate.get("type", "Organisation"),
        candidate.get("description", ""),
        verified_text,
        float(candidate.get("identity_score", 0.0)) * 100.0,
        ", ".join(candidate.get("source_ids", []))
    ]

func _use_selected_candidate() -> void:
    if candidate_selection < 0 or candidate_selection >= candidate_results.size():
        return
    _select_company(candidate_results[candidate_selection])
    _close_candidate_overlay()

func _close_candidate_overlay() -> void:
    candidate_overlay.visible = false

func _select_company(company: Dictionary) -> void:
    selected_company = company.duplicate(true)
    var name := str(selected_company.get("legal_name", selected_company.get("name", "Unknown")))
    search_input.text = name
    research_button.disabled = false
    var score := float(selected_company.get("identity_score", 0.0)) * 100.0
    var verified := bool(selected_company.get("verified", false))
    var badge := "[color=#32f0b0]VERIFIED[/color]" if verified else "[color=#ffbd55]CAUTION[/color]"
    var meta_parts: Array = []
    for value in [
        str(selected_company.get("country", "")),
        str(selected_company.get("city", "")),
        str(selected_company.get("ticker", "")),
        str(selected_company.get("registry_id", ""))
    ]:
        if not value.is_empty():
            meta_parts.append(value)
    selected_text.text = "[b][font_size=20]%s[/font_size][/b]  %s\n%s\nIdentity match %.0f%%" % [
        name,
        badge,
        " · ".join(meta_parts),
        score
    ]
    identity_status.text = "Selected one legal entity. Full research will stay scoped to this company."

func _start_research() -> void:
    if selected_company.is_empty():
        _resolve_company()
        return

    research_button.disabled = true
    resolve_button.disabled = true
    var depth := int(scan_depth.get_selected_id())
    status_label.text = "Starting verified live research …"
    var result: Dictionary = await research_service.research_selected(selected_company, depth)
    _apply_data(result)
    research_button.disabled = false
    resolve_button.disabled = false
    status_label.text = "Research completed · %s" % result.get("completed_at", "")

func _on_research_progress(done: int, total: int, message: String) -> void:
    status_label.text = "%d/%d · %s" % [done, total, message]

func _apply_data(data: Dictionary) -> void:
    current_data = data
    var rejected := int(data.get("rejected_relationship_candidates", 0))
    var summary := str(data.get("summary", ""))
    var verified := bool(data.get("identity_verified", false))
    var identity_badge := "[color=#31efb0]Identity verified[/color]" if verified else "[color=#ffbd55]Identity partially verified[/color]"
    summary_text.text = "%s\n\n[b]Research summary[/b]\n%s\n\n[b]Evidence[/b] %s findings · %s sources returned\n[b]Quality filter[/b] %s weak/ambiguous relationships rejected\n[b]Plan[/b] %s sources selected from %s catalogued" % [
        identity_badge,
        summary,
        data.get("finding_count", 0),
        data.get("sources", []).size(),
        rejected,
        data.get("source_plan", []).size(),
        data.get("catalog_size", SourceCatalog.all_sources().size())
    ]
    coverage_label.text = "%s catalogued · %s planned · %s evidence sources returned" % [
        data.get("catalog_size", 0),
        data.get("source_plan", []).size(),
        data.get("sources", []).size()
    ]

    entity_index.clear()
    entity_list.clear()
    for entity in data.get("entities", []):
        entity_index.append(entity)
        entity_list.add_item("%s  ·  %s  ·  %.0f%%  ·  %sx evidence" % [
            entity.get("name", "Unknown"),
            entity.get("type", "related"),
            float(entity.get("confidence", 0.0)) * 100.0,
            entity.get("evidence_count", 0)
        ])

    source_index.clear()
    source_list.clear()
    for source in data.get("sources", []):
        source_index.append(source)
        source_list.add_item("%s\n%s" % [
            source.get("name", "Source"),
            source.get("title", "")
        ])

    _render_graph(data.get("entities", []), data.get("links", []))
    if not entity_index.is_empty():
        _show_entity(entity_index[0], true)
    selected_source_url = ""
    open_source_button.disabled = true

func _render_graph(entities: Array, links: Array) -> void:
    for child in graph_root.get_children():
        child.queue_free()
    graph_nodes.clear()
    selected_graph_id = ""
    focus_point = Vector3.ZERO

    var positions := {}
    var count := max(1, entities.size())
    for i in range(entities.size()):
        var entity: Dictionary = entities[i]
        var shell := 0 if i == 0 else 1 + int((i - 1) / 7)
        var local_index := 0 if i == 0 else (i - 1) % 7
        var radius := 0.0 if i == 0 else 3.8 + float(shell) * 2.7
        var angle := float(local_index) / 7.0 * TAU + float(shell) * 0.53
        var pos := Vector3(cos(angle) * radius, sin(angle * 1.6) * (1.0 + shell * 0.35), sin(angle) * radius)
        positions[str(entity.get("id", ""))] = pos
        var node := _make_node(entity, pos, i)
        graph_root.add_child(node)
        graph_nodes[str(entity.get("id", ""))] = node

    for link in links:
        var source_id := str(link.get("source", ""))
        var target_id := str(link.get("target", ""))
        if positions.has(source_id) and positions.has(target_id):
            graph_root.add_child(_make_connection(
                positions[source_id],
                positions[target_id],
                TYPE_COLORS.get(_visual_type(str(link.get("type", "related"))), Color.WHITE),
                float(link.get("confidence", 0.5))
            ))
            _add_link_label(
                (positions[source_id] + positions[target_id]) * 0.5,
                str(link.get("label", "")),
                TYPE_COLORS.get(_visual_type(str(link.get("type", "related"))), Color.WHITE)
            )

func _make_node(entity: Dictionary, position: Vector3, index: int) -> CorpGraphNode:
    var node := CorpGraphNode.new()
    node.position = position
    node.name = "Entity_%s" % str(entity.get("id", index))
    var type := _visual_type(str(entity.get("type", "related")))
    var radius := 0.75 if type == "main" else 0.34 + min(0.16, float(entity.get("evidence_count", 1)) * 0.022)
    node.configure(entity, radius, TYPE_COLORS.get(type, Color.WHITE), index)
    node.selected.connect(_on_graph_node_selected)
    node.hovered.connect(_on_graph_node_hovered)
    return node

func _make_connection(a: Vector3, b: Vector3, color: Color, confidence: float) -> MeshInstance3D:
    var mesh_instance := MeshInstance3D.new()
    var cylinder := CylinderMesh.new()
    var length := a.distance_to(b)
    var thickness := 0.018 + clamp(confidence, 0.0, 1.0) * 0.035
    cylinder.top_radius = thickness
    cylinder.bottom_radius = thickness
    cylinder.height = length
    cylinder.radial_segments = 10
    mesh_instance.mesh = cylinder

    var material := StandardMaterial3D.new()
    material.albedo_color = Color(color, 0.70)
    material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
    material.emission_enabled = true
    material.emission = color
    material.emission_energy_multiplier = 1.5 + confidence
    mesh_instance.material_override = material
    mesh_instance.position = (a + b) * 0.5
    mesh_instance.look_at(b, Vector3.UP)
    mesh_instance.rotate_object_local(Vector3.RIGHT, PI / 2.0)
    return mesh_instance

func _add_link_label(position: Vector3, text: String, color: Color) -> void:
    if text.is_empty():
        return
    var label := Label3D.new()
    label.text = text.capitalize()
    label.position = position + Vector3(0, 0.2, 0)
    label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
    label.font_size = 16
    label.outline_size = 6
    label.modulate = color.lightened(0.15)
    graph_root.add_child(label)

func _on_graph_node_selected(entity: Dictionary) -> void:
    _show_entity(entity, true)
    _focus_entity(entity)

func _on_graph_node_hovered(entity: Dictionary, active: bool) -> void:
    if active:
        status_label.text = "Node: %s · tap/click for evidence" % entity.get("name", "Entity")
    elif not current_data.is_empty():
        status_label.text = "Research ready · click nodes or evidence"

func _focus_entity(entity: Dictionary) -> void:
    var entity_id := str(entity.get("id", ""))
    if selected_graph_id != "" and graph_nodes.has(selected_graph_id):
        var previous = graph_nodes[selected_graph_id]
        if is_instance_valid(previous):
            previous.set_highlight(false)
    selected_graph_id = entity_id
    if graph_nodes.has(entity_id):
        var node: CorpGraphNode = graph_nodes[entity_id]
        node.set_highlight(true)
        focus_point = node.global_position
        distance = clamp(distance, 8.0, 14.0)
        _update_camera()

func _show_entity(entity: Dictionary, focus: bool = false) -> void:
    var source_ids: Array = entity.get("source_ids", [])
    var verified_relation := bool(entity.get("verified_relation", entity.get("type") == "main"))
    var quality := "[color=#32efb0]Verified relationship[/color]" if verified_relation else "[color=#ffbd55]Unverified[/color]"
    details_text.text = "[b][font_size=24]%s[/font_size][/b]\n[color=#54c8ff]%s[/color]\n\n%s\n\n[b]Confidence[/b] %.0f%%\n[b]Evidence[/b] %s independent source families\n[b]Source families[/b] %s\n\n[b]About / evidence[/b]\n%s" % [
        entity.get("name", "Entity"),
        str(entity.get("type", "related")).capitalize(),
        quality,
        float(entity.get("confidence", 0.0)) * 100.0,
        entity.get("evidence_count", 0),
        ", ".join(source_ids) if not source_ids.is_empty() else "—",
        entity.get("description", "No description available.")
    ]
    if focus:
        _focus_entity(entity)

func _on_entity_selected(index: int) -> void:
    if index >= 0 and index < entity_index.size():
        _show_entity(entity_index[index], true)

func _on_source_selected(index: int) -> void:
    if index < 0 or index >= source_index.size():
        return
    var source: Dictionary = source_index[index]
    selected_source_url = str(source.get("url", ""))
    open_source_button.disabled = selected_source_url.is_empty()
    details_text.text = "[b][font_size=22]%s[/font_size][/b]\n[color=#54c8ff]%s[/color]\n\n[b]Evidence type[/b] %s\n[b]Retrieved[/b] %s\n\n%s\n\n[color=#8ba9bd]%s[/color]" % [
        source.get("name", "Source"),
        source.get("evidence_type", "evidence"),
        source.get("evidence_type", "evidence"),
        source.get("retrieved_at", ""),
        source.get("title", ""),
        selected_source_url
    ]

func _on_source_activated(index: int) -> void:
    _on_source_selected(index)
    _open_selected_source()

func _open_selected_source() -> void:
    if not selected_source_url.is_empty():
        OS.shell_open(selected_source_url)

func _set_nav_mode(mode: String) -> void:
    nav_mode = mode
    orbit_button.button_pressed = mode == "orbit"
    pan_button.button_pressed = mode == "pan"

func _zoom(amount: float) -> void:
    distance = clamp(distance + amount, 4.5, 34.0)
    _update_camera()

func _reset_view() -> void:
    yaw = 0.0
    pitch = -0.28
    distance = 15.0
    focus_point = Vector3.ZERO
    if selected_graph_id != "" and graph_nodes.has(selected_graph_id):
        var node = graph_nodes[selected_graph_id]
        if is_instance_valid(node):
            node.set_highlight(false)
    selected_graph_id = ""
    _update_camera()

func _unhandled_input(event: InputEvent) -> void:
    if candidate_overlay.visible:
        return

    if event is InputEventMouseButton:
        if event.button_index == MOUSE_BUTTON_LEFT:
            drag_active = event.pressed
        elif event.button_index in [MOUSE_BUTTON_RIGHT, MOUSE_BUTTON_MIDDLE]:
            drag_active = event.pressed
            if event.pressed:
                nav_mode = "pan"
        elif event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
            _zoom(-1.0)
        elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
            _zoom(1.0)

    elif event is InputEventMouseMotion and drag_active:
        _navigate_drag(event.relative)

    elif event is InputEventScreenDrag:
        _navigate_drag(event.relative * 0.65)

func _navigate_drag(relative: Vector2) -> void:
    if nav_mode == "pan":
        var scale := distance * 0.0017
        var right := camera.global_transform.basis.x.normalized()
        var up := camera.global_transform.basis.y.normalized()
        focus_point += (-right * relative.x + up * relative.y) * scale
    else:
        yaw -= relative.x * 0.0065
        pitch = clamp(pitch - relative.y * 0.0065, -1.12, 0.30)
    _update_camera()

func _update_camera() -> void:
    camera_rig.position = focus_point
    camera_rig.rotation = Vector3(pitch, yaw, 0)
    camera.position = Vector3(0, 0.45, distance)

func _build_visual_environment() -> void:
    var floor := MeshInstance3D.new()
    var plane := PlaneMesh.new()
    plane.size = Vector2(70, 70)
    floor.mesh = plane
    floor.position.y = -3.0
    var floor_shader := Shader.new()
    floor_shader.code = """
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back;
uniform vec3 grid_color : source_color = vec3(0.02, 0.42, 0.72);
void fragment(){
    vec2 g = abs(fract(UV * 48.0 - 0.5) - 0.5) / fwidth(UV * 48.0);
    float line = 1.0 - min(min(g.x, g.y), 1.0);
    float radial = 1.0 - smoothstep(0.18, 0.72, distance(UV, vec2(0.5)));
    ALBEDO = grid_color * 0.16;
    EMISSION = grid_color * line * radial * 0.75;
    ALPHA = max(0.025, line * radial * 0.22);
}
"""
    var floor_material := ShaderMaterial.new()
    floor_material.shader = floor_shader
    floor.material_override = floor_material
    add_child(floor)

    var globe := MeshInstance3D.new()
    var sphere := SphereMesh.new()
    sphere.radius = 11.0
    sphere.height = 22.0
    sphere.radial_segments = 64
    sphere.rings = 32
    globe.mesh = sphere
    globe.position = Vector3(0, -7.8, -6.5)
    var globe_material := StandardMaterial3D.new()
    globe_material.albedo_color = Color(0.02, 0.32, 0.62, 0.045)
    globe_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
    globe_material.emission_enabled = true
    globe_material.emission = Color("0c5c9e")
    globe_material.emission_energy_multiplier = 0.22
    globe_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
    globe.material_override = globe_material
    add_child(globe)

    var stars := MultiMeshInstance3D.new()
    var mm := MultiMesh.new()
    mm.transform_format = MultiMesh.TRANSFORM_3D
    mm.instance_count = 320
    var star_mesh := SphereMesh.new()
    star_mesh.radius = 0.015
    star_mesh.height = 0.03
    star_mesh.radial_segments = 5
    star_mesh.rings = 3
    mm.mesh = star_mesh
    var rng := RandomNumberGenerator.new()
    rng.seed = 30042026
    for i in range(mm.instance_count):
        mm.set_instance_transform(i, Transform3D(Basis.IDENTITY, Vector3(
            rng.randf_range(-32.0, 32.0),
            rng.randf_range(-13.0, 19.0),
            rng.randf_range(-32.0, 18.0)
        )))
    stars.multimesh = mm
    var star_material := StandardMaterial3D.new()
    star_material.albedo_color = Color("7bd5ff")
    star_material.emission_enabled = true
    star_material.emission = Color("4ebcff")
    star_material.emission_energy_multiplier = 2.6
    stars.material_override = star_material
    add_child(stars)

func _style_ui() -> void:
    var root_ui: Control = $CanvasLayer/RootUI
    var panel_nodes := ["TopBar", "LeftPanel", "RightPanel", "GraphLegend", "GraphHint"]
    for path in panel_nodes:
        var panel: PanelContainer = root_ui.get_node(path)
        panel.add_theme_stylebox_override("panel", _panel_style(Color(0.012, 0.038, 0.078, 0.93), Color(0.08, 0.55, 0.90, 0.50), 16))

    var selected_panel: PanelContainer = $CanvasLayer/RootUI/LeftPanel/LeftMargin/LeftVBox/SelectedCompany
    selected_panel.add_theme_stylebox_override("panel", _panel_style(Color(0.02, 0.07, 0.12, 0.92), Color(0.11, 0.69, 0.98, 0.46), 12))

    var candidate_card: PanelContainer = $CanvasLayer/RootUI/CandidateOverlay/Center/Card
    candidate_card.add_theme_stylebox_override("panel", _panel_style(Color(0.008, 0.028, 0.065, 0.985), Color(0.26, 0.62, 1.0, 0.75), 20))

    var search_style := _panel_style(Color(0.008, 0.026, 0.055, 0.95), Color(0.10, 0.42, 0.68, 0.68), 10)
    search_input.add_theme_stylebox_override("normal", search_style)
    search_input.add_theme_color_override("font_color", Color("e6f6ff"))
    search_input.add_theme_color_override("font_placeholder_color", Color(0.52, 0.65, 0.76, 0.78))

    var primary_style := _panel_style(Color(0.03, 0.47, 0.72, 0.98), Color(0.28, 0.88, 1.0, 0.95), 10)
    research_button.add_theme_stylebox_override("normal", primary_style)
    research_button.add_theme_stylebox_override("hover", _panel_style(Color(0.15, 0.34, 0.78, 1.0), Color(0.75, 0.35, 1.0, 1.0), 10))
    use_candidate.add_theme_stylebox_override("normal", primary_style)

    $CanvasLayer/RootUI/TopBar/TopMargin/TopHBox/LiveStatus.add_theme_color_override("font_color", Color("41edbd"))
    $CanvasLayer/RootUI/TopBar/TopMargin/TopHBox/BrandVBox/Title.add_theme_color_override("font_color", Color("e9f8ff"))
    $CanvasLayer/RootUI/TopBar/TopMargin/TopHBox/BrandVBox/Subtitle.add_theme_color_override("font_color", Color("71b8df"))

    for button in [resolve_button, orbit_button, pan_button, zoom_in_button, zoom_out_button, reset_button, open_source_button]:
        button.add_theme_stylebox_override("normal", _panel_style(Color(0.02, 0.07, 0.12, 0.94), Color(0.08, 0.42, 0.68, 0.62), 9))
        button.add_theme_stylebox_override("hover", _panel_style(Color(0.03, 0.14, 0.22, 0.98), Color(0.16, 0.76, 1.0, 0.90), 9))

func _panel_style(background: Color, border: Color, radius: int) -> StyleBoxFlat:
    var style := StyleBoxFlat.new()
    style.bg_color = background
    style.border_color = border
    style.set_border_width_all(1)
    style.set_corner_radius_all(radius)
    style.shadow_color = Color(0, 0, 0, 0.42)
    style.shadow_size = 14
    style.content_margin_left = 8
    style.content_margin_right = 8
    style.content_margin_top = 7
    style.content_margin_bottom = 7
    return style

func _visual_type(value: String) -> String:
    if value in TYPE_COLORS:
        return value
    if value in ["acquisition", "investor"]:
        return "ownership"
    return "related"

func _seed_initial_graph() -> void:
    var demo := {
        "query": "CorpNet Demo",
        "summary": "Select a legal company identity to start verified live research.",
        "entities": [
            {"id":"corpnet","name":"Select a company","type":"main","description":"Search above to begin.","confidence":1.0,"evidence_count":0},
            {"id":"identity","name":"Identity resolution","type":"parent","description":"Disambiguation before research","confidence":1.0,"evidence_count":1},
            {"id":"evidence","name":"Verified evidence","type":"subsidiary","description":"Cross-validated sources","confidence":1.0,"evidence_count":1},
            {"id":"network","name":"3D relationships","type":"partner","description":"Clickable company network","confidence":1.0,"evidence_count":1}
        ],
        "links": [
            {"source":"corpnet","target":"identity","type":"parent","label":"resolve","confidence":0.9},
            {"source":"corpnet","target":"evidence","type":"subsidiary","label":"verify","confidence":0.9},
            {"source":"corpnet","target":"network","type":"partner","label":"explore","confidence":0.9}
        ]
    }
    _render_graph(demo.get("entities", []), demo.get("links", []))
