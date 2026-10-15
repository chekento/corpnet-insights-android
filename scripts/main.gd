extends Node3D

const TYPE_COLORS := {
    "main": Color("4cc9f0"),
    "parent": Color("f59e0b"),
    "subsidiary": Color("8b5cf6"),
    "partner": Color("22c55e"),
    "competitor": Color("ef4444"),
    "supplier": Color("94a3b8"),
    "ownership": Color("f97316"),
    "related": Color("7dd3fc")
}

@onready var graph_root: Node3D = $GraphRoot
@onready var camera_rig: Node3D = $CameraRig
@onready var camera: Camera3D = $CameraRig/Camera3D
@onready var research_service: ResearchService = $ResearchService
@onready var search_input: LineEdit = $CanvasLayer/RootUI/Sidebar/SidebarMargin/SidebarVBox/SearchInput
@onready var scan_depth: OptionButton = $CanvasLayer/RootUI/Sidebar/SidebarMargin/SidebarVBox/ScanDepth
@onready var search_button: Button = $CanvasLayer/RootUI/Sidebar/SidebarMargin/SidebarVBox/SearchButton
@onready var status_label: Label = $CanvasLayer/RootUI/Sidebar/SidebarMargin/SidebarVBox/StatusLabel
@onready var coverage_label: Label = $CanvasLayer/RootUI/Sidebar/SidebarMargin/SidebarVBox/CoverageLabel
@onready var summary_text: RichTextLabel = $CanvasLayer/RootUI/Sidebar/SidebarMargin/SidebarVBox/ResultTabs/SummaryTab/SummaryText
@onready var entity_list: ItemList = $CanvasLayer/RootUI/Sidebar/SidebarMargin/SidebarVBox/ResultTabs/EntitiesTab/EntityList
@onready var source_list: ItemList = $CanvasLayer/RootUI/Sidebar/SidebarMargin/SidebarVBox/ResultTabs/SourcesTab/SourceList
@onready var details_text: RichTextLabel = $CanvasLayer/RootUI/DetailsPanel/DetailsMargin/DetailsVBox/DetailsText

var current_data: Dictionary = {}
var entity_index: Array = []
var yaw := 0.0
var pitch := -0.35
var distance := 16.0
var dragging := false
var t := 0.0

func _ready() -> void:
    _build_visual_environment()
    _style_ui()
    search_button.pressed.connect(_on_search_pressed)
    search_input.text_submitted.connect(func(_text: String): _on_search_pressed())
    entity_list.item_selected.connect(_on_entity_selected)
    research_service.progress.connect(_on_research_progress)
    coverage_label.text = "%d public sources catalogued · Deep mode plans 120" % SourceCatalog.all_sources().size()
    seed_demo()
    _update_camera()

func _process(delta: float) -> void:
    t += delta
    graph_root.rotation.y += delta * 0.012
    for child in graph_root.get_children():
        if child.has_meta("corp_node"):
            var base_scale: float = float(child.get_meta("base_scale", 1.0))
            var phase: float = float(child.get_meta("phase", 0.0))
            var pulse: float = 1.0 + sin(t * 1.8 + phase) * 0.035
            child.scale = Vector3.ONE * base_scale * pulse

func seed_demo() -> void:
    var demo := {
        "query": "CorpNet Demo",
        "summary": "Godot 3D research workspace. Search a company to replace this demo with live public-source evidence.",
        "entities": [
            {"id":"corpnet","name":"CorpNet Demo","type":"main","description":"Anchor entity","confidence":0.95,"evidence_count":5},
            {"id":"alpha","name":"Alpha Holdings","type":"parent","description":"Ownership layer","confidence":0.84,"evidence_count":3},
            {"id":"beta","name":"Beta Labs","type":"subsidiary","description":"Operating subsidiary","confidence":0.77,"evidence_count":2},
            {"id":"gamma","name":"Gamma Partner","type":"partner","description":"Strategic partner","confidence":0.68,"evidence_count":2},
            {"id":"delta","name":"Delta Rival","type":"competitor","description":"Competitive signal","confidence":0.61,"evidence_count":2},
            {"id":"epsilon","name":"Epsilon Supplier","type":"supplier","description":"Supply relationship","confidence":0.58,"evidence_count":1}
        ],
        "links": [
            {"source":"corpnet","target":"alpha","type":"parent","label":"ownership","confidence":0.84},
            {"source":"corpnet","target":"beta","type":"subsidiary","label":"subsidiary","confidence":0.77},
            {"source":"corpnet","target":"gamma","type":"partner","label":"partner","confidence":0.68},
            {"source":"corpnet","target":"delta","type":"competitor","label":"competitor","confidence":0.61},
            {"source":"corpnet","target":"epsilon","type":"supplier","label":"supplier","confidence":0.58}
        ],
        "sources": [],
        "source_plan": SourceCatalog.prioritized([], 120),
        "catalog_size": SourceCatalog.all_sources().size()
    }
    _apply_data(demo)

