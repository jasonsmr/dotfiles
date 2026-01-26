# plan_A — GNU toolchain on Termux (NDK-first, clean env) — steps 1–10

Rule:
- We proceed strictly along plan_A steps 1–10.
- If plan_A needs changes, we create a new doc: `plan_B_1-10.md` (never mutate plan_A history).
- All builds must log to `$HOME/logs/gnu-toolchain`.

## Step 1 — Enter correct env mode
- Use: `envmode termux-native`
- Do NOT run random shells mixed with mingw-hybrid vars.

## Step 2 — Hard clean environment (anti-leak)
Unset toolchain selectors and include/link leakage vars:
- CC/CXX/AR/AS/LD/NM/RANLIB/STRIP
- CFLAGS/CXXFLAGS/CPPFLAGS/LDFLAGS
- CPATH/C_INCLUDE_PATH/CPLUS_INCLUDE_PATH/LIBRARY_PATH
- PKG_CONFIG* vars

## Step 3 — Force NDK toolchain + stable shell
- Use NDK clang (from `$HOME/opt/android-sdk/ndk/latest`)
- Force: `CONFIG_SHELL=/data/data/com.termux/files/usr/bin/bash`
- Force: `SHELL=/data/data/com.termux/files/usr/bin/bash`

## Step 4 — Logging policy (mandatory)
All configure/make/install must be piped to:
- `$HOME/logs/gnu-toolchain/<name>.configure.log`
- `$HOME/logs/gnu-toolchain/<name>.make.log`
- `$HOME/logs/gnu-toolchain/<name>.install.log`
For first-failure diagnosis, prefer:
- `make -j1 V=1 ... | tee ...make_j1_v1.log`

## Step 5 — Host ld.bfd (BFD linker) for problematic LLD cases
- Build/install host `ld.bfd` into: `~/opt/host-binutils`
- Ensure unprefixed convenience link exists:
  - `~/opt/host-binutils/bin/ld.bfd -> aarch64-linux-android-ld.bfd`

## Step 6 — clang wrappers that force bfd
- Use `~/bin/clang-bfd` and `~/bin/clang++-bfd`
- They must prepend `~/opt/host-binutils/bin` before NDK clang in PATH.

## Step 7 — GCC stage2 configure (aarch64-linux-gnu target)
Configure with:
- `--target=aarch64-linux-gnu`
- `--prefix=~/opt/gnu`
- `--with-sysroot=~/opt/gnu-sysroot`
- `--with-gmp/mpfr/mpc=~/opt/gnu-deps`
And disable known Android pain points initially:
- `--disable-fixincludes`
- `--disable-lto`
- `--disable-libsanitizer`
- `--disable-bootstrap`
- `--disable-nls`
- `--disable-multilib`

## Step 8 — Build stage2 (first failure capture)
- Run: `make -j1 V=1 SHELL="$SHELL"`
- Fix failures one-by-one (prefer configure cache vars first; if not possible, patch source locally).

## Step 9 — Install stage2
- Run: `make install SHELL="$SHELL"`
- Avoid `ldconfig` probe:
  - `export ac_cv_path_LDCONFIG=/data/data/com.termux/files/usr/bin/true`

## Step 10 — Sanity checks
- Confirm gcc binaries installed under `~/opt/gnu/bin`
- Confirm target triple support and basic compile tests
- Snapshot logs + key scripts into repo notes if successful

