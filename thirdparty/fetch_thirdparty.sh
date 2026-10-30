#!/usr/bin/env bash
# 获取第三方依赖到本地缓存目录（不入库）。
#
#   bash thirdparty/fetch_thirdparty.sh <组件> [版本|路径]
#
# 组件：libplacebo | shaderc | vulkan-headers | ffmpeg | lycium
set -euo pipefail

COMP="${1:?用法: fetch_thirdparty.sh <组件> [版本|路径]}"
ARG="${2:-}"
CACHE="${MPV_THIRDPARTY_CACHE:-$HOME/.cache/heinplay-mpv/thirdparty}"
mkdir -p "$CACHE"

case "$COMP" in
  libplacebo)
    REPO="https://github.com/haasn/libplacebo.git"; DIR="libplacebo"; VER="$ARG" ;;
  shaderc)
    REPO="https://github.com/google/shaderc.git"; DIR="shaderc"; VER="$ARG" ;;
  vulkan-headers)
    REPO="https://github.com/KhronosGroup/Vulkan-Headers.git"; DIR="vulkan-headers"; VER="$ARG" ;;
  ffmpeg)
    REPO="https://github.com/FFmpeg/FFmpeg.git"; DIR="ffmpeg"; VER="$ARG" ;;
  lycium)
    REPO="https://gitee.com/openharmony-sig/lycium.git"; DIR="lycium"; VER="$ARG" ;;
  *) echo "未知组件: $COMP" >&2; exit 2 ;;
esac

DEST="$CACHE/$DIR"
if [ -d "$DEST/.git" ]; then
  echo "已存在: $DEST（如需更新请先删除）"
else
  git clone --depth 1 ${VER:+--branch "$VER"} "$REPO" "$DEST"
fi
echo "→ $DEST"
