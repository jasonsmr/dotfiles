#!/usr/bin/env bash
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

H="${HOME}"
ETC="${H}/etc"
SHIMS="${ETC}/gcc-shims"
PATCH_HDR="${ETC}/gcc-cxx-compat.h"
STAGE1="${H}/build/scripts/20_build_gcc_android_stage1.sh"
BAK="${STAGE1}.bak"
LOGDIR="${H}/logs/build/android"
MESON_OUT="${H}/build/out"

mkdir -p "${SHIMS}" "${ETC}" "${LOGDIR}"

echo "==> Writing shim: ${SHIMS}/safe-ctype.h (include real, then undef trap macros for C++)"
cat > "${SHIMS}/safe-ctype.h" <<'SC'
#ifndef GCC_SHIM_SAFE_CTYPE_H
#define GCC_SHIM_SAFE_CTYPE_H
/* Pull in GCC's real safe-ctype first. */
#include_next "safe-ctype.h"

/* In C++ TUs, immediately undef the trap macros that conflict with libc++ overloads.
   This keeps GCC's IS* safe macros intact, while allowing <locale>/<cctype> to parse. */
#ifdef __cplusplus
#  ifdef isprint
#    undef isprint
#  endif
#  ifdef iscntrl
#    undef iscntrl
#  endif
#  ifdef tolower
#    undef tolower
#  endif
#  ifdef toupper
#    undef toupper
#  endif
/* Quiet libc++ macro conflict warnings; no semantic change. */
#  ifndef _LIBCPP_DISABLE_MACRO_CONFLICT_WARNINGS
#    define _LIBCPP_DISABLE_MACRO_CONFLICT_WARNINGS 1
#  endif
#endif /* __cplusplus */

#endif /* GCC_SHIM_SAFE_CTYPE_H */
SC

echo "==> Writing harmless pre-include header: ${PATCH_HDR}"
cat > "${PATCH_HDR}" <<'HHD'
#ifdef __cplusplus
#ifndef _LIBCPP_DISABLE_MACRO_CONFLICT_WARNINGS
#  define _LIBCPP_DISABLE_MACRO_CONFLICT_WARNINGS 1
#endif
/* Often avoids availability attribute noise in cross builds; harmless on Android. */
#ifndef _LIBCPP_DISABLE_AVAILABILITY
#  define _LIBCPP_DISABLE_AVAILABILITY 1
#endif
#endif
HHD

WRAP="${SHIMS}/configure-wrap.sh"
echo "==> Writing configure wrapper: ${WRAP}"
cat > "${WRAP}" <<WR
#!/usr/bin/env bash
# Ensure our shim dir is searched first for quoted includes like "safe-ctype.h"
CPPFLAGS="-iquote ${SHIMS} -I${SHIMS} \${CPPFLAGS-}"
# Also pre-include the small libc++ warning silencer (harmless)
CPPFLAGS="\${CPPFLAGS} -include ${PATCH_HDR}"
export CPPFLAGS
# Exec the real configure passed as \$1, forwarding the remaining args
exec "\$@"
WR
chmod +x "${WRAP}"

echo "==> Backing up ${STAGE1}"
[ -f "${BAK}" ] || cp -a "${STAGE1}" "${BAK}"

echo "==> Patching stage1 to call configure through our wrapper and disable gcov tools"
# If we've already patched it, skip.
if ! grep -q "${WRAP}" "${STAGE1}"; then
  # Replace the one line that invokes configure:  "${SRC_GCC}/configure" "${CONF_ARGS[@]}"
  # with: bash "$WRAP" "${SRC_GCC}/configure" "${CONF_ARGS[@]}" --disable-gcov --disable-gcov-tool
  sed -i -E 's#("[[:alnum:]_{}$./-]+/configure"[[:space:]]*"\$\{CONF_ARGS\[@\]\}")#bash "'"${WRAP}"'" \1 --disable-gcov --disable-gcov-tool#' "${STAGE1}" || {
    echo "!! Could not patch configure call in ${STAGE1}. Restoring backup and aborting."
    cp -a "${BAK}" "${STAGE1}"
    exit 1
  }
else
  echo "==> Stage1 already patched; leaving as-is"
fi

echo "==> Cleaning stage1 work dir & previous log"
rm -rf "${H}/toolchain-work/build/gcc-android-stage1"
rm -f "${LOGDIR}/20_gcc_android_stage1.log"

echo "==> Rebuilding android-toolchain via Meson/Ninja"
set +e
meson compile -C "${MESON_OUT}" android-toolchain -v
rc=$?

if [ $rc -ne 0 ]; then
  echo "==> Build failed (exit ${rc}). Showing gcov.cc compile line and tail:"
  grep -n 'gcov\.cc' "${LOGDIR}/20_gcc_android_stage1.log" | head || true
  # Prove our -iquote shim path and pre-include are present on C++ lines:
  grep -n -- "-iquote ${SHIMS}" "${LOGDIR}/20_gcc_android_stage1.log" | head || true
  grep -n -- "-include ${PATCH_HDR}" "${LOGDIR}/20_gcc_android_stage1.log" | head || true
  tail -n 120 "${LOGDIR}/20_gcc_android_stage1.log" || true
  exit $rc
fi

echo "==> Success."
