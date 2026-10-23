# Level data integration — verified facts and boundaries

The upstream `docs/level-format.md` describes a 34 × 34 × 34 lattice, indexed by
`x * 1156 + y * 34 + z`, with **z increasing downward**. The original
level files contain a u16 lattice, a six-byte header, and 256-byte object
records. This is **not** the same as the simplified JSON format implemented
in `scripts/level_loader.gd`.

The current loader deliberately accepts only original, hand-authored
`{"name":"...","cells":[[x,y,z],...]}` fixtures, validating bounds,
duplicates and malformed input. It converts the downward z-axis into
Godot's upward y-axis.

## Next steps
1. Inspect the actual shape of `public/map_data.json` (large file; connector
   preview did not return its content).
2. Implement a separate adapter from that exact schema to validated cells.
3. Map each cell's face/block type, object records and level start state.
4. Implement surface-relative movement, camera and gravity with tests.
5. Build an Android export using a configured Godot Android SDK runner.

**Rights:** no original level geometry, graphics, music or other extracted
game assets are copied into this Android directory. Upstream data availability
does not imply redistribution permission.

**Status:** source committed; no APK compiled or runtime test performed.
