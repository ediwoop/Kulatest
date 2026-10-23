extends RefCounted
## Camera proportions interpreted from docs/camera.md, in one-unit blocks.
## Native widescreen keeps the vertical composition and exposes more at the sides.
const BASE_PITCH := 250.0 * 360.0 / 4096.0
const BASE_FOV := 77.3196165
const DEPTH := 800.0 / 512.0
const SCREEN_OFFSET := 250.0 / 800.0 / 0.8
var zoom := 1.0
var pitch := BASE_PITCH
var fov := BASE_FOV
var look_amount := 0.0

func update(camera: Camera3D, anchor: Vector3, frame: Basis, look_held: bool, delta: float, occupied: Dictionary) -> void:
    look_amount = move_toward(look_amount, 1.0 if look_held else 0.0, delta * 3.0)
    var theta := deg_to_rad(pitch + look_amount * 35.0)
    var ahead := -frame.z
    var up := frame.y
    var depth := DEPTH * zoom
    var down_offset := depth * tan(deg_to_rad(fov * 0.5)) * SCREEN_OFFSET
    var eye := anchor - ahead * (depth * cos(theta) - down_offset * sin(theta)) + up * (depth * sin(theta) + down_offset * cos(theta))
    eye = _avoid_cubes(anchor, eye, occupied)
    camera.position = eye
    camera.basis = Basis.looking_at(ahead * cos(theta) - up * sin(theta), up)
    camera.fov = fov
    camera.near = 0.035
    camera.far = 150.0
    camera.keep_aspect = Camera3D.KEEP_HEIGHT

func _avoid_cubes(anchor: Vector3, eye: Vector3, occupied: Dictionary) -> Vector3:
    var direction := eye - anchor
    var nearest := 1.0
    for key in occupied:
        var center := Vector3(key)
        var low := center - Vector3.ONE * 0.56
        var high := center + Vector3.ONE * 0.56
        var entry := 0.0
        var exit := 1.0
        var intersects := true
        for axis in range(3):
            if abs(direction[axis]) < 0.00001:
                if anchor[axis] < low[axis] or anchor[axis] > high[axis]:
                    intersects = false
                    break
            else:
                var first: float = (low[axis] - anchor[axis]) / direction[axis]
                var last: float = (high[axis] - anchor[axis]) / direction[axis]
                entry = maxf(entry, minf(first, last))
                exit = minf(exit, maxf(first, last))
                if entry > exit:
                    intersects = false
                    break
        if intersects:
            nearest = minf(nearest, maxf(0.08, entry - 0.06 / maxf(direction.length(), 0.01)))
    return anchor + direction * nearest
