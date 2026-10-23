extends Node3D
## Original prototype geometry and implementation; no original game assets.
const LevelLoader = preload("res://scripts/level_loader.gd")
const FollowCamera = preload("res://scripts/follow_camera.gd")
const TURN_TIME := 19.0 / 60.0
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
var follow_camera = FollowCamera.new()
var view_frame := Basis.IDENTITY
var camera_anchor := Vector3.ZERO
var look_held := false
var settings_panel: PanelContainer
var zoom_slider: HSlider
var pitch_slider: HSlider
var fov_slider: HSlider
var settings_status: Label
var test_mode := false

func _ready() -> void:
    test_mode = "--self-test" in OS.get_cmdline_user_args() or "--visual-test" in OS.get_cmdline_user_args()
    _load_camera_settings()
    _make_environment()
    _make_ball()
    camera = Camera3D.new()
    camera.current = true
    add_child(camera)
    _make_ui()
    _load_level()
    _update_camera(0.0)
    if "--self-test" in OS.get_cmdline_user_args():
        _run_self_test.call_deferred()
    elif "--visual-test" in OS.get_cmdline_user_args():
        _run_visual_test.call_deferred()

func _process(delta: float) -> void:
    _update_camera(delta)

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

func _frame(up: Vector3i, ahead: Vector3i) -> Basis:
    return Basis(Vector3(ahead).cross(Vector3(up)), Vector3(up), -Vector3(ahead)).orthonormalized()

func _update_camera(delta: float) -> void:
    if not is_instance_valid(camera) or not is_instance_valid(ball):
        return
    follow_camera.update(camera, camera_anchor, view_frame, look_held, delta, occupied)

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
    camera_anchor = ball.position
    view_frame = _frame(normal, facing)
    busy = false
    status.text = level_name + " · salto: 2 cubos · reiniciar: R"

func _roll_linear(t: float, origin: Vector3, destination: Vector3, up: Vector3i, forward: Vector3i) -> void:
    ball.position = origin.lerp(destination, t)
    camera_anchor = ball.position
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
    camera_anchor = ball.position
    var progress := clampf((t - 0.3) / 0.4, 0.0, 1.0)
    view_frame = _frame(up, forward).slerp(_frame(forward, -up), progress).orthonormalized()
    ball_mesh.basis = Basis(n.cross(f).normalized(), t * 5.8)

func _turn(direction: int) -> void:
    if busy or not ready_to_play:
        return
    busy = true
    var source := view_frame
    facing = Vector3i(Vector3(facing).cross(Vector3(normal))) * direction
    var destination := _frame(normal, facing)
    var tween := create_tween()
    tween.tween_method(_turn_camera.bind(source, destination), 0.0, 1.0, TURN_TIME).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
    await tween.finished
    view_frame = destination
    busy = false

func _turn_camera(t: float, source: Basis, destination: Basis) -> void:
    view_frame = source.slerp(destination, t).orthonormalized()

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
    camera_anchor = ball.position
    view_frame = _frame(normal, facing)
    follow_camera.look_amount = 0.0
    look_held = false
    _update_camera(0.0)
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
    _make_camera_ui(root)
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
        view_frame = _frame(normal, facing)
        await _turn(1)
        await _turn(-1)
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
        _test_camera(failures)
    if failures.is_empty():
        print("SELF-TEST PASS: movement and edge transitions on 6 faces, turning, jump, fall/reset, wall, clearance and input guard")
        get_tree().quit(0)
    else:
        for failure in failures:
            push_error(failure)
        get_tree().quit(1)

func _load_camera_settings() -> void:
    if test_mode:
        return
    var config := ConfigFile.new()
    if config.load("user://camera.cfg") == OK:
        follow_camera.zoom = clampf(float(config.get_value("camera", "zoom", 1.0)), 1.0, 2.5)
        follow_camera.pitch = clampf(float(config.get_value("camera", "pitch", FollowCamera.BASE_PITCH)), 12.0, 40.0)
        follow_camera.fov = clampf(float(config.get_value("camera", "fov", FollowCamera.BASE_FOV)), 55.0, 90.0)

func _save_camera_settings() -> void:
    if test_mode:
        return
    var config := ConfigFile.new()
    config.set_value("camera", "zoom", follow_camera.zoom)
    config.set_value("camera", "pitch", follow_camera.pitch)
    config.set_value("camera", "fov", follow_camera.fov)
    config.save("user://camera.cfg")