func _on_search_pressed() -> void:
    var query := search_input.text.strip_edges()
    if query.is_empty():
        status_label.text = "Please enter a company name."
        return
    search_button.disabled = true
    var depth: int = int(scan_depth.get_selected_id())
    status_label.text = "Starting live internet research …"
    var result: Dictionary = await research_service.research_company(query, depth)
    _apply_data(result)
    search_button.disabled = false
    status_label.text = "Research completed · %s" % result.get("completed_at", "")

func _on_research_progress(done: int, total: int, message: String) -> void:
    status_label.text = "%d/%d · %s" % [done, total, message]

func _apply_data(data: Dictionary) -> void:
    current_data = data
    var summary := str(data.get("summary", ""))
    var footer := "\n\n[b]Evidence[/b] %s findings · %s queried results · %s-source plan / %s catalogued" % [
        data.get("finding_count", 0),
        data.get("queried_source_count", data.get("sources", []).size()),
        data.get("source_plan", []).size(),
        data.get("catalog_size", SourceCatalog.all_sources().size())
    ]
    summary_text.text = "[b]Research summary[/b]\n\n%s%s" % [summary, footer]
    coverage_label.text = "%s catalogued · %s planned · %s evidence sources returned" % [
        data.get("catalog_size", 0),
        data.get("source_plan", []).size(),
        data.get("sources", []).size()
    ]
    entity_list.clear()
    source_list.clear()
    entity_index.clear()
    for entity in data.get("entities", []):
        entity_index.append(entity)
        entity_list.add_item("%s  ·  %s  ·  %sx" % [entity.get("name", "Unknown"), entity.get("type", "related"), entity.get("evidence_count", 0)])
    for source in data.get("sources", []):
        source_list.add_item("%s · %s" % [source.get("name", "Source"), source.get("title", "")])
    _render_graph(data.get("entities", []), data.get("links", []))
    if entity_index.size() > 0:
        _show_entity(entity_index[0])

func _render_graph(entities: Array, links: Array) -> void:
    for child in graph_root.get_children():
        child.queue_free()
    var positions := {}
    var count := max(1, entities.size())
    for i in range(entities.size()):
        var entity: Dictionary = entities[i]
        var shell: int = 0 if i == 0 else 1 + int((i - 1) / 8)
        var local_index: int = 0 if i == 0 else (i - 1) % 8
        var shell_count: int = int(min(8, max(1, count - 1 - shell * 8)))
        var angle: float = float(local_index) / float(max(shell_count, 1)) * TAU + float(shell) * 0.42
        var radius: float = 0.0 if i == 0 else 4.4 + float(shell) * 3.0
        var pos: Vector3 = Vector3(cos(angle) * radius, sin(angle * 1.7 + float(shell)) * (1.25 + float(shell) * 0.35), sin(angle) * radius)
        positions[entity.get("id")] = pos
        graph_root.add_child(_make_node(entity, pos, i))
    for link in links:
        var from_id: String = str(link.get("source", ""))
        var to_id: String = str(link.get("target", ""))
        if positions.has(from_id) and positions.has(to_id):
            graph_root.add_child(_make_connection(
                positions[from_id],
                positions[to_id],
                TYPE_COLORS.get(_relation_to_visual_type(str(link.get("type", "related"))), Color.WHITE),
                float(link.get("confidence", 0.5))
            ))

