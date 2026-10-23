extends Node3D
## Native runtime using the committed first-level geometry and artwork subset.
const LevelLoader = preload("res://scripts/level_loader.gd")
const VisualStyle = preload("res://scripts/visual_style.gd")
const RunState = preload("res://scripts/run_state.gd")
const FollowCamera = preload("res://scripts/follow_camera.gd")
const TURN_TIME := 19.0 / 60.0
const LEVEL_PATH := "res://levels/level1.json"
const BALL_RADIUS := 100.0 / 512.0
const STEP_TIME := 0.22
const BALL_OFFSET := 0.5 + BALL_RADIUS
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
var run = RunState.new()
var objective_nodes: Dictionary = {}
var portal_material: StandardMaterial3D
var portal_label: Label3D
var hud: Label
var hint: Label
var hint_remaining := 0.0
var result_overlay: ColorRect
var result_title: Label
var result_details: Label
var replay_button: Button
var move_held := false
var pending_turn := 0
var pending_jump := false
var app_active := true
var visual_clock := 0.0
var record_seconds := -1.0
var style = VisualStyle.new()
var level_root: Node3D
var cube_nodes: Dictionary = {}
var original_cells: Array[Vector3i] = []
var ball_body := Basis.IDENTITY
var motion_body := Basis.IDENTITY
var landing_age := 1.0
var in_air := false
var shadow: MeshInstance3D
var shadow_material: ShaderMaterial
var start_normal := Vector3i.UP

func _ready() -> void:
    test_mode = "--self-test" in OS.get_cmdline_user_args() or "--visual-test" in OS.get_cmdline_user_args()
    _load_camera_settings()
    _make_environment()
    _make_ball()
    camera = Camera3D.new()
    camera.current = true
    add_child(camera)
    _make_ui()
    _theme_ui(get_tree().root)
    _load_level("res://levels/test_level.json" if "--self-test" in OS.get_cmdline_user_args() else LEVEL_PATH)
    _update_camera(0.0)
    if "--self-test" in OS.get_cmdline_user_args():
        _run_self_test.call_deferred()
    elif "--visual-test" in OS.get_cmdline_user_args():
        _run_visual_test.call_deferred()

func _process(delta: float) -> void:
    _update_camera(delta)
    visual_clock += delta
    _animate_ball(delta)
    for id in objective_nodes:
        var node: Node3D = objective_nodes[id]
        if node.has_meta("spin"):
            node.rotation.y = visual_clock * 1.4
            node.position.y = float(node.get_meta("base_height",0.0)) + sin(visual_clock*2.4)*0.035*(0.0 if node.has_meta("portal") else 1.0)
    var was_paused: bool = run.paused
    run.paused = not app_active or (is_instance_valid(settings_panel) and settings_panel.visible)
    if was_paused and not run.paused and not busy:
        _visit_surface()
    if run.tick(delta):
        _show_result()
    hint_remaining = maxf(0.0, hint_remaining - delta)
    if hint_remaining == 0.0 and is_instance_valid(hint):
        hint.text = "Mantén Avanzar · recoge la llave y alcanza la salida"
    _refresh_hud()
    if is_instance_valid(replay_button):
        replay_button.disabled = busy
    if not _can_move():
        return
    if pending_jump:
        pending_jump = false
        _jump()
    elif pending_turn != 0:
        var direction := pending_turn
        pending_turn = 0
        _turn(direction)
    elif move_held:
        _advance()

func _make_environment() -> void:
    style.environment(self)

