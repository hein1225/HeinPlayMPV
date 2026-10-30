#!/usr/bin/env bash
# 把本仓库的预编译产物打成 Release 资产（结构与 fetch_release.sh 的落地路径严格对应）。
#
#   bash scripts/pack_release.sh [输出目录]
#
# 产物：
#   mpv-headers.tar.gz              include/mpv/*
#   android-<abi>.tar.gz            <abi>/*.so
#   android-tvlegacy-<abi>.tar.gz   <abi>/*.so
#   windows-mpv-x86_64.tar.gz       mpv-windows/{bin,lib,include}
#   linux-mpv-x86_64.tar.gz         mpv-linux/{lib,include,mpv.pc}
#   ohos-mpv-arm64-v8a.tar.gz       arm64-v8a/*.so
#   sha256sums.txt
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
OUT="${1:-$ROOT/dist}"
mkdir -p "$OUT"

STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT

# 1) 头文件
#    mpv-headers.tar.gz          —— master 头（Windows / Linux 桌面壳用）
#    mpv-headers-android.tar.gz  —— mpv 0.41.0 头（**必须**与 Android 的 libmpv.so 同源）
#    包内结构统一为 include/mpv/*.h，解到 third_party/ 后即 third_party/include/mpv/...
rm -rf "$STAGE/inc"; mkdir -p "$STAGE/inc/include/mpv"
cp -L "$ROOT/prebuilt/include/mpv/"*.h "$STAGE/inc/include/mpv/"
tar -czf "$OUT/mpv-headers.tar.gz" -C "$STAGE/inc" include

if [ -d "$ROOT/sources/mpv-0.41.0/include/mpv" ]; then
  rm -rf "$STAGE/inca"; mkdir -p "$STAGE/inca/include/mpv"
  cp -L "$ROOT/sources/mpv-0.41.0/include/mpv/"*.h "$STAGE/inca/include/mpv/"
  tar -czf "$OUT/mpv-headers-android.tar.gz" -C "$STAGE/inca" include
fi

# 2) Android 主工程 ABI
for ABI in arm64-v8a armeabi-v7a; do
  SRC="$ROOT/prebuilt/android/$ABI"
  [ -d "$SRC" ] || continue
  rm -rf "$STAGE/a"; mkdir -p "$STAGE/a/$ABI"
  cp -L "$SRC"/*.so "$STAGE/a/$ABI/"
  tar -czf "$OUT/android-$ABI.tar.gz" -C "$STAGE/a" "$ABI"
done

# 3) tvLegacy ABI（若独立产物目录存在）
for ABI in arm64-v8a armeabi-v7a; do
  SRC="$ROOT/prebuilt/tvlegacy/$ABI"
  [ -d "$SRC" ] || continue
  rm -rf "$STAGE/t"; mkdir -p "$STAGE/t/$ABI"
  cp -L "$SRC"/*.so "$STAGE/t/$ABI/"
  tar -czf "$OUT/android-tvlegacy-$ABI.tar.gz" -C "$STAGE/t" "$ABI"
done

# 4) Windows（来自 prebuilt/windows，需先跑 fetch_mpv_windows.sh）
if [ -d "$ROOT/prebuilt/windows" ]; then
  rm -rf "$STAGE/w"; mkdir -p "$STAGE/w"
  cp -rL "$ROOT/prebuilt/windows" "$STAGE/w/mpv-windows"
  tar -czf "$OUT/windows-mpv-x86_64.tar.gz" -C "$STAGE/w" mpv-windows
else
  echo "!! 跳过 Windows 资产：prebuilt/windows 不存在（先跑 build/windows/fetch_mpv_windows.sh）"
fi

# 5) Linux
#    包内结构直接对应工程的 third_party 布局：
#      mpv-linux/libmpv.so.2        ← 桌面 mpv 壳的依赖收集脚本按此路径找
#      mpv-linux/include/mpv/*.h    ← 头文件
#      mpv-linux/mpv.pc             ← pkg-config（CI 用 PKG_CONFIG_PATH 指到解包目录）
#      ffmpeg-mini/lib/*.so*        ← libmpv 依赖的**精简** ffmpeg（缺它 ldd 闭包不完整）
if [ -d "$ROOT/prebuilt/linux/x86_64" ]; then
  rm -rf "$STAGE/l"; mkdir -p "$STAGE/l/mpv-linux/include/mpv"
  cp -L "$ROOT/prebuilt/linux/x86_64/libmpv.so.2" "$STAGE/l/mpv-linux/"
  cp -L "$ROOT/prebuilt/include/mpv/"*.h "$STAGE/l/mpv-linux/include/mpv/"
  [ -f "$ROOT/prebuilt/linux/LICENSE.LGPL" ] && cp -L "$ROOT/prebuilt/linux/LICENSE.LGPL" "$STAGE/l/mpv-linux/"
  sed "s|@PREFIX@|@PREFIX@|" "$ROOT/linux/mpv.pc.in" > "$STAGE/l/mpv-linux/mpv.pc" 2>/dev/null || true
  if [ -d "$ROOT/prebuilt/ffmpeg-mini/lib" ]; then
    mkdir -p "$STAGE/l/ffmpeg-mini/lib"
    cp -L "$ROOT/prebuilt/ffmpeg-mini/lib/"*.so* "$STAGE/l/ffmpeg-mini/lib/"
  fi
  tar -czf "$OUT/linux-mpv-x86_64.tar.gz" -C "$STAGE/l" mpv-linux ffmpeg-mini
fi

# 6) 鸿蒙
if [ -d "$ROOT/prebuilt/ohos/arm64-v8a" ]; then
  rm -rf "$STAGE/o"; mkdir -p "$STAGE/o/arm64-v8a"
  cp -L "$ROOT/prebuilt/ohos/arm64-v8a/"*.so "$STAGE/o/arm64-v8a/"
  tar -czf "$OUT/ohos-mpv-arm64-v8a.tar.gz" -C "$STAGE/o" arm64-v8a
fi

( cd "$OUT" && sha256sum *.tar.gz > sha256sums.txt )
ls -lh "$OUT"
