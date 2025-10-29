#!/data/data/com.termux/files/usr/bin/bash
# ---- toolchain/termux prelude ----
if [ -z "$__TOOLCHAIN_PRELUDE" ]; then
  __TOOLCHAIN_PRELUDE=1
  : ${TMP:="$HOME$TMP"}; mkdir -p -- "$TMP"
  # minimal PATH glue (keep short, user can extend in ~/.zshrc)
  if [ -d "$HOME/opt/toolchain/aarch64-linux-android/bin" ]; then
    case ":$PATH:" in *":$HOME/opt/toolchain/aarch64-linux-android/bin:"*) ;; 
      *) PATH="$HOME/opt/toolchain/aarch64-linux-android/bin:$PATH";;
    esac
  fi
fi
# ---- end prelude ----


RED=$'\e[31m'; GRN=$'\e[32m'; YLW=$'\e[33m'; BLU=$'\e[34m'; DIM=$'\e[2m'; RST=$'\e[0m'
ok()   { printf "${GRN}✔${RST} %s\n" "$*"; }
warn() { printf "${YLW}▲${RST} %s\n" "$*"; }
die()  { printf "${RED}✘${RST} %s\n" "$*" >&2; exit 1; }
info() { printf "${BLU}•${RST} %s\n" "$*"; }
dim()  { printf "${DIM}%s${RST}\n" "$*"; }

FETCH=0
FIX=0
VERBOSE=0
JSON=0
STRICT=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --fetch) FETCH=1; shift;;
    --fix)   FIX=1; shift;;
    --json)  JSON=1; shift;;
    --strict) STRICT=1; shift;;
    -v|--verbose) VERBOSE=$((VERBOSE+1)); shift;;
    -h|--help)
      cat <<EOF
Usage: $(basename "$0") [--fetch] [--fix] [--json] [--strict] [-v]
Checks Termux/NDK/Meson env + required source tarballs for Fizban.
 --fetch  : auto-download missing sources into ~/src
 --fix    : regenerate Meson cross (envmode meson-cross) if available
 --json   : print simple key=value summary
 --strict : fail if system clang resolves outside NDK or if triple drivers missing
 -v       : extra logs + compile smoke test
EOF
      exit 0;;
    *) warn "Unknown arg: $1"; shift;;
  esac
done

# ---------- Termux/platform ----------
[[ -d /data/data/com.termux/files/usr ]] || die "Termux not detected at /data/data/com.termux/files/usr"
ok "Termux detected"

PREFIX="${PREFIX:-/data/data/com.termux/files/usr}"
[[ -x "$PREFIX/bin/bash" ]] || die "bash not found at $PREFIX/bin/bash"
ok "bash present at $PREFIX/bin/bash"

ARCH="$(uname -m)"
ok "Host arch: $ARCH"

# ---------- TMP ----------
TMPDIR="${TMPDIR:-${TMP:-$HOME$TMP}}"
mkdir -p "$TMPDIR" "$PREFIX$HOME$TMP"
[[ -w "$TMPDIR" ]] || die "TMPDIR '$TMPDIR' not writable"
ok "TMPDIR=$TMPDIR writable"

# ---------- env loaders ----------
ENV_MODES="$HOME/.env_modes.sh"
if [[ -f "$ENV_MODES" ]]; then
  # shellcheck disable=SC1090
  source "$ENV_MODES"
  ok "~/.env_modes.sh loaded"
else
  warn "~/.env_modes.sh missing (envmode helper unavailable)"
fi

if [[ -f "$HOME/bin/compile-env.sh" ]]; then
  # shellcheck disable=SC1090
  source "$HOME/bin/compile-env.sh" >/dev/null 2>&1 || true
  ok "~/bin/compile-env.sh present"
fi

# ---------- Android SDK/NDK ----------
ANDROID_HOME="${ANDROID_HOME:-$HOME/opt/android-sdk}"
ANDROID_SDK_ROOT="${ANDROID_SDK_ROOT:-$ANDROID_HOME}"

if [[ -z "${ANDROID_NDK_HOME:-}" ]]; then
  if [[ -d "$ANDROID_HOME/ndk" ]]; then
    ANDROID_NDK_HOME="$(ls -1d "$ANDROID_HOME/ndk"/* 2>/dev/null | sort -V | tail -n1 || true)"
  fi