func _load_level(path: String = LEVEL_PATH) -> void:
    var result: Dictionary = LevelLoader.from_json_file(path)
    if not result.get("ok", false):
        status.text = "Error: " + str(result.get("error", "unknown"))
        push_error(status.text)
        return
    if is_instance_valid(level_root):
        level_root.free()
    level_root = Node3D.new()
    add_child(level_root)
    occupied.clear()
    objective_nodes.clear()
    cube_nodes.clear()
    portal_label = null
    portal_material = null
    var points: Array[Vector3i] = result["cells"]
    original_cells = points
    for point in points:
        occupied[LevelLoader.to_world(point)] = true
    start_cell = result.get("start_cell", LevelLoader.to_world(points[0]))
    start_normal = result.get("start_normal", Vector3i.UP)
    start_facing = result.get("start_heading", Vector3i.FORWARD)
    if not result.has("start_heading"):
        for direction in [Vector3i.FORWARD, Vector3i.RIGHT, Vector3i.BACK, Vector3i.LEFT]:
            if occupied.has(start_cell + direction):
                start_facing = direction
                break
    level_name = str(result["name"])
    run.configure(result.get("objects", []), result.get("time_limit", 90.0))
    _make_objectives()
    _rebuild_cubes()
    record_seconds = -1.0
    _load_record()
    ready_to_play = true
    _restart()

func _make_ball() -> void:
    ball = Node3D.new()
    add_child(ball)
    ball_mesh = MeshInstance3D.new()
    ball_mesh.mesh = style.model("ball")
    ball.add_child(ball_mesh)
    shadow = MeshInstance3D.new()
    var quad := PlaneMesh.new()
    quad.size = Vector2(0.58,0.58)
    shadow.mesh = quad
    var shader := Shader.new()
    shader.code = "shader_type spatial; render_mode unshaded, blend_mix, depth_draw_never, cull_disabled; uniform float strength=0.5; void fragment(){float r=length(UV-vec2(0.5))*2.0; ALBEDO=vec3(0.10,0.065,0.025); ALPHA=(1.0-smoothstep(0.10,1.0,r))*strength;}"
    shadow_material = ShaderMaterial.new()
    shadow_material.shader = shader
    shadow.material_override = shadow_material
    add_child(shadow)

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
        _request_turn(-1)
    elif event.is_action_pressed("ui_right"):
        _request_turn(1)
    elif event.is_action_pressed("ui_accept"):
        _request_jump()

func _surface_position(at: Vector3i, up: Vector3i) -> Vector3:
    return Vector3(at) + Vector3(up) * BALL_OFFSET

func _advance() -> void:
    if not _can_move():
        return
    var next := cell + facing
    # A face is walkable only when the space above it is clear.
    if occupied.has(next + normal):
        move_held = false
        _say("Pared delante · gira para continuar")
        return
    var side := Vector3i(Vector3(facing).cross(Vector3(normal)))
    if not occupied.has(next) and (occupied.has(cell+side) or occupied.has(cell-side)):
        move_held = false
        _say("Gira para seguir el recorrido")
        return
    busy = true
    motion_body = ball_body
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
    _visit_surface()

func _roll_linear(t: float, origin: Vector3, destination: Vector3, up: Vector3i, forward: Vector3i) -> void:
    ball.position = origin.lerp(destination, t)
    camera_anchor = ball.position
    var axis := Vector3(up).cross(Vector3(forward)).normalized()
    ball_body = (Basis(axis, t * origin.distance_to(destination) * 5.0 * TAU / 8.0) * motion_body).orthonormalized()

func _roll_edge(t: float, at: Vector3i, up: Vector3i, forward: Vector3i) -> void:
    var n := Vector3(up)
    var f := Vector3(forward)
    var center := Vector3(at)
    var edge := center + (n + f) * 0.5
    if t < 0.3:
        ball.position = (center + n * BALL_OFFSET).lerp(edge + n * BALL_RADIUS, t / 0.3)
    elif t < 0.7:
        var angle := (t - 0.3) / 0.4 * PI * 0.5
        ball.position = edge + (n * cos(angle) + f * sin(angle)) * BALL_RADIUS
    else:
        ball.position = (edge + f * BALL_RADIUS).lerp(center + f * BALL_OFFSET, (t - 0.7) / 0.3)
    camera_anchor = ball.position
    var progress := clampf((t - 0.3) / 0.4, 0.0, 1.0)
    view_frame = _frame(up, forward).slerp(_frame(forward, -up), progress).orthonormalized()
    ball_body = (Basis(n.cross(f).normalized(), t * 5.8) * motion_body).orthonormalized()