func _make_node(entity: Dictionary, pos: Vector3, index: int) -> Node3D:
    var root := Node3D.new()
    root.position = pos
    root.name = str(entity.get("id", "entity"))
    root.set_meta("corp_node", true)
    root.set_meta("base_scale", 1.0)
    root.set_meta("phase", float(index) * 0.83)
    var type: String = _relation_to_visual_type(str(entity.get("type", "related")))
    var color: Color = TYPE_COLORS.get(type, Color.WHITE)
    var radius: float = 0.72 if type == "main" else 0.38 + min(0.20, float(entity.get("evidence_count", 1)) * 0.025)

    var mesh := MeshInstance3D.new()
    var sphere := SphereMesh.new()
    sphere.radius = radius
    sphere.height = radius * 2.0
    sphere.radial_segments = 32
    sphere.rings = 18
    mesh.mesh = sphere

    var material := StandardMaterial3D.new()
    material.albedo_color = color.darkened(0.15)
    material.emission_enabled = true
    material.emission = color
    material.emission_energy_multiplier = 3.5 if type == "main" else 2.25
    material.metallic = 0.45
    material.roughness = 0.16
    mesh.material_override = material
    root.add_child(mesh)

    for ring_index in range(2 if type == "main" else 1):
        var ring := MeshInstance3D.new()
        var torus := TorusMesh.new()
        torus.inner_radius = radius + 0.18 + ring_index * 0.16
        torus.outer_radius = torus.inner_radius + 0.025
        torus.rings = 48
        torus.ring_segments = 8
        ring.mesh = torus
        ring.rotation.x = PI / 2.0 + ring_index * 0.45
        var ring_material := StandardMaterial3D.new()
        ring_material.albedo_color = Color(color, 0.55)
        ring_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
        ring_material.emission_enabled = true
        ring_material.emission = color
        ring_material.emission_energy_multiplier = 2.0
        ring.material_override = ring_material
        root.add_child(ring)

    var label := Label3D.new()
    label.text = str(entity.get("name", "Entity"))
    label.position = Vector3(0, radius + 0.48, 0)
    label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
    label.font_size = 34 if type == "main" else 26
    label.outline_size = 8
    label.modulate = Color(0.90, 0.97, 1.0)
    root.add_child(label)
    return root

func _make_connection(a: Vector3, b: Vector3, color: Color, confidence: float) -> MeshInstance3D:
    var mesh_instance := MeshInstance3D.new()
    var cylinder := CylinderMesh.new()
    var length: float = a.distance_to(b)
    var thickness: float = 0.025 + clamp(confidence, 0.0, 1.0) * 0.045
    cylinder.top_radius = thickness
    cylinder.bottom_radius = thickness
    cylinder.height = length
    cylinder.radial_segments = 10
    mesh_instance.mesh = cylinder

    var material := StandardMaterial3D.new()
    material.albedo_color = Color(color, 0.72)
    material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
    material.emission_enabled = true
    material.emission = color
    material.emission_energy_multiplier = 1.4 + confidence
    mesh_instance.material_override = material
    mesh_instance.position = (a + b) * 0.5
    mesh_instance.look_at(b, Vector3.UP)
    mesh_instance.rotate_object_local(Vector3.RIGHT, PI / 2.0)
    return mesh_instance

func _show_entity(entity: Dictionary) -> void:
    var source_ids: Array = entity.get("source_ids", [])
    details_text.text = "[b][font_size=22]%s[/font_size][/b]\n\n[b]Type[/b] %s\n[b]Confidence[/b] %.0f%%\n[b]Evidence[/b] %s findings\n[b]Source families[/b] %s\n\n%s" % [
        entity.get("name", "Entity"),
        entity.get("type", "related"),
        float(entity.get("confidence", 0.0)) * 100.0,
        entity.get("evidence_count", 0),
        ", ".join(source_ids) if not source_ids.is_empty() else "—",
        entity.get("description", "No description available.")
    ]

func _on_entity_selected(index: int) -> void:
    if index >= 0 and index < entity_index.size():
        _show_entity(entity_index[index])

