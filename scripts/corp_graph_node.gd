extends Area3D
class_name CorpGraphNode

signal selected(entity: Dictionary)
signal hovered(entity: Dictionary, active: bool)

var entity: Dictionary = {}
var base_scale := 1.0
var phase := 0.0
var ring_nodes: Array = []

func configure(data: Dictionary, radius: float, color: Color, index: int) -> void:
    entity = data
    phase = float(index) * 0.83
    input_ray_pickable = true

    var collision := CollisionShape3D.new()
    var shape := SphereShape3D.new()
    shape.radius = radius * 1.45
    collision.shape = shape
    add_child(collision)

    var sphere_mesh := MeshInstance3D.new()
    var sphere := SphereMesh.new()
    sphere.radius = radius
    sphere.height = radius * 2.0
    sphere.radial_segments = 36
    sphere.rings = 20
    sphere_mesh.mesh = sphere

    var material := StandardMaterial3D.new()
    material.albedo_color = color.darkened(0.18)
    material.emission_enabled = true
    material.emission = color
    material.emission_energy_multiplier = 3.6 if str(entity.get("type", "")) == "main" else 2.4
    material.metallic = 0.52
    material.roughness = 0.12
    sphere_mesh.material_override = material
    add_child(sphere_mesh)

    var ring_count := 3 if str(entity.get("type", "")) == "main" else 1
    for ring_index in range(ring_count):
        var ring := MeshInstance3D.new()
        var torus := TorusMesh.new()
        torus.inner_radius = radius + 0.16 + ring_index * 0.13
        torus.outer_radius = torus.inner_radius + 0.026
        torus.rings = 48
        torus.ring_segments = 10
        ring.mesh = torus
        ring.rotation.x = PI / 2.0 + ring_index * 0.38
        var rm := StandardMaterial3D.new()
        rm.albedo_color = Color(color, 0.58)
        rm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
        rm.emission_enabled = true
        rm.emission = color
        rm.emission_energy_multiplier = 2.2
        ring.material_override = rm
        ring_nodes.append(ring)
        add_child(ring)

    var label := Label3D.new()
    label.text = str(entity.get("name", "Entity"))
    label.position = Vector3(0, radius + 0.46, 0)
    label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
    label.font_size = 30 if str(entity.get("type", "")) == "main" else 24
    label.outline_size = 9
    label.modulate = Color(0.92, 0.97, 1.0)
    add_child(label)

    input_event.connect(_on_input_event)
    mouse_entered.connect(func(): hovered.emit(entity, true))
    mouse_exited.connect(func(): hovered.emit(entity, false))

func animate(time: float) -> void:
    var pulse := 1.0 + sin(time * 1.8 + phase) * 0.035
    scale = Vector3.ONE * base_scale * pulse
    for i in range(ring_nodes.size()):
        var ring: Node3D = ring_nodes[i]
        ring.rotation.z += 0.003 + float(i) * 0.0015

func set_highlight(active: bool) -> void:
    base_scale = 1.18 if active else 1.0

func _on_input_event(_camera: Node, event: InputEvent, _position: Vector3, _normal: Vector3, _shape_idx: int) -> void:
    if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
        selected.emit(entity)
    elif event is InputEventScreenTouch and event.pressed:
        selected.emit(entity)