func _turn(direction: int) -> void:
    if not _can_move():
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
    if not _can_move():
        return
    # Conservative clearance: do not jump through a cube in the flight corridor.
    for step in range(3):
        if occupied.has(cell + facing * step + normal) or occupied.has(cell + facing * step + normal * 2):
            _say("Salto bloqueado por un cubo")
            return
    busy = true
    in_air = true
    motion_body = ball_body
    var landing := cell + facing * 2
    var origin := ball.position
    var destination := _surface_position(landing, normal)
    var up := normal
    var forward := facing
    var tween := create_tween()
    tween.tween_method(_jump_frame.bind(origin, destination, up, forward), 0.0, 1.0, JUMP_TIME)
    await tween.finished
    if run.enabled and run.state != RunState.State.RUNNING:
        busy = false
        return
    if occupied.has(landing):
        cell = landing
        in_air = false
        landing_age = 0.0
        ball.position = destination
        _say("Salto completado")
        busy = false
        _visit_surface()
    else:
        _say("Caída · vuelves al inicio")
        move_held = false
        pending_turn = 0
        pending_jump = false
        var fall := create_tween()
        fall.tween_property(ball, "position", destination - Vector3(up) * 5.0, 0.45).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
        await fall.finished
        busy = false
        if not run.enabled or run.state == RunState.State.RUNNING:
            _restart()

func _jump_frame(t: float, origin: Vector3, destination: Vector3, up: Vector3i, forward: Vector3i) -> void:
    _roll_linear(t, origin, destination, up, forward)
    ball.position += Vector3(up) * (4.0 * t * (1.0 - t))

func _restart() -> void:
    if busy or not ready_to_play:
        return
    move_held = false
    pending_turn = 0
    pending_jump = false
    run.reset()
    if is_instance_valid(result_overlay):
        result_overlay.hide()
    if is_instance_valid(settings_panel):
        settings_panel.hide()
    for object in run.objects:
        if objective_nodes.has(object["id"]):
            objective_nodes[object["id"]].show()
    _update_portal()
    _rebuild_cubes()
    cell = start_cell
    facing = start_facing
    normal = start_normal
    ball.position = _surface_position(cell, normal)
    ball_body = Basis.IDENTITY
    motion_body = Basis.IDENTITY
    landing_age = 1.0
    in_air = false
    camera_anchor = ball.position
    view_frame = _frame(normal, facing)
    follow_camera.look_amount = 0.0
    look_held = false
    _update_camera(0.0)
    status.text = level_name
    _say("Recoge la llave dorada y alcanza la salida")
    _refresh_hud()

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
    hud = Label.new()
    hud.position = Vector2(24, 62)
    hud.add_theme_font_size_override("font_size", 24)
    root.add_child(hud)
    hint = Label.new()
    hint.position = Vector2(24, 103)
    hint.add_theme_font_size_override("font_size", 19)
    hint.size.x = 790
    hint.clip_text = true
    root.add_child(hint)
    _make_camera_ui(root)
    var bar := HBoxContainer.new()
    root.add_child(bar)
    bar.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
    bar.offset_top = -110
    bar.offset_bottom = -24
    bar.alignment = BoxContainer.ALIGNMENT_CENTER
    bar.add_theme_constant_override("separation", 14)
    _add_button(bar, "Izquierda", _request_turn.bind(-1))
    var advance_button := _add_button(bar, "Avanzar", Callable())
    advance_button.button_down.connect(_set_move_held.bind(true))
    advance_button.button_up.connect(_set_move_held.bind(false))
    _add_button(bar, "Derecha", _request_turn.bind(1))
    _add_button(bar, "Saltar", _request_jump)
    _add_button(bar, "Reiniciar", _restart)
    _make_result_ui(root)

