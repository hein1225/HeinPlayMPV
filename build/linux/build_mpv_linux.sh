#!/usr/bin/env bash
# 自编译 libmpv（Linux x64，mpv master，ABI 2.6）
#
#   bash build/linux/build_mpv_linux.sh [mpv 源码目录]
#
# 依赖见 docs/versions.md（Debian 13 的包清单 + libplacebo≥7.360.1 的坑）。
set -euo pipefail

SRC="${1:-/opt/team/tool-deps/mpv-src/mpv}"
PREFIX="${PREFIX:-/usr/local}"
[ -d "$SRC" ] || { echo "找不到 mpv 源码: $SRC" >&2; exit 1; }

meson setup "$SRC/build" --wipe --prefix="$PREFIX" --buildtype=release \
  -Dlibmpv=true -Dcplayer=false -Dbuild-date=false \
  -Dlua=disabled -Djavascript=disabled -Dtests=false \
  -Dvulkan=enabled -Dgl=enabled -Degl-x11=enabled -Dx11=enabled
ninja -C "$SRC/build"
ninja -C "$SRC/build" install
ldconfig
echo "libmpv 已安装到 $PREFIX；把 $PREFIX/lib/x86_64-linux-gnu/libmpv.so.2.* 复制到 prebuilt/linux/x86_64/"
