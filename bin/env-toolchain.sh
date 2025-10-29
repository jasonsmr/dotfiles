# save as: ~/env-toolchain.sh
# usage:   . ~/env-toolchain.sh    (note the leading dot)

# --- paths you already use ---
export BUILD="$HOME/build/gcc-android-stage1"
export DEST="$HOME/opt/toolchain/aarch64-linux-android/lib/gcc/aarch64-linux-android/13.2.0"
export HOSTLIB="$HOME/opt/host-libs/lib"

# 1) cc1 runtime deps (gmp/mpfr/mpc)
export LD_LIBRARY_PATH="$HOSTLIB${LD_LIBRARY_PATH+:$LD_LIBRARY_PATH}"

# 2) let GCC find your installed libgcc.a without always passing -L
#    (this affects the *linker* search path, not the shell)
export LIBRARY_PATH="$DEST${LIBRARY_PATH+:$LIBRARY_PATH}"

# (optional) add your stage1 gcc driver to PATH for convenience
# export PATH="$BUILD/gcc:$PATH"