func _add_button(bar: HBoxContainer, title: String, action: Callable) -> Button:
    var button := Button.new()
    button.text = title
    button.custom_minimum_size = Vector2(160, 86)
    button.add_theme_font_size_override("font_size", 23)
    if action.is_valid():
        button.pressed.connect(action)
    bar.add_child(button)
    return button

func _run_self_test() -> void:
    var failures: Array[String] = []
    var authored_cells := occupied.duplicate()
    run.enabled = false
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
        _test_gameplay_state(failures)
        busy = false
        occupied = authored_cells
        run.enabled = true
        await _test_controls(failures)
        await _run_route_test(failures)
        await _test_original_level(failures)
        _test_ball_visuals(failures)
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
    settings_button.pressed.connect(_toggle_camera_settings)
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
        app_active = false
        look_held = false
        move_held = false
        pending_turn = 0
        pending_jump = false
        _save_camera_settings()
    elif what == NOTIFICATION_APPLICATION_FOCUS_IN:
        app_active = true

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
    _toggle_camera_settings()
    await _advance()
    await _capture("camera-first-coin")
    await _advance()
    _jump()
    await get_tree().create_timer(JUMP_TIME*0.5).timeout
    await _capture("camera-jump")
    await get_tree().create_timer(JUMP_TIME).timeout
    await _capture("camera-ball-landing")
    busy = false
    var failures: Array[String] = []
    await _test_original_level(failures)
    if not failures.is_empty():
        push_error(str(failures))
        get_tree().quit(1)
        return
    await _capture("camera-level-complete")
    _restart()
    await _turn(1)
    await _capture("camera-scenery")
    print("VISUAL TEST PASS")
    get_tree().quit(0)

func _can_move() -> bool:
    return ready_to_play and not busy and app_active and (not run.enabled or (run.state == RunState.State.RUNNING and not run.paused))

func _set_move_held(held: bool) -> void:
    move_held = held and app_active and ready_to_play and run.state == RunState.State.RUNNING and not run.paused
    if move_held and _can_move():
        _advance()

func _request_turn(direction: int) -> void:
    if not ready_to_play or not app_active or run.paused or run.state != RunState.State.RUNNING:
        return
    if busy:
        pending_turn = direction
    else:
        _turn(direction)

func _request_jump() -> void:
    if not ready_to_play or not app_active or run.paused or run.state != RunState.State.RUNNING:
        return
    if busy:
        pending_jump = true
    else:
        _jump()

func _toggle_camera_settings() -> void:
    settings_panel.visible = not settings_panel.visible
    run.paused = settings_panel.visible or not app_active
    if not settings_panel.visible and _can_move():
        _visit_surface()
    move_held = false
    pending_turn = 0
    pending_jump = false

func _say(message: String) -> void:
    if is_instance_valid(hint):
        hint.text = message
        hint_remaining = 3.0

func _refresh_hud() -> void:
    if not is_instance_valid(hud):
        return
    var pause_text := " · PAUSA" if run.paused else ""
    hud.text = "%02d  ·  LLAVES %d/%d  ·  %05d PTS%s" % [int(ceil(run.remaining)),run.collected.size(),run.required_keys,run.score,pause_text]
    hud.modulate = Color(1.0,0.43,0.35) if run.remaining < 15.0 else Color(1.0,0.85,0.35)

func _visit_surface() -> void:
    var event: String = run.visit(cell, normal)
    if event in ["key","coin","fruit"]:
        for object in run.objects:
            if run.taken.has(object["id"]) and objective_nodes.has(object["id"]):
                objective_nodes[object["id"]].hide()
        if event == "key":
            _update_portal()
            _rebuild_cubes()
        _say({"key":"Llave recogida · salida abierta","coin":"Moneda recogida · +250 puntos","fruit":"Manzana recogida · +2500 puntos"}[event])
    elif event == "locked":
        _say("Salida cerrada · necesitas la llave")
    elif event == "win":
        _show_result()
    _refresh_hud()