func _make_camera_ui(root: Control) -> void:
    status.custom_minimum_size.x = 780
    status.size.x = 780
    status.clip_text = true
    var tools := HBoxContainer.new()
    root.add_child(tools)
    tools.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
    tools.offset_left = -400
    tools.offset_right = -24
    tools.offset_top = 20
    tools.offset_bottom = 78
    tools.add_theme_constant_override("separation", 12)
    var look_button := Button.new()
    look_button.text = "Mirar abajo"
    look_button.custom_minimum_size = Vector2(180, 58)
    look_button.add_theme_font_size_override("font_size", 22)
    look_button.button_down.connect(func(): look_held = true)
    look_button.button_up.connect(func(): look_held = false)
    tools.add_child(look_button)
    var settings_button := Button.new()
    settings_button.text = "Cámara"
    settings_button.custom_minimum_size = Vector2(180, 58)
    settings_button.add_theme_font_size_override("font_size", 22)
    tools.add_child(settings_button)
    settings_panel = PanelContainer.new()
    root.add_child(settings_panel)
    settings_panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
    settings_panel.offset_left = -410
    settings_panel.offset_right = -24
    settings_panel.offset_top = 90
    settings_panel.offset_bottom = 535
    var style := StyleBoxFlat.new()
    style.bg_color = Color(0.04, 0.07, 0.13, 0.97)
    style.content_margin_left = 22
    style.content_margin_right = 22
    style.content_margin_top = 18
    style.content_margin_bottom = 18
    style.corner_radius_top_left = 14
    style.corner_radius_top_right = 14
    style.corner_radius_bottom_left = 14
    style.corner_radius_bottom_right = 14
    settings_panel.add_theme_stylebox_override("panel", style)
    var content := VBoxContainer.new()
    content.add_theme_constant_override("separation", 12)
    settings_panel.add_child(content)
    var title := Label.new()
    title.text = "Ajustar perspectiva"
    title.add_theme_font_size_override("font_size", 25)
    content.add_child(title)
    zoom_slider = _camera_slider(content, "Distancia", 1.0, 2.5, follow_camera.zoom)
    pitch_slider = _camera_slider(content, "Inclinación", 12.0, 40.0, follow_camera.pitch)
    fov_slider = _camera_slider(content, "Campo de visión", 55.0, 90.0, follow_camera.fov)
    settings_status = Label.new()
    settings_status.add_theme_font_size_override("font_size", 18)
    content.add_child(settings_status)
    var presets := HBoxContainer.new()
    presets.add_theme_constant_override("separation", 10)
    content.add_child(presets)
    for item in [["Clásica", 1.0], ["Amplia", 1.8]]:
        var button := Button.new()
        button.text = item[0]
        button.custom_minimum_size = Vector2(162, 48)
        button.add_theme_font_size_override("font_size", 22)
        button.pressed.connect(_camera_preset.bind(float(item[1])))
        presets.add_child(button)
    zoom_slider.value_changed.connect(_camera_values_changed)
    pitch_slider.value_changed.connect(_camera_values_changed)
    fov_slider.value_changed.connect(_camera_values_changed)
    settings_button.pressed.connect(func(): settings_panel.visible = not settings_panel.visible)
    settings_panel.hide()
    _camera_values_changed(0.0)

func _camera_slider(parent: VBoxContainer, title: String, low: float, high: float, value: float) -> HSlider:
    var label := Label.new()
    label.text = title
    label.add_theme_font_size_override("font_size", 20)
    parent.add_child(label)
    var slider := HSlider.new()
    slider.min_value = low
    slider.max_value = high
    slider.step = 0.01
    slider.value = value
    slider.custom_minimum_size = Vector2(340, 32)
    parent.add_child(slider)
    slider.drag_ended.connect(func(_changed: bool): _save_camera_settings())
    return slider

func _camera_values_changed(_value: float) -> void:
    follow_camera.zoom = zoom_slider.value
    follow_camera.pitch = pitch_slider.value
    follow_camera.fov = fov_slider.value
    settings_status.text = "%.2f×  ·  %.0f°  ·  FOV %.0f°" % [follow_camera.zoom, follow_camera.pitch, follow_camera.fov]

func _camera_preset(zoom: float) -> void:
    zoom_slider.value = zoom
    pitch_slider.value = FollowCamera.BASE_PITCH
    fov_slider.value = FollowCamera.BASE_FOV
    _save_camera_settings()

