extends Node3D
## Original prototype geometry and implementation; no original game assets.
const LevelLoader = preload("res://scripts/level_loader.gd")
const LEVEL_PATH := "res://levels/test_level.json"
const STEP_TIME := 0.22
const BALL_OFFSET := 0.74
const JUMP_TIME := 0.65
var ball: Node3D
var ball_mesh: MeshInstance3D
var camera: Camera3D
var occupied: Dictionary = {}
var cell := Vector3i.ZERO
var normal := Vector3i.UP
var facing := Vector3i.FORWARD
var start_cell := Vector3i.ZERO
var start_facing := Vector3i.FORWARD
var busy := false
var ready_to_play := false
var status: Label
var level_name := ""
var camera_ready := false

func _ready() -> void:
    _make_environment()
    _make_ball()
    camera = Camera3D.new()
    camera.current = true
    add_child(camera)
    _make_ui()
    _load_level()
    _update_camera(1.0)
    if "--self-test" in OS.get_cmdline_user_args():
        _run_self_test.call_deferred()

func _process(delta: float) -> void:
    _update_camera(1.0 - exp(-12.0 * delta))

func _make_environment() -> void:
    var light := DirectionalLight3D.new()
    light.rotation_degrees = Vector3(-45, 30, 0)
    light.light_energy = 1.2
    add_child(light)
    var world := WorldEnvironment.new()
    world.environment = Environment.new()
    world.environment.background_mode = Environment.BG_COLOR
    world.environment.background_color = Color(0.06, 0.09, 0.17)
    world.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
    world.environment.ambient_light_color = Color(0.7, 0.8, 1.0)
    world.environment.ambient_light_energy = 0.55
    add_child(world)

func _load_level() -> void:
    var result: Dictionary = LevelLoader.from_json_file(LEVEL_PATH)
    if not result.get("ok", false):
        status.text = "Error: " + str(result.get("error", "unknown"))
        push_error(status.text)
        return
    var points: Array[Vector3i] = result["cells"]
    for point in points:
        var at := LevelLoader.to_world(point)
        occupied[at] = true
        var mesh := MeshInstance3D.new()
        var cube := BoxMesh.new()
        cube.size = Vector3.ONE * 0.98
        mesh.mesh = cube
        var material := StandardMaterial3D.new()
        material.albedo_color = Color(0.26, 0.65, 0.74) if (at.x + at.y + at.z) % 2 == 0 else Color(0.38, 0.77, 0.80)
        mesh.material_override = material
        mesh.position = Vector3(at)
        add_child(mesh)
    start_cell = LevelLoader.to_world(points[0])
    for direction in [Vector3i.FORWARD, Vector3i.RIGHT, Vector3i.BACK, Vector3i.LEFT]:
        if occupied.has(start_cell + direction):
            start_facing = direction
            break
    level_name = str(result["name"])
    ready_to_play = true
    _restart()

func _make_ball() -> void:
    ball = Node3D.new()
    add_child(ball)
    ball_mesh = MeshInstance3D.new()
    var sphere := SphereMesh.new()
    sphere.radius = 0.23
    sphere.height = 0.46
    ball_mesh.mesh = sphere
    var shader := Shader.new()
    shader.code = "shader_type spatial; varying vec3 p; void vertex(){p=VERTEX;} void fragment(){float stripe=step(0.0,sin(p.y*45.0)); ALBEDO=mix(vec3(1.0,0.45,0.08),vec3(1.0,0.92,0.6),stripe); ROUGHNESS=0.65;}"
    var material := ShaderMaterial.new()
    material.shader = shader
    ball_mesh.material_override = material
    ball.add_child(ball_mesh)

func _update_camera(weight: float) -> void:
    if not is_instance_valid(camera) or not is_instance_valid(ball):
        return
    var target := ball.position + Vector3(normal) * 0.15
    var position_target := ball.position - Vector3(facing) * 4.5 + Vector3(normal) * 3.3
    var target_basis := Basis.looking_at(target - position_target, Vector3(normal))
    if not camera_ready:
        camera.position = position_target
        camera.basis = target_basis
        camera_ready = true
    else:
        camera.position = camera.position.lerp(position_target, weight)
        camera.basis = camera.basis.slerp(target_basis, weight).orthonormalized()