func _mesh(parent: Node3D, shape: Mesh, material: Material, at: Vector3 = Vector3.ZERO) -> MeshInstance3D:
    var instance := MeshInstance3D.new()
    instance.mesh = shape
    instance.material_override = material
    instance.position = at
    parent.add_child(instance)
    return instance

func _make_objectives() -> void:
    for object in run.objects:
        var root := Node3D.new()
        var up: Vector3i = object["normal"]
        root.position = Vector3(object["cell"]) + Vector3(up)*0.51
        var ahead := Vector3i.FORWARD if abs(up.y) == 1 else Vector3i.UP
        root.basis = _frame(up,ahead)
        level_root.add_child(root)
        var model := MeshInstance3D.new()
        var type: String = {"portal":"7","key":"31","coin":"37","fruit":"43"}[object["kind"]]
        var variant: int = int(object.get("variant",0)) if type == "37" else 0
        model.mesh = style.model(type,variant)
        var source: Dictionary = style.data["models"][type][variant]
        model.position.y = -float(source["box"][0][1])/512.0 + 0.06
        if object["kind"] != "portal":
            model.set_meta("spin",true)
            root.position += Vector3(up)*(-float(source["box"][0][1])/512.0+0.10)
            model.position = Vector3.ZERO
        model.set_meta("base_height",model.position.y)
        model.set_meta("spin",true)
        if object["kind"] == "portal":
            model.set_meta("portal",true)
        root.add_child(model)
        objective_nodes[object["id"]] = model
    _update_portal()

func _update_portal() -> void:
    var unlocked: bool = run.collected.size() >= run.required_keys
    for object in run.objects:
        if object["kind"] == "portal" and objective_nodes.has(object["id"]):
            var model: MeshInstance3D = objective_nodes[object["id"]]
            model.mesh = style.model("7",0 if unlocked else 1)

func _make_result_ui(root: Control) -> void:
    result_overlay = ColorRect.new()
    result_overlay.color = Color(0.02, 0.04, 0.09, 0.85)
    root.add_child(result_overlay)
    result_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    result_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
    var panel := PanelContainer.new()
    result_overlay.add_child(panel)
    panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
    panel.offset_left = -260
    panel.offset_right = 260
    panel.offset_top = -160
    panel.offset_bottom = 160
    var style := StyleBoxFlat.new()
    style.bg_color = Color(0.07, 0.12, 0.2)
    style.content_margin_left = 35
    style.content_margin_right = 35
    style.content_margin_top = 30
    style.content_margin_bottom = 30
    style.corner_radius_top_left = 20
    style.corner_radius_top_right = 20
    style.corner_radius_bottom_left = 20
    style.corner_radius_bottom_right = 20
    panel.add_theme_stylebox_override("panel", style)
    var content := VBoxContainer.new()
    content.add_theme_constant_override("separation", 24)
    panel.add_child(content)
    result_title = Label.new()
    result_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    result_title.add_theme_font_size_override("font_size", 34)
    content.add_child(result_title)
    result_details = Label.new()
    result_details.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    result_details.add_theme_font_size_override("font_size", 23)
    content.add_child(result_details)
    replay_button = Button.new()
    replay_button.text = "Volver a jugar"
    replay_button.custom_minimum_size = Vector2(420, 70)
    replay_button.add_theme_font_size_override("font_size", 25)
    replay_button.pressed.connect(_restart)
    content.add_child(replay_button)
    result_overlay.hide()

func _show_result() -> void:
    move_held = false
    pending_turn = 0
    pending_jump = false
    look_held = false
    settings_panel.hide()
    if run.state == RunState.State.WON:
        _save_record()
        result_title.text = "¡Nivel completado!"
        var best := record_seconds if record_seconds >= 0.0 else run.elapsed()
        result_details.text = "%05d puntos · %.2f s\nMejor tiempo: %.2f s" % [run.score, run.elapsed(), best]
    else:
        result_title.text = "Se acabó el tiempo"
        result_details.text = "Recoge la llave y alcanza el portal"
    replay_button.disabled = busy
    result_overlay.show()

