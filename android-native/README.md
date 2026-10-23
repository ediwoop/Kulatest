# Kula Native Prototype 0.4

Independent Godot Android prototype on the `android-native` branch. Uses original test geometry and procedural visuals; no original game assets are bundled.

## Play the test island

Hold **Avanzar** to keep rolling; release to stop after the current step. Use **Izquierda** and **Derecha** to turn. **Saltar** crosses two cells, including the single-cell gap near the start. A jump or turn requested during a step is buffered. Collect the gold key after the gap, follow the track and enter the portal before the 90-second countdown expires. Only the matching supporting face triggers an objective. Falling restarts this test island. Completion and timeout offer **Volver a jugar**. The best completion time is stored locally.

The **Cámara** panel offers distance, pitch and FOV controls plus Classic/Wide presets. Hold **Mirar abajo** to look down. Opening camera settings pauses the timer; losing application focus releases held inputs and pauses the timer. The camera keeps the vertical jump out of its ground anchor.

This is a single original prototype level, not a recreation of the full game. Obstacles, original levels/assets, audio and a level campaign remain outside this build.

## Validation

The Android workflow runs movement checks on all six faces, camera framing/clearance checks, objective schema/state tests, held-control/input-buffer tests, timeout/retry tests and an automated full-level route. It also renders camera and completion screenshots through software OpenGL before exporting the APK.

Since 0.3, the APK uses the stable public development key documented under `.github/debug-signing`. It is not a production signing key.
