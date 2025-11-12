# SteamCMD (Windows) — usage & secrets

**Never** put Steam credentials in repo or CI logs.

Local usage:
- Set env only in a local `.env` file (ignored by git):
  - `STEAM_USERNAME=...`
  - `STEAM_PASSWORD=...` (optional; avoid if possible)
- First login may require Steam Guard; `rf-steamcmd-win` will prompt.

Example:
```bash
source rf_runtime/bin/rf-env.sh
rf_runtime/bin/rf-steamcmd-win +login "$STEAM_USERNAME" +app_info_update 1 +quit