func _load_record() -> void:
    if test_mode:
        return
    var config := ConfigFile.new()
    if config.load("user://records.cfg") == OK:
        record_seconds = float(config.get_value(level_name, "best_seconds", -1.0))

func _save_record() -> void:
    if record_seconds < 0.0 or run.elapsed() < record_seconds:
        record_seconds = run.elapsed()
        if not test_mode:
            var config := ConfigFile.new()
            config.set_value(level_name, "best_seconds", record_seconds)
            config.save("user://records.cfg")

func _test_gameplay_state(failures: Array[String]) -> void:
    var state = RunState.new()
    var key := {"id": 0, "kind": "key", "cell": Vector3i.ZERO, "normal": Vector3i.UP}
    var portal := {"id": 1, "kind": "portal", "cell": Vector3i.FORWARD, "normal": Vector3i.UP}
    state.configure([key, portal], 10.0)
    if state.visit(portal["cell"], Vector3i.UP) != "locked":
        failures.append("Portal requires key")
    if state.visit(key["cell"], Vector3i.DOWN) != "none" or not state.collected.is_empty():
        failures.append("Key requires supporting face")
    if state.visit(key["cell"], Vector3i.UP) != "key" or state.visit(key["cell"], Vector3i.UP) != "none" or state.collected.size() != 1:
        failures.append("Single key pickup")
    state.paused = true
    state.tick(20.0)
    if state.remaining != 10.0 or state.visit(portal["cell"], Vector3i.UP) != "none":
        failures.append("Pause freezes timer and objectives")
    state.paused = false
    state.tick(1.0)
    if state.visit(portal["cell"], Vector3i.UP) != "win" or state.state != RunState.State.WON:
        failures.append("Unlocked portal completes level")
    state.tick(20.0)
    if state.remaining != 9.0 or state.visit(portal["cell"], Vector3i.UP) != "none":
        failures.append("Win freezes run")
    state.reset()
    if not state.collected.is_empty() or state.remaining != 10.0 or state.state != RunState.State.RUNNING:
        failures.append("Restart resets objective and timer")
    state.tick(11.0)
    if state.state != RunState.State.EXPIRED or state.remaining != 0.0 or state.visit(key["cell"], Vector3i.UP) != "none":
        failures.append("Timeout blocks late pickup")
    var valid := {"cells": [[1,1,1],[2,1,1]], "objects": [{"kind":"key","cell":[1,1,1],"normal":[0,0,-1]},{"kind":"portal","cell":[2,1,1],"normal":[0,0,-1]}]}
    if not LevelLoader.validate(valid).get("ok", false):
        failures.append("Playable schema accepted")
    var bad: Dictionary = valid.duplicate(true)
    bad["objects"][0]["normal"] = [1,0,0]
    if LevelLoader.validate(bad).get("ok", false):
        failures.append("Buried objective rejected")
    bad = valid.duplicate(true)
    bad["objects"][0]["cell"] = [30,30,30]
    if LevelLoader.validate(bad).get("ok", false):
        failures.append("Unsupported objective rejected")
    print("GAMEPLAY STATE TESTS: key face, duplicate pickup, locked/unlocked portal, pause, timeout, reset and schema validation")

func _run_route_test(failures: Array[String]) -> void:
    busy = false
    run.enabled = true
    _restart()
    await _advance()
    await _jump()
    if run.collected.size() != 1:
        failures.append("Authored route collects key after jump")
    await _advance()
    await _turn(1)
    for step in range(3):
        await _advance()
    await _turn(-1)
    for step in range(3):
        await _advance()
    if run.state != RunState.State.WON or not result_overlay.visible:
        failures.append("Authored route reaches unlocked portal")
    if objective_nodes.has(0) and objective_nodes[0].visible:
        failures.append("Collected key hidden")
    var finished_cell := cell
    await _advance()
    await _jump()
    if cell != finished_cell:
        failures.append("Completed level blocks movement")
    print("FULL ROUTE TEST: start, gap jump, key, two turns, portal, completion modal and movement lock")

