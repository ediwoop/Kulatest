# Kula Native Android — experimental engine

This directory is an **original Godot 4 prototype**, not a port or a complete reproduction of Kula World.

## Current features
- Basic 3D block path and ball
- Grid-based forward movement
- Left/right 90° orientation changes
- Third-person camera
- On-screen buttons and keyboard controls

## Not yet implemented
- RetroAtlas data loader and level conversion
- Surface-relative gravity and face transitions
- Jumping, collision hazards, scoring, menus, music
- Original textures/models and complete game levels
- Android export and tested APK

## Run
Open `android-native/project.godot` with Godot 4.x and press F6/F5.

## Legal note
No copyrighted Kula World game assets are bundled. The upstream repository's extracted game data and art must be reviewed separately from the code license before incorporation.

## Next engineering milestone
Inspect `public/map_data.json` schema in the parent repository, implement a validated importer with sample original geometry only when its use is cleared, and implement surface-relative movement.
