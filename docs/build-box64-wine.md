# Building Box64 (WoW64) + Wine for Android (Termux host)

## Host & toolchains
- Host: Android ARM64 (Termux), **no reliance on Termux packages for Windows targets**.
- Bootstrap: Android **NDK r27** toolchain for early stages; then switch to your self-built `aarch64-w64-mingw32` toolchains in `~/opt/toolchain` / `~/opt/mingw*`.
- Source roots: `~/src`; install prefixes: `~/opt/toolchain`, `~/opt/mingw` (64-bit), `~/opt/mingw32` (32-bit).
- Environment prep: ensure your `~/.env/mingw64.sh` / `~/.env/mingw32.sh` switchers and `~/bin` wrappers (clang, pkg-config) are on PATH. Unset `CPATH`, `LIBRARY_PATH` to prevent Termux lib leakage.

### 1) MinGW-w64 toolchains (summary)
- Build **binutils → gcc stage1 → mingw-w64 headers/crt → gcc stage2** for:
  - `x86_64-w64-mingw32` and `i686-w64-mingw32`
- Install to `~/opt/mingw` and `~/opt/mingw32`.
- Provide `x86_64-w64-mingw32-{clang,clang++,ar,ranlib,windsres}` wrappers.
- Verify with simple PE hello (both 32/64).

> (Detailed scripts live in your Fizban toolchain project; this doc links to them and clarifies the exact prefixes and wrappers used by Wine and helper libs.)

### 2) Wine (WoW64) for Android runtime
- Build **Wine WoW64 (64/32)** using MinGW-w64 cross toolchains above, output to a **relocatable tree** we package under `rf_runtime/wine64/`.
- Configure tips:
  - Disable desktop managers you don’t ship.
  - Enable components Proton expects (FAudio, vkd3d support, etc).
  - Use `PKG_CONFIG*` pointing to each prefix; ensure `ZLIB`, `libpng`, `freetype`, `SDL2` static where appropriate.
- Output: `wine64` binaries + WoW64 thunk libs installed under a staging dir we later pack.

### 3) Box64 (ARM64 dynarec) with WoW64 support
- Build natively on ARM64 (Android) with CMake:
  - `-DARM_DYNAREC=ON`
  - Prefer system paths minimal; install into `~/opt/box64` (staging).
- For APK usage, we **package** the produced `libbox64.so` as a JNI lib under `app/src/main/jniLibs/arm64-v8a/` in the Android app (RobotForest).
- At runtime, RobotForest loads `libbox64.so` from `nativeLibraryDir`; our wrappers in `rf_runtime/bin` use that path to execute Windows programs through Wine.

### 4) DXVK & VKD3D-Proton
- Cross build with MinGW-w64 toolchains to produce d3d dlls.
- Package into `rf_runtime/dxvk/` and `rf_runtime/vkd3d/` with setup scripts that copy symlinks/dlls into the Wine prefix on first launch.

### 5) Proton (custom)
- Start from Proton-GE or a stable Proton base.
- Apply config patches for Android:
  - prefer `VK_ICD_FILENAMES` to select Turnip.
  - ship `DXVK_ASYNC` (optional), shader caches disabled by default.
- Place scripts under `rf_runtime/proton/` with runner entrypoint: `steam-win.sh`.

### 6) Pack
- Use `scripts/rf_pack_runtime.sh` to assemble the final `dist/robotforest-wow64-runtime-${TAG}.zip` (CI also emits `.sha256`).
