extends RefCounted
## Gameplay state is independent of rendering and uses explicit supporting faces.
enum State { RUNNING, WON, EXPIRED }
var enabled := false
var state := State.RUNNING
var paused := false
var objects: Array = []
var time_limit := 90.0
var remaining := 90.0
var required_keys := 0
var collected: Dictionary = {}

func configure(level_objects: Array, seconds: float) -> void:
    objects = level_objects.duplicate(true)
    time_limit = seconds
    required_keys = 0
    for object in objects:
        if object["kind"] == "key":
            required_keys += 1
    enabled = not objects.is_empty()
    reset()

func reset() -> void:
    state = State.RUNNING
    paused = false
    remaining = time_limit
    collected.clear()

func tick(delta: float) -> bool:
    if not enabled or paused or state != State.RUNNING:
        return false
    remaining = maxf(0.0, remaining - maxf(delta, 0.0))
    if remaining == 0.0:
        state = State.EXPIRED
        return true
    return false

func visit(cell: Vector3i, normal: Vector3i) -> String:
    if not enabled or paused or state != State.RUNNING:
        return "none"
    for object in objects:
        if object["cell"] != cell or object["normal"] != normal:
            continue
        if object["kind"] == "key" and not collected.has(object["id"]):
            collected[object["id"]] = true
            return "key"
        if object["kind"] == "portal":
            if collected.size() < required_keys:
                return "locked"
            state = State.WON
            return "win"
    return "none"

func elapsed() -> float:
    return time_limit - remaining
