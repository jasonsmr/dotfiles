#!/data/data/com.termux/files/usr/bin/env zsh
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


# --- env: prefer TMP over /tmp ---
: ${TMP:="$HOME$TMP"}
mkdir -p -- "$TMP"

# Toolchain root (adjust TRIPLE if you add more)
TOOL="${HOME}/opt/toolchain/aarch64-linux-android"

log(){ print -r -- "\n==> $*"; }

# Basic checks
log "Toolchain binary on PATH:"
command -v aarch64-linux-android-as || print -r -- "!! not on PATH"

log "Assembler RUNPATH:"
readelf -d -- "$TOOL/bin/aarch64-linux-android-as" 2>/dev/null | grep -E 'RUNPATH|RPATH' || print -r -- "!! no RUNPATH on assembler"

# Sweep all ELFs for RUNPATH
log "Sweeping toolchain for DT_RUNPATH..."
setopt null_glob
missing=0
for f in "$TOOL"/bin/* "$TOOL"/lib/*.so(.N); do
  file -b -- "$f" | grep -q ELF || continue
  if ! readelf -d -- "$f" 2>/dev/null | grep -q RUNPATH; then
    print -r -- "!! no RUNPATH: $f"
    missing=$((missing+1))
  fi
done
print -r -- "RUNPATH sweep complete; files missing RUNPATH: $missing"

# Smoke test (assemble+link) using $TMP
log "Smoke test (assemble+link) in \$TMP=$TMP"
hello_s="$TMP/hello.s"
hello_o="$TMP/hello.o"
hello_bin="$TMP/hello"

cat > "$hello_s" <<'ASM'
  .global _start
_start:
  mov     x0, #1          // fd=1 (stdout)
  adr     x1, msg
  mov     x2, #14         // len
  mov     x8, #64         // write
  svc     #0
  mov     x8, #93         // exit
  mov     x0, #0
  svc     #0
msg:
  .ascii  "hello, aarch64\n"
ASM

# assemble/link (OK if link fails later—just report)
aarch64-linux-android-as -o "$hello_o" "$hello_s"; rc_as=$?
aarch64-linux-android-ld -o "$hello_bin" "$hello_o"; rc_ld=$?
file "$hello_bin" 2>/dev/null || true

print -r -- "assemble rc=$rc_as, link rc=$rc_ld"
print -r -- "Done."
