#!/bin/bash
set -euo pipefail
RIVO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$RIVO_ROOT"
command -v cmake >/dev/null || { echo 'Instala CMake: brew install cmake'; exit 1; }
command -v xcodebuild >/dev/null || { echo 'Este script requiere macOS y Xcode.'; exit 1; }
bash scripts/ensure-vendor.sh
mkdir -p .build/sources
tar -xzf Vendor/taglib-2.3.2.tar.gz -C .build/sources
tar -xzf Vendor/utfcpp-4.0.6.tar.gz -C .build/sources
build_slice() {
  local slice="$1" sdk="$2" archs="$3"
  cmake -S .build/sources/taglib-2.3.2 -B ".build/taglib-$slice" \
    -DCMAKE_BUILD_TYPE=Release -DCMAKE_SYSTEM_NAME=iOS \
    -DCMAKE_OSX_SYSROOT="$(xcrun --sdk "$sdk" --show-sdk-path)" \
    -DCMAKE_OSX_ARCHITECTURES="$archs" -DCMAKE_OSX_DEPLOYMENT_TARGET=18.0 \
    -DCMAKE_INSTALL_PREFIX="$RIVO_ROOT/.build/install-$slice" \
    -Dutf8cpp_INCLUDE_DIR="$RIVO_ROOT/.build/sources/utfcpp-4.0.6/source" \
    -DBUILD_SHARED_LIBS=OFF -DBUILD_TESTING=OFF -DWITH_EXAMPLES=OFF \
    -DBUILD_BINDINGS=OFF -DWITH_ZLIB=ON
  cmake --build ".build/taglib-$slice" --parallel 3
  cmake --install ".build/taglib-$slice"
}
build_slice device iphoneos arm64
build_slice simulator iphonesimulator 'arm64;x86_64'
rm -rf Vendor/TagLib.xcframework
xcodebuild -create-xcframework \
  -library .build/install-device/lib/libtag.a -headers .build/install-device/include \
  -library .build/install-simulator/lib/libtag.a -headers .build/install-simulator/include \
  -output Vendor/TagLib.xcframework
