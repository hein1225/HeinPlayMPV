#!/bin/bash
# ═══════════════════════════════════════════════════════════════════════════
# HeinPlay 安卓专用 mpv 交叉编译入口（tvLegacy / Android 5.0+）
#
# 【为什么自己编而不用鸿蒙那份】
#   鸿蒙版 libmpv.so 的 ELF 带 `.note.ohos.ident`、构建配置是
#   `-Degl-android=disabled -Degl-openharmony=enabled`，且 NEEDED 含
#   `libnative_window.so`（鸿蒙库名；安卓对应 libnativewindow.so，无下划线）。
#   它在安卓上 System.loadLibrary 必然失败 —— 平台产物不可跨用。
#
# 【渲染路线：OpenGL，不用 Vulkan】
#   官方 mpv 的图形后端是插件式的，GL 与 Vulkan 并列：
#     · video/out/opengl/context_android.c → gpu-context=android（EGL + GLES）
#     · video/out/vulkan/context.c         → gpu-context=vulkan（需 libvulkan）
#   Vulkan 是 Android 7.0(API 24) 才引入的，而本工程要覆盖 Android 5.0(API 21)，
#   故走官方 mpv-android 同款路线：ffmpeg --disable-vulkan、
#   libplacebo -Dvulkan=disabled，得到 vo=gpu + gpu-context=android 的纯 GL 版本。
#
# 【上游复用】构建脚本直接复用官方 mpv-android 的 buildscripts（已就地适配）：
#   · NDK 指向本机 r27（官方默认 r30）
#   · apilvl 参数化（官方硬编码 23，本工程用 21）
#   · mpv 源码固定 v0.41.0（与鸿蒙版同源基线，便于两侧对搬）
#
# 用法：
#   ./build_android_mpv.sh deps           只拉依赖源码
#   ./build_android_mpv.sh armv7l         编 armeabi-v7a（Android 5.0 老设备）
#   ./build_android_mpv.sh arm64          编 arm64-v8a
#   ./build_android_mpv.sh all            两个 ABI 都编
# ═══════════════════════════════════════════════════════════════════════════
set -o pipefail

ROOT="/workspace/code/HeinPlay/.mpv-android"
BS="$ROOT/src/mpv-android/buildscripts"
LOGS="$ROOT/logs"
mkdir -p "$LOGS"

# API 21：Android 5.0，tvLegacy 的最低目标。
export APILVL="${APILVL:-21}"
export JOBS="${JOBS:-4}"

# 【为什么要自带 meson】官方 mpv-android 依赖 fontconfig 2.18.3，其 meson.build
# 声明 `meson_version: '>= 1.11.0'`，而本机系统 meson 仅 1.7.0，会在 fontconfig
# 处直接报错中断。系统 meson 不能动（鸿蒙版构建仍在用它），故在本工程 tools/ 下
# 放一份独立的 meson 1.12.1，仅在本脚本内 PATH 前置生效。
export PATH="$ROOT/tools:$PATH"
echo "meson: $(meson --version)（本工程独立版，系统版 $(/usr/bin/meson --version)）"

TARGET="${1:-all}"
LOG="$LOGS/build_${TARGET}_$(date +%Y%m%d_%H%M%S).log"

echo "[$(date)] 安卓 mpv 交叉编译开始 target=$TARGET API=$APILVL"
echo "日志: $LOG"
echo "NDK : $(readlink -f "$BS/sdk/android-ndk-r27")"
echo

cd "$BS" || exit 1

build_one() {
  local arch="$1"
  echo "──────── 编译 $arch (API $APILVL) ────────"
  ./buildall.sh --arch "$arch" mpv
}

case "$TARGET" in
  deps)
    ./include/download-deps.sh
    ;;
  armv7l|arm64)
    build_one "$TARGET"
    ;;
  all)
    build_one armv7l
    build_one arm64
    ;;
  *)
    echo "未知目标: $TARGET（可用: deps / armv7l / arm64 / all）" >&2
    exit 1
    ;;
esac

ret=$?
echo "=== BUILD EXIT: $ret ==="
[ "$TARGET" = "all" ] || [ "$TARGET" = "armv7l" ] || [ "$TARGET" = "arm64" ] && {
  echo "产物:"
  ls -lh "$BS/prefix"/*/lib/libmpv.so* 2>/dev/null
}
exit $ret