func _test_controls(failures: Array[String]) -> void:
    _restart()
    _set_move_held(true)
    _request_jump()
    _set_move_held(false)
    await get_tree().create_timer(STEP_TIME + JUMP_TIME + 0.3).timeout
    if run.collected.size() != 1 or busy or move_held:
        failures.append("Buffered jump after held step")
    var released_cell := cell
    await get_tree().create_timer(0.3).timeout
    if cell != released_cell or busy:
        failures.append("Release stops continued movement")
    _toggle_camera_settings()
    var paused_time: float = run.remaining
    _set_move_held(true)
    _request_turn(1)
    _request_jump()
    await get_tree().create_timer(0.2).timeout
    if run.remaining != paused_time or move_held or pending_jump or pending_turn != 0:
        failures.append("Settings pause timer and queued input")
    _toggle_camera_settings()
    _restart()
    await _advance()
    _jump()
    await get_tree().create_timer(0.1).timeout
    _toggle_camera_settings()
    await get_tree().create_timer(JUMP_TIME + 0.1).timeout
    if not run.collected.is_empty():
        failures.append("Paused arrival defers pickup")
    _toggle_camera_settings()
    if run.collected.size() != 1:
        failures.append("Resume resolves deferred surface pickup")
    _restart()
    run.remaining = 0.03
    _set_move_held(true)
    await get_tree().create_timer(0.5).timeout
    if run.state != RunState.State.EXPIRED or not result_overlay.visible or move_held or busy:
        failures.append("Timeout during movement")
    _restart()
    if result_overlay.visible or not run.collected.is_empty() or run.remaining <= 89.0:
        failures.append("Retry after timeout")
    print("CONTROL TESTS: held movement, buffered jump, release, settings pause, timeout during tween and retry")

func _rebuild_cubes() -> void:
    if not is_instance_valid(level_root):
        return
    for node in cube_nodes.values():
        node.free()
    cube_nodes.clear()
    var surfaces: Array = run.objects.duplicate()
    surfaces.append({"kind":"start","cell":start_cell,"normal":start_normal})
    for original in original_cells:
        var mesh := MeshInstance3D.new()
        mesh.mesh = style.cube(original,occupied,surfaces,run.collected.size() >= run.required_keys)
        mesh.position = Vector3(LevelLoader.to_world(original))
        level_root.add_child(mesh)
        cube_nodes[LevelLoader.to_world(original)] = mesh

func _animate_ball(delta: float) -> void:
    if not is_instance_valid(ball_mesh) or not ready_to_play:
        return
    landing_age += delta
    var breath := sin(visual_clock*TAU)*200.0/4096.0
    var landing := 0.0
    if landing_age < 0.47:
        landing = sin(minf(landing_age/0.07,1.0)*PI*0.5)*0.1826*maxf(0.0,1.0-landing_age/0.47)
    var width := 1.0+breath+landing
    var height := 1.0-2.0*(breath+landing)
    if in_air:
        width *= 0.97
        height *= 1.05
    var frame := view_frame.orthonormalized()
    ball_mesh.basis = frame*Basis.from_scale(Vector3(width,height,width))*frame.inverse()*ball_body
    ball_mesh.position = frame.y*BALL_RADIUS*(height-1.0)
    if is_instance_valid(shadow):
        var under := Vector3i((camera_anchor-Vector3(normal)*BALL_OFFSET).round())
        shadow.visible = occupied.has(under) and not (run.enabled and run.state == RunState.State.WON)
        shadow.position = Vector3(under)+Vector3(normal)*0.505
        shadow.basis = _frame(normal,facing)
        shadow.scale = Vector3(width,1.0,width)
        var clearance := maxf(0.0,(ball.position-camera_anchor).dot(Vector3(normal)))
        shadow_material.set_shader_parameter("strength",maxf(0.0,0.48*(1.0-clearance)))