fi
ANDROID_NDK_HOME="${ANDROID_NDK_HOME:-$HOME/opt/android-ndk-r27b}"
[[ -d "$ANDROID_NDK_HOME" ]] || die "ANDROID_NDK_HOME '$ANDROID_NDK_HOME' not found"
ok "NDK: $ANDROID_NDK_HOME"

HOST_TAG="linux-aarch64"
TOOLCHAIN="$ANDROID_NDK_HOME/toolchains/llvm/prebuilt/$HOST_TAG"
NDK_LLVM_BIN="$TOOLCHAIN/bin"
NDK_SYSROOT="$TOOLCHAIN/sysroot"
[[ -d "$NDK_LLVM_BIN" ]] || die "NDK LLVM bin missing: $NDK_LLVM_BIN"
[[ -d "$NDK_SYSROOT"   ]] || die "NDK sysroot missing: $NDK_SYSROOT"
ok "NDK toolchain OK"

ANDROID_API="${ANDROID_API:-28}"
[[ "$ANDROID_API" =~ ^[0-9]+$ ]] || die "ANDROID_API must be numeric (got '$ANDROID_API')"

NDK_TRIPLE="aarch64-linux-android${ANDROID_API}"
CLANG_TRIPLE="$NDK_LLVM_BIN/$NDK_TRIPLE-clang"
CLANGXX_TRIPLE="$NDK_LLVM_BIN/$NDK_TRIPLE-clang++"

[[ -x "$CLANG_TRIPLE" && -x "$CLANGXX_TRIPLE" ]] || die "NDK triple compilers missing for API $ANDROID_API"
ok "NDK compilers present: $(basename "$CLANG_TRIPLE"), $(basename "$CLANGXX_TRIPLE")"

for t in llvm-ar llvm-ranlib llvm-strip; do
  [[ -x "$NDK_LLVM_BIN/$t" ]] || die "Missing $t in $NDK_LLVM_BIN"
done
ok "llvm-ar/ranlib/strip present"

# ---------- PATH hygiene ----------
first_path="${PATH%%:*}"
ok "PATH head is $first_path"

# ---------- Strict compiler sanity ----------
if command -v clang >/dev/null 2>&1; then
  resolved="$(command -v clang)"
  case "$resolved" in
    "$NDK_LLVM_BIN/clang"|"$CLANG_TRIPLE") ok "clang resolves to NDK: $resolved" ;;
    *)
      if [[ $STRICT -eq 1 ]]; then
        die "System 'clang' resolves to $resolved (not NDK). Enforce explicit NDK triple drivers."
      else
        warn "System 'clang' resolves to $resolved (not NDK). Builds must use $CLANG_TRIPLE explicitly."
      fi
      ;;
  esac
fi

if command -v clang++ >/dev/null 2>&1; then
  resolvedxx="$(command -v clang++)"
  case "$resolvedxx" in
    "$NDK_LLVM_BIN/clang++"|"$CLANGXX_TRIPLE") ok "clang++ resolves to NDK: $resolvedxx" ;;
    *)
      if [[ $STRICT -eq 1 ]]; then
        die "System 'clang++' resolves to $resolvedxx (not NDK). Enforce explicit NDK triple drivers."
      else
        warn "System 'clang++' resolves to $resolvedxx (not NDK). Builds must use $CLANGXX_TRIPLE explicitly."
      fi
      ;;
  esac
fi

# ---------- pkg-config sanity vs ENV_MODE ----------
case "${ENV_MODE:-unset}" in
  ndk-hybrid)
    if [[ -z "${PKG_CONFIG_LIBDIR:-}" ]]; then
      warn "ENV_MODE=ndk-hybrid but PKG_CONFIG_LIBDIR is empty"
    else
      ok "Hybrid mode pkg-config configured"
    fi
    ;;
  ndk-cross)
    if [[ -n "${PKG_CONFIG_LIBDIR:-}${PKG_CONFIG_PATH:-}" ]]; then
      warn "ENV_MODE=ndk-cross prefers empty PKG_CONFIG_* (current set)"
    else
      ok "Cross mode pkg-config clean"
    fi
    ;;
  termux-native|sdk-tools|unset)
    ok "ENV_MODE=${ENV_MODE:-unset}"
    ;;
  *)
    warn "Unknown ENV_MODE ${ENV_MODE}"
    ;;