func _unhandled_key_input(event: InputEvent) -> void:
    if event.is_action_pressed("ui_up"):
        _advance()
    elif event.is_action_pressed("ui_left"):
        _turn(-1)
    elif event.is_action_pressed("ui_right"):
        _turn(1)
    elif event.is_action_pressed("ui_accept"):
        _jump()

func _surface_position(at: Vector3i, up: Vector3i) -> Vector3:
    return Vector3(at) + Vector3(up) * BALL_OFFSET

func _advance() -> void:
    if busy or not ready_to_play:
        return
    var next := cell + facing
    # A face is walkable only when the space above it is clear.
    if occupied.has(next + normal):
        status.text = "Pared delante · gira para continuar"
        return
    busy = true
    var old_normal := normal
    var old_facing := facing
    var origin := ball.position
    var tween := create_tween()
    if occupied.has(next):
        cell = next
        tween.tween_method(_roll_linear.bind(origin, _surface_position(cell, normal), old_normal, old_facing), 0.0, 1.0, STEP_TIME)
    else:
        # Convex edge: same supporting cube, new local gravity and heading.
        normal = old_facing
        facing = -old_normal
        tween.tween_method(_roll_edge.bind(cell, old_normal, old_facing), 0.0, 1.0, STEP_TIME * 1.8)
    await tween.finished
    ball.position = _surface_position(cell, normal)
    busy = false
    status.text = level_name + " · salto: 2 cubos · reiniciar: R"

func _roll_linear(t: float, origin: Vector3, destination: Vector3, up: Vector3i, forward: Vector3i) -> void:
    ball.position = origin.lerp(destination, t)
    var axis := Vector3(up).cross(Vector3(forward)).normalized()
    ball_mesh.basis = Basis(axis, t * origin.distance_to(destination) / 0.23)

func _roll_edge(t: float, at: Vector3i, up: Vector3i, forward: Vector3i) -> void:
    var n := Vector3(up)
    var f := Vector3(forward)
    var center := Vector3(at)
    var edge := center + (n + f) * 0.5
    if t < 0.3:
        ball.position = (center + n * BALL_OFFSET).lerp(edge + n * 0.24, t / 0.3)
    elif t < 0.7:
        var angle := (t - 0.3) / 0.4 * PI * 0.5
        ball.position = edge + (n * cos(angle) + f * sin(angle)) * 0.24
    else:
        ball.position = (edge + f * 0.24).lerp(center + f * BALL_OFFSET, (t - 0.7) / 0.3)
    ball_mesh.basis = Basis(n.cross(f).normalized(), t * 5.8)

func _turn(direction: int) -> void:
    if busy or not ready_to_play:
        return
    facing = Vector3i(Vector3(facing).cross(Vector3(normal))) * direction

func _jump() -> void:
    if busy or not ready_to_play:
        return
    # Conservative clearance: do not jump through a cube in the flight corridor.
    for step in range(3):
        if occupied.has(cell + facing * step + normal) or occupied.has(cell + facing * step + normal * 2):
            status.text = "Salto bloqueado por un cubo"
            return
    busy = true
    var landing := cell + facing * 2
    var origin := ball.position
    var destination := _surface_position(landing, normal)
    var up := normal
    var forward := facing
    var tween := create_tween()
    tween.tween_method(_jump_frame.bind(origin, destination, up, forward), 0.0, 1.0, JUMP_TIME)
    await tween.finished
    if occupied.has(landing):
        cell = landing
        ball.position = destination
        status.text = "Salto completado"
        busy = false
    else:
        status.text = "Caída · vuelves al inicio"
        var fall := create_tween()
        fall.tween_property(ball, "position", destination - Vector3(up) * 5.0, 0.45).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
        await fall.finished
        busy = false
        _restart()

func _jump_frame(t: float, origin: Vector3, destination: Vector3, up: Vector3i, forward: Vector3i) -> void:
    _roll_linear(t, origin, destination, up, forward)
    ball.position += Vector3(up) * (4.0 * t * (1.0 - t))

