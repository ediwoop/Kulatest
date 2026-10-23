"""Derive the native first-level subset from the committed viewer data."""
import json
import shutil
from pathlib import Path

root = Path(__file__).resolve().parents[2]
public = root / "public"
native = root / "android-native"
data = json.loads((public / "map_data.json").read_text())
shapes = json.loads((public / "objects.json").read_text())
level = next(x for x in data["levels"] if x["pack"] == "/HIRO/HIRO.PAK" and x["index"] == 0)
faces = [[0, 0, -1], [1, 0, 0], [0, 1, 0], [0, -1, 0], [-1, 0, 0], [0, 0, 1]]
cells = [level["cells"][i:i + 3] for i in range(0, len(level["cells"]), 4)]
objects = []
start = None
for record in level["records"]:
    for item in record["on"]:
        at = [record[k] for k in ("x", "y", "z")]
        kind = item["type"]
        if kind == 30:
            start = {"cell": at, "normal": faces[item["face"]], "heading": [0, -1, 0]}
        else:
            name = {7: "portal", 31: "key", 37: "coin", 46: "fruit"}[kind]
            objects.append({"kind": name, "cell": at, "normal": faces[item["face"]], "variant": item["f"][1] if kind == 37 else 0})
assert len(cells) == 20 and len(objects) == 5 and start["cell"] == [17, 18, 17]
native_level = {"name": "LEVEL 1 · HIRO", "source": {"pack": level["pack"], "index": 0}, "cells": cells, "start": start, "time_limit": level["time"], "objects": objects}
(native / "levels/level1.json").write_text(json.dumps(native_level, separators=(",", ":")) + "\n")
visuals = {"ball": shapes["balls"][0], "models": {k: shapes["types"][k] for k in ("7", "31", "37", "43")}, "skins": {k: shapes["skins"][k] for k in ("corners", "sets", "shade")}}
(native / "assets/level1_visuals.json").write_text(json.dumps(visuals, separators=(",", ":")) + "\n")
shutil.copyfile(public / "tex/HIRO.png", native / "assets/HIRO.png")
print("Imported LEVEL 1: 20 cells, exact start, 2 bronze coins, key, apple and exit; Hiro atlas and ball model.")
