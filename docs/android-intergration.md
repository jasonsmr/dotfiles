# Android Integration

## Vulkan
- Expect Adreno + Turnip. APK sets:
  - `VK_ICD_FILENAMES` to the system Vulkan ICD (no Mesa Zink in prod).
  - `ENABLE_VK_LAYER_LUNARG_monitor` off in prod.
- Runtime verifies `vulkaninfo` presence via app-side diagnostic (optional).

## Audio
- Prefer **AAudio** via your app layer; Wine/Proton side uses FAudio (XAudio) and standard Wine audio drivers.
- Provide an option to select audio buffer size/latency in app settings; pass via env into Wine.

## Gamepad
- Use Android input events in the APK to create a **SDL GameController** mapping file shipped as `rf_runtime/proton/gamecontrollerdb.txt`.
- Set `SDL_GAMECONTROLLERCONFIG` and/or drop db in expected Proton paths.
- Enable `XINPUT` mapping in Proton; ensure your Xbox Wireless controller is recognized.

## Other
- Storage via SAF/DocumentFile; runtime lives in app-private dir.
- No world-readable secrets; logs redact credentials; crash-safe temp uses `${TMP:-$HOME/tmp}` only.
