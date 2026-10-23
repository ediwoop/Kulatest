extends RefCounted
class_name LevelLoader
## Independent geometry loader. Accepts a minimal, original JSON schema.
## Does not include or redistribute game level data.
const GRID_SIZE := 34
const EMPTY := 65535

static func from_json_file(path: String) -> Dictionary:
    if not FileAccess.file_exists(path):
        return {"ok": false, "error": "File not found: " + path}
    var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
    if not (parsed is Dictionary):
        return {"ok": false, "error": "Expected a JSON object"}
    return validate(parsed)

static func validate(data: Dictionary) -> Dictionary:
    if not data.has("cells") or not (data["cells"] is Array):
        return {"ok": false, "error": "Expected cells array"}
    var cells: Array = data["cells"]
    var points: Array[Vector3i] = []
    var seen := {}
    for raw in cells:
        if not (raw is Array) or raw.size() != 3:
            return {"ok": false, "error": "Each cell must be [x,y,z]"}
        for coordinate in raw:
            if not (coordinate is int or coordinate is float):
                return {"ok": false, "error": "Coordinates must be numbers"}
            if not is_finite(float(coordinate)) or coordinate != floor(coordinate) or coordinate < 0 or coordinate >= GRID_SIZE:
                return {"ok": false, "error": "Coordinates must be integers 0..33"}
        var point := Vector3i(raw[0], raw[1], raw[2])
        if seen.has(point):
            return {"ok": false, "error": "Duplicate cell"}
        seen[point] = true
        points.append(point)
    if points.is_empty():
        return {"ok": false, "error": "Level is empty"}
    return {"ok": true, "cells": points, "name": str(data.get("name", "Test level"))}

## Coordinate conversion from the documented lattice: z is downward.
static func to_world(point: Vector3i) -> Vector3i:
    return Vector3i(point.x, -point.z, point.y)

## The original lattice linear index is x*1156 + y*34 + z.
static func lattice_index(point: Vector3i) -> int:
    return point.x * 1156 + point.y * 34 + point.z
