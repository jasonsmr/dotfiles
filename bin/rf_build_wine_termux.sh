#!/data/data/com.termux/files/usr/bin/env bash
set -euo pipefail

# rf_build_wine_termux.sh
# ------------------------
# Native Termux Wine builder using existing env + toolchain.
# Assumes env is pre-set via .env_modes.sh
# Output is logged to /sdcard/Download/BUILD/config/wine_build_termux.log

LOGFILE="/sdcard/Download/BUILD/config/wine_build_termux.log"
mkdir -p "$(dirname "$LOGFILE")"
exec > >(tee "$LOGFILE") 2>&1

echo "[*] Starting Wine build inside Termux at $(date)"

cd ~/android/robotforest-wine

echo "[*] Cleaning previous build dirs..."
rm -rf build32 build64
mkdir build32 build64

echo "[*] Sourcing environment..."
source ~/.env_modes.sh

echo "[*] Compiler paths:"
which x86_64-w64-mingw32-gcc || echo "x86_64 gcc missing"
which i686-w64-mingw32-gcc   || echo "i686 gcc missing"

echo "[*] Starting Wine64 build..."
cd build64
export CC=$HOME/opt/mingw/bin/x86_64-w64-mingw32-gcc
export CXX=$HOME/opt/mingw/bin/x86_64-w64-mingw32-g++
export CFLAGS="$CFLAGS -Wl,-rpath,$HOME/opt/mingw/x86_64-w64-mingw32/lib64"

export LDFLAGS="-L$HOME/opt/mingw/x86_64-w64-mingw32/lib64"

export LIBRARY_PATH="$HOME/opt/mingw/x86_64-w64-mingw32/lib64"

../wine-9.0-rf/configure \
  --host=x86_64-w64-mingw32 \
  --disable-tests \
  --without-x \
  --without-alsa \
  --prefix=$HOME/android/rf_runtime_host_test/wine64


make -j$(nproc)
make install

echo "[*] Finished Wine64 at $(date)"

echo "[*] Starting Wine32 build..."
cd ../build32
export CC=$HOME/opt/mingw/bin/i686-w64-mingw32-gcc
export CXX=$HOME/opt/mingw/bin/i686-w64-mingw32-g++
export CFLAGS="-B$HOME/opt/mingw/i686-w64-mingw32/lib \
  -I$HOME/opt/mingw/i686-w64-mingw32/include"
export LDFLAGS="-L$HOME/opt/mingw/i686-w64-mingw32/lib"
export LIBRARY_PATH="$HOME/opt/mingw/i686-w64-mingw32/lib"

../wine-9.0-rf/configure \
  --host=i686-w64-mingw32 \
  --with-wine64=../build64 \
  --disable-tests \
  --without-x \
  --without-alsa \
  --prefix=$HOME/android/rf_runtime_host_test/wine32

make -j$(nproc)
make install

echo "[*] Finished Wine32 at $(date)"

echo "[*] Wine build complete and installed to rf_runtime_host_test"