func _theme_ui(node: Node) -> void:
    if node is Button:
        var base := StyleBoxFlat.new()
        base.bg_color = Color(0.08,0.13,0.16,0.70)
        base.border_color = Color(0.95,0.81,0.47,0.50)
        base.set_border_width_all(1)
        base.set_corner_radius_all(16)
        base.content_margin_left = 14
        base.content_margin_right = 14
        node.add_theme_stylebox_override("normal",base)
        var pressed := base.duplicate()
        pressed.bg_color = Color(0.64,0.43,0.16,0.90)
        pressed.border_color = Color(1.0,0.90,0.57)
        node.add_theme_stylebox_override("pressed",pressed)
        var hover := base.duplicate()
        hover.bg_color = Color(0.18,0.24,0.25,0.85)
        node.add_theme_stylebox_override("hover",hover)
        node.add_theme_color_override("font_color",Color(1.0,0.93,0.75))
    if node is Label:
        node.add_theme_color_override("font_shadow_color",Color(0.07,0.08,0.09,0.90))
        node.add_theme_constant_override("shadow_offset_x",2)
        node.add_theme_constant_override("shadow_offset_y",2)
    for child in node.get_children():
        _theme_ui(child)

func _test_original_level(failures: Array[String]) -> void:
    busy = false
    _load_level(LEVEL_PATH)
    if occupied.size()!=20 or run.objects.size()!=5 or run.time_limit!=99 or start_cell!=Vector3i(17,-17,18) or facing!=Vector3i.FORWARD:
        failures.append("Original LEVEL 1 import/start")
    for step in range(6):
        await _advance()
    if run.state!=RunState.State.RUNNING or run.score!=250:
        failures.append("LEVEL 1 bronze coin and locked exit")
    await _turn(1)
    for step in range(3):
        await _advance()
    await _turn(1)
    for step in range(6):
        await _advance()
    if run.collected.size()!=1 or run.taken.size()!=4 or run.score!=4000:
        failures.append("LEVEL 1 two coins, key and first-fruit apple")
    if "--visual-test" in OS.get_cmdline_user_args():
        await _capture("camera-key-collected")
    await _turn(1)
    for step in range(3):
        await _advance()
    await _turn(1)
    for step in range(6):
        await _advance()
    if run.state!=RunState.State.WON or not result_overlay.visible:
        failures.append("LEVEL 1 full completion")
    print("ORIGINAL LEVEL 1 PASS: 20 cells, original start, two bronze coins, apple, key, locked/unlocked exit, 99 seconds and 4000 points")

func _test_ball_visuals(failures: Array[String]) -> void:
    if style.data["ball"]["polys"].size()!=128 or style.data["ball"]["frames"][0].size()!=294:
        failures.append("Original ball geometry retained")
    ball_body = Basis.IDENTITY
    motion_body = ball_body
    _roll_linear(1.0,Vector3.ZERO,Vector3.FORWARD,Vector3i.UP,Vector3i.FORWARD)
    var first := ball_body
    motion_body = first
    _roll_linear(1.0,Vector3.ZERO,Vector3.FORWARD,Vector3i.UP,Vector3i.FORWARD)
    if ball_body.is_equal_approx(first) or not ball_body.is_equal_approx(Basis(Vector3.LEFT,10.0*TAU/8.0)):
        failures.append("Continuous accumulated ball roll")
    ball_body = Basis.IDENTITY
    view_frame = _frame(Vector3i.UP,Vector3i.FORWARD)
    in_air = false
    landing_age = 0.0
    visual_clock = 0.0
    _animate_ball(0.05)
    var height := ball_mesh.basis.y.length()
    if height >= 1.0 or ball_mesh.basis.x.length()<=1.0 or abs(ball_mesh.position.y-BALL_RADIUS*height+BALL_RADIUS)>0.001:
        failures.append("Landing squash anchored to supporting face")
    print("BALL VISUAL TESTS: original vertex-colour skin, continuous roll and support-anchored landing squash")
