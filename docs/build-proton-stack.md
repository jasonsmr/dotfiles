# Proton, DXVK, VKD3D-Proton — build notes

- DXVK: build with `x86_64-w64-mingw32` + `i686-w64-mingw32` (dlls land under `dxvk/`).
- VKD3D-Proton: build with `x86_64-w64-mingw32` (d3d12.dll + vkd3d libs under `vkd3d/`).
- Proton (scripts/configs): use GE tag or curated set; put under `proton/` with launcher `steam-win.sh`.
- First-run copy step: wrapper moves DXVK/VKD3D dlls into the active prefix (`drive_c/...`) if not present.
