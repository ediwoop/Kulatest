extends Node3D
## Native prototype using original hand-authored test geometry only.
const LevelLoader = preload("res://scripts/level_loader.gd")
const LEVEL_PATH := "res://levels/test_level.json"
const STEP_TIME := 0.18
const BALL_OFFSET := 0.74
var ball: Node3D
var camera: Camera3D
var occupied: Dictionary = {}
var cell := Vector3i.ZERO
var facing := Vector3i(0, 0, -1)
var busy := false
var status: Label

func _ready() -> void:
    _make_environment()
    _make_ball()
    _make_camera()
    _make_ui()
    _load_level()
    _update_camera()

func _make_environment() -> void:
    var light := DirectionalLight3D.new()
    light.rotation_degrees = Vector3(-45, 30, 0)
    add_child(light)
    var world := WorldEnvironment.new()
    world.environment = Environment.new()
    world.environment.background_mode = Environment.BG_COLOR
    world.environment.background_color = Color(0.06, 0.09, 0.17)
    add_child(world)

func _load_level() -> void:
    var result: Dictionary = LevelLoader.from_json_file(LEVEL_PATH)
    if not result.get("ok", false):
        status.text = "Error: " + str(result.get("error", "unknown"))
        push_error(status.text)
        return
    var material := StandardMaterial3D.new()
    material.albedo_color = Color(0.34, 0.75, 0.82)
    var points: Array[Vector3i] = result["cells"]
    for point in points:
        _add_cube(LevelLoader.to_world(point), material)
    # Start at the first authored cell; prefer a neighbour in the forward direction.
    cell = LevelLoader.to_world(points[0])
    facing = Vector3i.ZERO
    for direction in [Vector3i(0, 0, -1), Vector3i(1, 0, 0), Vector3i(0, 0, 1), Vector3i(-1, 0, 0)]:
        if occupied.has(cell + direction):
            facing = direction
            break
    if facing == Vector3i.ZERO:
        facing = Vector3i(0, 0, -1)
    ball.position = Vector3(cell) + Vector3.UP * BALL_OFFSET
    status.text = str(result["name"]) + " · " + str(points.size()) + " cubos"

func _add_cube(at: Vector3i, material: Material) -> void:
    occupied[at] = true
    var mesh := MeshInstance3D.new()
    mesh.mesh = BoxMesh.new()
    mesh.material_override = material
    mesh.position = Vector3(at)
    add_child(mesh)

func _make_ball() -> void:
    ball = Node3D.new()
    add_child(ball)
    var mesh := MeshInstance3D.new()
    var sphere := SphereMesh.new()
    sphere.radius = 0.23
    sphere.height = 0.46
    mesh.mesh = sphere
    var material := StandardMaterial3D.new()
    material.albedo_color = Color(1.0, 0.56, 0.18)
    mesh.material_override = material
    ball.add_child(mesh)

func _make_camera() -> void:
    camera = Camera3D.new()
    camera.current = true
    add_child(camera)

func _update_camera() -> void:
    camera.position = ball.position - Vector3(facing) * 4.5 + Vector3.UP * 3.3
    camera.look_at(ball.position + Vector3.UP * 0.15)

func _unhandled_key_input(event: InputEvent) -> void:
    if event.is_action_pressed("ui_up"):
        _advance()
    elif event.is_action_pressed("ui_left"):
        _turn(-1)
    elif event.is_action_pressed("ui_right"):
        _turn(1)

func _advance() -> void:
    if busy:
        return
    var next := cell + facing
    if not occupied.has(next):
        status.text = "No hay cubo delante"
        return
    busy = true
    cell = next
    var tween := create_tween()
    tween.tween_property(ball, "position", Vector3(cell) + Vector3.UP * BALL_OFFSET, STEP_TIME)
    await tween.finished
    busy = false
    _update_camera()

func _turn(direction: int) -> void:
    if busy:
        return
    facing = Vector3i(-facing.z * direction, 0, facing.x * direction)
    _update_camera()

func _make_ui() -> void:
    var canvas := CanvasLayer.new()
    add_child(canvas)
    status = Label.new()
    status.position = Vector2(20, 20)
    canvas.add_child(status)
    var bar := HBoxContainer.new()
    bar.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
    bar.offset_top = -95
    bar.offset_bottom = -15
    bar.alignment = BoxContainer.ALIGNMENT_CENTER
    canvas.add_child(bar)
    for item in [["Girar izq.", -1], ["Avanzar", 0], ["Girar der.", 1]]:
        var button := Button.new()
        button.text = item[0]
        button.custom_minimum_size = Vector2(115, 75)
        bar.add_child(button)
        if item[1] == 0:
            button.pressed.connect(_advance)
        else:
            button.pressed.connect(_turn.bind(item[1]))