esac

# ---------- Meson + tools ----------
for t in meson ninja pkg-config tar xz; do
  if command -v "$t" >/dev/null 2>&1; then ok "$t -> $(command -v "$t")"; else warn "$t missing"; fi
done

MESON_DIR="$HOME/.config/meson/cross"
if [[ -d "$MESON_DIR" ]]; then
  ok "Meson cross dir: $MESON_DIR"
else
  warn "Meson cross dir missing: $MESON_DIR"
fi

if [[ $FIX -eq 1 ]] && command -v envmode >/dev/null 2>&1; then
  if envmode meson-cross >/dev/null 2>&1; then ok "Regenerated Meson NDK cross via envmode meson-cross"; else warn "envmode meson-cross failed"; fi
fi

# ---------- Source preflight ----------
SRC="${SRC:-$HOME/src}"
mkdir -p "$SRC"
ok "[fizban preflight] checking sources in $SRC ..."

declare -A SRC_URL=(
  [binutils-2.42]="https://ftp.gnu.org/gnu/binutils/binutils-2.42.tar.xz"
  [gcc-13.2.0]="https://ftp.gnu.org/gnu/gcc/gcc-13.2.0/gcc-13.2.0.tar.xz"
  [gmp-6.3.0]="https://ftp.gnu.org/gnu/gmp/gmp-6.3.0.tar.xz"
  [mpfr-4.2.1]="https://www.mpfr.org/mpfr-4.2.1/mpfr-4.2.1.tar.xz"
  [mpc-1.3.1]="https://ftp.gnu.org/gnu/mpc/mpc-1.3.1.tar.gz"
  [zlib-1.3.1]="https://zlib.net/zlib-1.3.1.tar.xz"
  [mingw-w64-v11.0.1]="https://sourceforge.net/projects/mingw-w64/files/mingw-w64/mingw-w64-release/mingw-w64-v11.0.1.tar.bz2/download"
)

REQ_DIRS=(binutils-2.42 gcc-13.2.0 gmp-6.3.0 mpfr-4.2.1 mpc-1.3.1 zlib-1.3.1 mingw-w64-v11.0.1)
MISSING=()

for d in "${REQ_DIRS[@]}"; do
  if [[ -d "$SRC/$d" ]]; then
    ok "found $d source"
  else
    warn "MISSING source: $d (expected in $SRC)"
    MISSING+=("$d")
  fi
done

if (( ${#MISSING[@]} )) && [[ $FETCH -eq 1 ]]; then
  ok "Fetching missing sources..."
  for d in "${MISSING[@]}"; do
    url="${SRC_URL[$d]:-}"
    if [[ -z "$url" ]]; then warn "No URL mapped for $d; skip"; continue; fi
    cd "$SRC"
    out="$(basename "$url")"
    [[ "$out" == "download" ]] && out="$d.tar.bz2"
    info "Downloading $d -> $out"
    if curl -fL "$url" -o "$out"; then
      info "Extracting $out"
      case "$out" in
        *.tar.xz)  tar -xf "$out" ;;
        *.tar.gz)  tar -xzf "$out" ;;
        *.tar.bz2) tar -xjf "$out" ;;
        *) warn "Unknown archive type: $out (skipping extract)" ;;
      esac
    else
      warn "Download failed: $url"
    fi
  done
  cd - >/dev/null 2>&1 || true
fi

ok "[fizban preflight] done."

# ---------- Optional compile smoke ----------
if [[ $VERBOSE -ge 1 ]]; then
  tmpc="$(mktemp -p "$TMPDIR" XXXXX.c)"
  cat >"$tmpc" <<'CEOF'
#include <stdio.h>
int main(){ puts("hello"); return 0; }
CEOF
  if "$CLANG_TRIPLE" --sysroot="$NDK_SYSROOT" "$tmpc" -o "${tmpc%.c}" >/dev/null 2>&1; then
    ok "NDK clang test compile ok"
  else
    warn "NDK clang test compile failed"
  fi
  rm -f "$tmpc" "${tmpc%.c}"
fi

info "verification complete"
