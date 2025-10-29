#!/usr/bin/env sh
# Termux-safe: no 'set -euo'; explicit error checks; verbose per-step logging.

LOGROOT="$HOME/logs/cross"
mkdir -p "$LOGROOT"

STAMPROOT="$HOME/.cross-stamps"
mkdir -p "$STAMPROOT"

# Pretty time tag
ts() { date +"%Y-%m-%d_%H-%M-%S"; }

# run a step script with xtrace and tee'd logging
run_step() {
  step_name="$1"
  step_cmd="$2"            # full command (script path + args if any)
  stamp="$STAMPROOT/$step_name.done"
  log="$LOGROOT/${step_name}-$(ts).log"

  echo "==> [$step_name] starting (log: $log)"
  if [ -f "$stamp" ]; then
    echo "==> [$step_name] already marked done ($stamp) — skipping"
    return 0
  fi

  # show key env (helpful in logs)
  echo "---- ENV SNAPSHOT ----" | tee -a "$log"
  echo "HOME=$HOME" | tee -a "$log"
  echo "PATH=$PATH" | tee -a "$log"
  echo "LD_LIBRARY_PATH=${LD_LIBRARY_PATH-}" | tee -a "$log"
  echo "----------------------" | tee -a "$log"

  # enable xtrace for the step only
  # shellcheck disable=SC2154
  {
    echo "---- BEGIN STEP $step_name ----"
    set -x
    eval "$step_cmd"
    rc=$?
    { set +x; } 2>/dev/null
    echo "---- END STEP $step_name (rc=$rc) ----"
    exit $rc
  } 2>&1 | tee -a "$log"

  rc=${PIPESTATUS:-0} # zsh/ash safe fallback
  if [ "$rc" -eq 0 ]; then
    touch "$stamp"
    echo "==> [$step_name] OK"
  else
    echo "==> [$step_name] FAILED (see $log)"
    return "$rc"
  fi
}

# ----- sequence -----
# These are the scripts we created earlier.
BIN="$HOME/bin"

run_step "00-env"               ". \"$BIN/env-cross.sh\" && env | sort | sed -n '1,120p' >/dev/null"
run_step "01-binutils"          "\"$BIN/build-binutils-mingw.sh\""
run_step "02-mingw-headers"     "\"$BIN/build-mingw-headers.sh\""
run_step "03-gcc-stage1"        "\"$BIN/build-gcc-stage1-mingw.sh\""
run_step "04-mingw-crt-wpt"     "\"$BIN/build-winpthread.sh\""
run_step "05-gcc-stage2"        "\"$BIN/build-gcc-stage2-mingw.sh\""

# quick verification at the end (binutils + compilers present)
run_step "99-verify"            "
  . \"$BIN/env-cross.sh\" && \
  echo '--- binutils ---' && \
  \"$HOME/opt/toolchain/x86_64-w64-mingw32/bin/x86_64-w64-mingw32-as\" --version && \
  \"$HOME/opt/toolchain/i686-w64-mingw32/bin/i686-w64-mingw32-as\" --version && \
  echo '--- gcc ---' && \
  \"$HOME/opt/toolchain/x86_64-w64-mingw32/bin/x86_64-w64-mingw32-gcc\" -v && \
  \"$HOME/opt/toolchain/i686-w64-mingw32/bin/i686-w64-mingw32-gcc\" -v
"
