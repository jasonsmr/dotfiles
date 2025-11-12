## 4) `docs/pins-and-ci.md`
```markdown
# Reproducible pins & CI

- All third-party payloads are fetched via `scripts/ci/fetch_components.sh` using **pinned URLs and SHA256** in `scripts/ci/pins.env`.
- **Sample**: `scripts/ci/pins.env.sample` (copy to `pins.env` locally or set via CI secrets).
- CI only installs Linux runner build deps; the runtime bundle remains **self-contained** for Android.

QOL/Guards:
- No `/tmp` — use `${TMP:-$HOME/tmp}` everywhere.
- Workflows locked behind CODEOWNERS; protected branches: `main`, `ci/*`, `productionize`.
- Artifacts are uploaded under `rf-runtime-dist`; releases are created from exact `TAG`.
