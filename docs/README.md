# RobotForest WOW64 Runtime — Overview

This repo builds the **self-contained runtime** used by the RobotForest APK to run Windows games on Android ARM64:
- **Box64 (WoW64)** + **Wine** for Windows userspace
- **DXVK** (D3D9/10/11 → Vulkan), **VKD3D-Proton** (D3D12 → Vulkan)
- **Proton (custom)** glue and configs
- **SteamCMD** for install/update

Key docs:
- BUILD Box64/WoW64 + Wine → [docs/build-box64-wine.md](build-box64-wine.md)
- BUILD Proton/DXVK/VKD3D → [docs/build-proton-stack.md](build-proton-stack.md)
- Runtime layout & entrypoints → [docs/runtime-layout.md](runtime-layout.md)
- SteamCMD usage & secrets → [docs/steamcmd.md](steamcmd.md)
- Android integration (Vulkan, audio, gamepad) → [docs/android-integration.md](android-integration.md)
- Reproducible pins & CI → [docs/pins-and-ci.md](pins-and-ci.md)
