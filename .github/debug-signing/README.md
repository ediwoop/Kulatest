# Public development signing key

This is an intentionally public Android DEBUG key, password `android`, alias `androiddebugkey`. It keeps prototype installs update-compatible from version 0.4 onward. Never use it for production, store releases, sensitive permissions or trust decisions.

Versions 0.1–0.3 actually used Godot's ephemeral editor key; creating the Android SDK debug key alone did not select it in Godot. Version 0.4 explicitly sets `export/android/debug_keystore` and verifies the exported APK's signer against this development key. Uninstall 0.3 or earlier once before installing 0.4.
