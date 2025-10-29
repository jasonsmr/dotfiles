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


# Reuse run_wine.sh env
RUN_WINE="$HOME/bin/run_wine.sh"

# Minimal first-run bootstrap flags that help on odd setups
STEAM_ARGS="--no-cef-sandbox -console -noverifyfiles"

# If Steam is already installed in the prefix, run it:
if [ -x "$WINEPREFIX/drive_c/Program Files (x86)/Steam/steam.exe" ]; then
  exec "$RUN_WINE" "$WINEPREFIX/drive_c/Program Files (x86)/Steam/steam.exe" $STEAM_ARGS
fi

# Else, expect a local installer (place SteamSetup.exe wherever you prefer).
SETUP="${1:-$HOME/Downloads/SteamSetup.exe}"
[ -f "$SETUP" ] || { echo "Missing Steam installer: $SETUP"; exit 1; }

exec "$RUN_WINE" "$SETUP"
