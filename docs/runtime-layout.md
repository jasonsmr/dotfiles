# Runtime Layout

`rf_runtime/`
- `bin/`
  - `rf-env.sh` — sets PATH/LD_LIBRARY_PATH/WINEPREFIX et al.
  - `rf-steamcmd-win` — wrapper to run Windows SteamCMD via Wine/Box64.
  - `wine64.sh` — convenience launcher.
  - `steam-win.sh` — Proton game runner (see Proton docs).
- `box64/` — Box64 helpers; JNI `.so` is loaded from APK `nativeLibraryDir`.
- `wine64/` — Wine WoW64 tree (binaries, libs, prefixes).
- `dxvk/` `vkd3d/` — Vulkan translation layers (dlls + setup scripts).
- `proton/` — custom Proton runner files and configs.
- `drive_c/steamcmd/` — Windows SteamCMD payload (steamcmd.exe, etc).

> On device, the **APK mounts libbox64.so / libbox86.so** under `nativeLibraryDir`; the runtime wrappers resolve to that path (see RobotForest `Exec.java`). We do **not** rely on Termux/proot at run time.