func _notification(what: int) -> void:
    if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
        look_held = false
        _save_camera_settings()

func _test_camera(failures: Array[String]) -> void:
    var rig = FollowCamera.new()
    var anchor := Vector3.ZERO
    var faces: Array[Vector3i] = [Vector3i.UP, Vector3i.DOWN, Vector3i.LEFT, Vector3i.RIGHT, Vector3i.FORWARD, Vector3i.BACK]
    for up in faces:
        var ahead := Vector3i.FORWARD if abs(up.y) == 1 else Vector3i.UP
        var frame := _frame(up, ahead)
        rig.update(camera, anchor, frame, false, 0.0, {})
        var local := camera.basis.inverse() * (anchor - camera.position)
        var screen_y := 0.5 - local.y / (-local.z * 2.0 * tan(deg_to_rad(camera.fov * 0.5)))
        if abs(screen_y - 0.6953125) > 0.001 or local.z >= 0.0:
            failures.append("Camera framing on " + str(up))
        if not camera.position.is_finite() or abs(camera.basis.determinant() - 1.0) > 0.001:
            failures.append("Camera finite/orthonormal on " + str(up))
        for step in range(21):
            var rotating := frame.slerp(_frame(ahead, -up), float(step) / 20.0).orthonormalized()
            rig.update(camera, anchor, rotating, false, 0.0, {})
            if not camera.position.is_finite() or abs(camera.basis.determinant() - 1.0) > 0.001:
                failures.append("Camera during edge rotation")
    var frame := _frame(Vector3i.UP, Vector3i.FORWARD)
    rig.update(camera, anchor, frame, false, 0.0, {})
    var distance := camera.position.length()
    rig.zoom = 1.8
    rig.update(camera, anchor, frame, false, 0.0, {})
    if abs(camera.position.length() / distance - 1.8) > 0.001:
        failures.append("Camera zoom")
    rig.zoom = 1.0
    rig.update(camera, anchor, frame, true, 1.0, {})
    if rig.look_amount != 1.0:
        failures.append("Camera look down")
    rig.update(camera, anchor, frame, false, 1.0, {})
    if rig.look_amount != 0.0:
        failures.append("Camera look release")
    rig.update(camera, Vector3(0, BALL_OFFSET, 0), frame, false, 0.0, {Vector3i(0, 1, 1): true})
    if camera.position.distance_to(Vector3(0, BALL_OFFSET, 0)) >= distance - 0.1:
        failures.append("Camera obstacle clearance")
    normal = Vector3i.UP
    facing = Vector3i.FORWARD
    view_frame = frame
    occupied = {}
    follow_camera.look_amount = 0.0
    camera_anchor = Vector3(0, BALL_OFFSET, 0)
    _update_camera(0.0)
    var before := camera.position
    _jump_frame(0.5, Vector3(0, BALL_OFFSET, 0), Vector3(0, BALL_OFFSET, -2), normal, facing)
    _update_camera(0.0)
    if abs(camera.position.y - before.y) > 0.001:
        failures.append("Camera jump vertical stability")
    print("CAMERA TESTS: framing and transitions on 6 faces, zoom, look/release, obstacle clearance, jump stability")

func _capture(name: String) -> void:
    for frame in range(4):
        await get_tree().process_frame
    await RenderingServer.frame_post_draw
    var image := get_viewport().get_texture().get_image()
    var error := image.save_png("res://build/" + name + ".png")
    if error != OK:
        push_error("Screenshot failed: " + name)
        get_tree().quit(1)

func _run_visual_test() -> void:
    await _capture("camera-classic")
    _camera_preset(1.8)
    await _capture("camera-wide")
    _camera_preset(1.0)
    settings_panel.show()
    await _capture("camera-settings")
    settings_panel.hide()
    await _advance()
    var before := camera.position
    _jump()
    await get_tree().create_timer(JUMP_TIME * 0.5).timeout
    await _capture("camera-jump")
    await get_tree().create_timer(JUMP_TIME).timeout
    await _turn(1)
    await _capture("camera-turn")
    await _advance()
    await _capture("camera-side")
    await _advance()
    await _capture("camera-under")
    look_held = true
    await get_tree().create_timer(0.4).timeout
    await _capture("camera-look-down")
    look_held = false
    print("VISUAL TEST PASS")
    get_tree().quit(0)