func _restart() -> void:
    if busy or not ready_to_play:
        return
    cell = start_cell
    facing = start_facing
    normal = Vector3i.UP
    ball.position = _surface_position(cell, normal)
    ball_mesh.basis = Basis.IDENTITY
    camera_ready = false
    status.text = level_name + " · avanza hasta un borde o salta el hueco"

func _input(event: InputEvent) -> void:
    if event is InputEventKey and event.pressed and event.keycode == KEY_R:
        _restart()

func _make_ui() -> void:
    var canvas := CanvasLayer.new()
    add_child(canvas)
    var root := Control.new()
    root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    root.mouse_filter = Control.MOUSE_FILTER_IGNORE
    canvas.add_child(root)
    status = Label.new()
    status.position = Vector2(24, 24)
    status.add_theme_font_size_override("font_size", 22)
    root.add_child(status)
    var bar := HBoxContainer.new()
    root.add_child(bar)
    bar.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
    bar.offset_top = -110
    bar.offset_bottom = -24
    bar.alignment = BoxContainer.ALIGNMENT_CENTER
    bar.add_theme_constant_override("separation", 14)
    _add_button(bar, "Izquierda", _turn.bind(-1))
    _add_button(bar, "Avanzar", _advance)
    _add_button(bar, "Derecha", _turn.bind(1))
    _add_button(bar, "Saltar", _jump)
    _add_button(bar, "Reiniciar", _restart)

func _add_button(bar: HBoxContainer, title: String, action: Callable) -> void:
    var button := Button.new()
    button.text = title
    button.custom_minimum_size = Vector2(160, 86)
    button.add_theme_font_size_override("font_size", 23)
    button.pressed.connect(action)
    bar.add_child(button)

func _run_self_test() -> void:
    var failures: Array[String] = []
    var faces: Array[Vector3i] = [Vector3i.UP, Vector3i.DOWN, Vector3i.LEFT, Vector3i.RIGHT, Vector3i.FORWARD, Vector3i.BACK]
    for up in faces:
        var forward := Vector3i.FORWARD if abs(up.y) == 1 else Vector3i.UP
        cell = Vector3i.ZERO
        normal = up
        facing = forward
        occupied = {cell: true, cell + forward: true}
        ball.position = _surface_position(cell, normal)
        _turn(1)
        _turn(-1)
        if facing != forward:
            failures.append("Turn inverse on " + str(up))
        await _advance()
        if cell != forward or normal != up:
            failures.append("Planar move on " + str(up))
        await _advance()
        if normal != forward or facing != -up or cell != forward:
            failures.append("Convex edge on " + str(up))
        if not ball.position.is_equal_approx(_surface_position(cell, normal)):
            failures.append("Surface alignment on " + str(up))
    cell = Vector3i.ZERO
    normal = Vector3i.UP
    facing = Vector3i.FORWARD
    occupied = {cell: true, cell + facing * 2: true}
    ball.position = _surface_position(cell, normal)
    await _jump()
    if cell != Vector3i.FORWARD * 2 or busy:
        failures.append("Jump across gap")
    occupied = {cell: true}
    await _jump()
    if cell != start_cell or normal != Vector3i.UP or busy:
        failures.append("Fall and reset")
    cell = Vector3i.ZERO
    normal = Vector3i.UP
    facing = Vector3i.FORWARD
    occupied = {cell: true, cell + facing + normal: true}
    await _advance()
    if cell != Vector3i.ZERO or normal != Vector3i.UP or busy:
        failures.append("Wall collision")
    await _jump()
    if cell != Vector3i.ZERO or busy:
        failures.append("Jump clearance")
    busy = true
    _turn(1)
    await _advance()
    await _jump()
    _restart()
    if cell != Vector3i.ZERO or facing != Vector3i.FORWARD:
        failures.append("Busy input guard")
    if failures.is_empty():
        print("SELF-TEST PASS: movement and edge transitions on 6 faces, turning, jump, fall/reset, wall, clearance and input guard")
        get_tree().quit(0)
    else:
        for failure in failures:
            push_error(failure)
        get_tree().quit(1)
