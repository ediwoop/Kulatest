extends RefCounted
class_name LevelLoader
## Original JSON schema, with validated geometry and surface-bound objectives.
const GRID_SIZE := 34
const EMPTY := 65535

static func from_json_file(path: String) -> Dictionary:
    if not FileAccess.file_exists(path):
        return {"ok": false, "error": "File not found: " + path}
    var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
    if not (parsed is Dictionary):
        return {"ok": false, "error": "Expected a JSON object"}
    return validate(parsed)

static func _triplet(raw: Variant, low: int, high: int) -> bool:
    if not (raw is Array) or raw.size() != 3:
        return false
    for coordinate in raw:
        if not (coordinate is int or coordinate is float):
            return false
        if not is_finite(float(coordinate)) or coordinate != floor(coordinate) or coordinate < low or coordinate > high:
            return false
    return true

static func validate(data: Dictionary) -> Dictionary:
    if not data.has("cells") or not (data["cells"] is Array):
        return {"ok": false, "error": "Expected cells array"}
    var points: Array[Vector3i] = []
    var seen := {}
    for raw in data["cells"]:
        if not _triplet(raw, 0, GRID_SIZE - 1):
            return {"ok": false, "error": "Each cell must contain three integers 0..33"}
        var point := Vector3i(raw[0], raw[1], raw[2])
        if seen.has(point):
            return {"ok": false, "error": "Duplicate cell"}
        seen[point] = true
        points.append(point)
    if points.is_empty():
        return {"ok": false, "error": "Level is empty"}
    var raw_objects: Variant = data.get("objects", [])
    if not (raw_objects is Array):
        return {"ok": false, "error": "Expected objects array"}
    var objects: Array = []
    var surfaces := {}
    var portals := 0
    for raw in raw_objects:
        if not (raw is Dictionary) or not (raw.get("kind", "") in ["key", "portal"]):
            return {"ok": false, "error": "Unknown objective kind"}
        if not _triplet(raw.get("cell"), 0, GRID_SIZE - 1) or not _triplet(raw.get("normal"), -1, 1):
            return {"ok": false, "error": "Invalid objective coordinates"}
        var at := Vector3i(raw["cell"][0], raw["cell"][1], raw["cell"][2])
        var normal := Vector3i(raw["normal"][0], raw["normal"][1], raw["normal"][2])
        if normal.length_squared() != 1 or not seen.has(at) or seen.has(at + normal):
            return {"ok": false, "error": "Objective must rest on an exposed supporting face"}
        var surface := str(at) + ":" + str(normal)
        if surfaces.has(surface):
            return {"ok": false, "error": "Overlapping objectives"}
        surfaces[surface] = true
        if raw["kind"] == "portal":
            portals += 1
        objects.append({"id": objects.size(), "kind": raw["kind"], "cell": to_world(at), "normal": to_world(normal)})
    if not objects.is_empty() and portals != 1:
        return {"ok": false, "error": "Playable levels need exactly one portal"}
    var seconds: Variant = data.get("time_limit", 90.0)
    if not (seconds is int or seconds is float) or not is_finite(float(seconds)) or seconds <= 0 or seconds > 3600:
        return {"ok": false, "error": "Invalid time limit"}
    return {"ok": true, "cells": points, "name": str(data.get("name", "Test level")), "objects": objects, "time_limit": float(seconds)}

static func to_world(point: Vector3i) -> Vector3i:
    return Vector3i(point.x, -point.z, point.y)

static func lattice_index(point: Vector3i) -> int:
    return point.x * 1156 + point.y * 34 + point.z
