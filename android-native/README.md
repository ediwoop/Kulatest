# Kula Native Prototype 0.4

Original test level and procedural visuals, built with Godot on branch `android-native`. No original game assets are bundled.

Hold **Avanzar** to roll, release to stop after the current step. Turn with **Izquierda/Derecha**. **Saltar** crosses two cells and is buffered if requested mid-step. Collect the key after the initial gap and enter the portal within 90 seconds. Pickups require the matching supporting face. Falling restarts the island. Completion/timeout offer **Volver a jugar**; best completion time is saved locally.

Camera controls: **Mirar abajo** (hold), **Cámara** settings, Classic/Wide presets. Settings and loss of focus pause the timer. Closing settings resolves any pickup deferred while paused. The camera follows the ground anchor during jumps.

Checks cover six-face movement/camera, key/portal state, schema validation, timer/pause/retry, held controls, buffered jump and a complete authored route. Rendered checks capture camera views and completion. APK signer is verified against the fixed public development certificate. **Uninstall 0.3 or earlier once before installing 0.4**; see `.github/debug-signing`.

This is a single prototype level; a campaign, original levels/assets, audio and obstacles remain to be implemented.