func _unhandled_input(event: InputEvent) -> void:
    if event is InputEventMouseButton:
        if event.button_index in [MOUSE_BUTTON_RIGHT, MOUSE_BUTTON_MIDDLE]:
            dragging = event.pressed
        elif event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
            distance = max(6.0, distance - 1.0)
            _update_camera()
        elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
            distance = min(34.0, distance + 1.0)
            _update_camera()
    elif event is InputEventMouseMotion and dragging:
        yaw -= event.relative.x * 0.008
        pitch = clamp(pitch - event.relative.y * 0.008, -1.1, 0.2)
        _update_camera()
    elif event is InputEventScreenDrag:
        yaw -= event.relative.x * 0.004
        pitch = clamp(pitch - event.relative.y * 0.004, -1.1, 0.2)
        _update_camera()

func _update_camera() -> void:
    camera_rig.rotation = Vector3(pitch, yaw, 0)
    camera.position = Vector3(0, 4.6, distance)

func _build_visual_environment() -> void:
    var floor := MeshInstance3D.new()
    floor.name = "DataGrid"
    var plane := PlaneMesh.new()
    plane.size = Vector2(60, 60)
    floor.mesh = plane
    floor.position.y = -3.2

    var shader := Shader.new()
    shader.code = """
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back;
uniform vec3 grid_color : source_color = vec3(0.05, 0.55, 0.85);
void fragment(){
    vec2 g = abs(fract(UV * 40.0 - 0.5) - 0.5) / fwidth(UV * 40.0);
    float line = 1.0 - min(min(g.x, g.y), 1.0);
    float fade = 1.0 - smoothstep(0.15, 0.72, distance(UV, vec2(0.5)));
    ALBEDO = grid_color * 0.35;
    EMISSION = grid_color * line * fade * 0.7;
    ALPHA = max(0.035, line * fade * 0.30);
}
"""
    var shader_material := ShaderMaterial.new()
    shader_material.shader = shader
    floor.material_override = shader_material
    add_child(floor)

    var stars := MultiMeshInstance3D.new()
    var multi_mesh := MultiMesh.new()
    multi_mesh.transform_format = MultiMesh.TRANSFORM_3D
    multi_mesh.instance_count = 220
    var star_mesh := SphereMesh.new()
    star_mesh.radius = 0.018
    star_mesh.height = 0.036
    star_mesh.radial_segments = 6
    star_mesh.rings = 4
    multi_mesh.mesh = star_mesh
    var rng := RandomNumberGenerator.new()
    rng.seed = 20261015
    for i in range(multi_mesh.instance_count):
        var pos := Vector3(rng.randf_range(-30,30), rng.randf_range(-12,18), rng.randf_range(-30,30))
        multi_mesh.set_instance_transform(i, Transform3D(Basis.IDENTITY, pos))
    stars.multimesh = multi_mesh
    var star_material := StandardMaterial3D.new()
    star_material.albedo_color = Color("8bdcff")
    star_material.emission_enabled = true
    star_material.emission = Color("5ec8ff")
    star_material.emission_energy_multiplier = 2.0
    stars.material_override = star_material
    add_child(stars)

func _style_ui() -> void:
    var root_ui: Control = $CanvasLayer/RootUI
    var panel_style := StyleBoxFlat.new()
    panel_style.bg_color = Color(0.025, 0.055, 0.10, 0.88)
    panel_style.border_color = Color(0.15, 0.55, 0.82, 0.34)
    panel_style.set_border_width_all(1)
    panel_style.set_corner_radius_all(16)
    panel_style.shadow_color = Color(0,0,0,0.38)
    panel_style.shadow_size = 18
    for node_path in ["TopBar", "Sidebar", "DetailsPanel"]:
        var panel: PanelContainer = root_ui.get_node(node_path)
        panel.add_theme_stylebox_override("panel", panel_style)

    var button_style := StyleBoxFlat.new()
    button_style.bg_color = Color("0b6fa4")
    button_style.set_corner_radius_all(10)
    button_style.content_margin_top = 12
    button_style.content_margin_bottom = 12
    search_button.add_theme_stylebox_override("normal", button_style)
    search_button.add_theme_color_override("font_color", Color.WHITE)
    search_input.add_theme_color_override("font_color", Color("d8f4ff"))
    search_input.add_theme_color_override("font_placeholder_color", Color(0.55,0.68,0.75,0.8))

func _relation_to_visual_type(value: String) -> String:
    if value in TYPE_COLORS:
        return value
    if value in ["acquisition", "investor"]:
        return "ownership"
    return "related"
