#!/bin/bash
# ============================================================================
# 为 Android 编译启用 Vulkan 的 mpv-android 依赖链（shaderc 已预编）
# ============================================================================
#
# 背景：
#   上游 mpv-android 的 buildall.sh 默认禁用 Vulkan（为覆盖 API 21），本工程
#   主工程 hain_tv 的 minSdk 为 24，可启用 Vulkan（libvulkan 自 API 24 才有）。
#
# 与上游的差异（均在 buildscripts/ 内就地改造，原文件已备份到
# .mpv-build/mpv-android-orig-scripts/）：
#   1. buildall.sh  APILVL 23 -> 24
#   2. buildall.sh  cross-file 注入预编 shaderc 的 pkgconfig / include
#   3. libplacebo.sh  -Dvulkan=disabled -> -Dvulkan=enabled -Dshaderc=enabled
#   4. ffmpeg.sh      --disable-vulkan  -> --enable-vulkan
#   5. mpv.sh         增加 -Dvulkan=enabled（GL 后端保留，运行时二选一）
#
# 前置：先用 build_shaderc_android.sh 编好 shaderc（两 ABI）。
#
# 用法：
#   ./build_mpv_android_vulkan.sh <armv7l|arm64|x86|x86_64> [target]
#   target 默认 mpv；可传 ffmpeg / libplacebo / mpv-android 等
#
# ============================================================================

set -e

ARCH="${1:-arm64}"
TARGET="${2:-mpv}"

BS_ROOT="/workspace/code/HeinPlay/.mpv-android/src/mpv-android"
SHADERC_ROOT="/workspace/code/HeinPlay/.mpv-build/shaderc-android/prefix"
NDK_ROOT="/opt/team/tool-deps/android-sdk/ndk/27.0.12077973"
TEAM_CMAKE_BIN="/opt/team/tool-deps/android-sdk/cmake/3.22.1/bin"
MESON_DIR="/workspace/code/HeinPlay/.mpv-android/tools/meson-1.12.1"

# --- 工具链 ---------------------------------------------------------------
# ninja/cmake 不在系统 PATH，须显式加（meson 要用 ninja 做后端）
export PATH="$TEAM_CMAKE_BIN:$PATH"

# gperf：fontconfig 用它生成 fcobjshash.h。系统与 apt 源都没有，已从源码编好
# 装在 /usr/local/bin（/tmp/gperf-3.1）。缺了它 fontconfig 会转去下载 meson wrap
# 子项目，而 wrap_mode=nodownload 会直接失败：
#   ERROR: Subproject gperf is buildable: NO
#   Automatic wrap-based subproject downloading is disabled
if ! command -v gperf >/dev/null; then
  echo "[env] ⚠️  未找到 gperf，fontconfig 会编译失败" >&2
  echo "[env]     修复：curl -sL https://ftp.gnu.org/gnu/gperf/gperf-3.1.tar.gz | tar xz" >&2
  echo "[env]           && cd gperf-3.1 && ./configure --prefix=/usr/local && make -j4 && make install" >&2
  exit 1
fi
export PATH="/usr/local/bin:$PATH"

# meson 用 vendored 版本（系统无 meson），做成可执行入口
MESON_BIN="/tmp/meson"
cat > "$MESON_BIN" <<EOF
#!/bin/bash
exec python3 "$MESON_DIR/meson.py" "\$@"
EOF
chmod +x "$MESON_BIN"
export PATH="/tmp:$PATH"

# shaderc 位置（供 buildall.sh 的 cross-file 注入）
export SHADERC_ROOT

# ANDROID_NDK_ROOT 由 buildall.sh 的 loadndk 自行设置，此处只确保软链存在
NDK_LINK="$BS_ROOT/buildscripts/sdk/android-ndk-r27"
if [ ! -e "$NDK_LINK" ]; then
  mkdir -p "$(dirname "$NDK_LINK")"
  ln -s "$NDK_ROOT" "$NDK_LINK"
fi

echo "[env] ARCH       = $ARCH"
echo "[env] TARGET     = $TARGET"
echo "[env] NDK        = $NDK_ROOT"
echo "[env] SHADERC    = $SHADERC_ROOT/$ARCH"
echo "[env] ninja      = $(command -v ninja)"
echo "[env] meson      = $MESON_BIN"
echo "[env] pkg-config = $(command -v pkg-config)"

if [ ! -d "$SHADERC_ROOT/$ARCH/lib/pkgconfig" ]; then
  echo "[env] ⚠️  未找到 $ARCH 的 shaderc，Vulkan 着色器编译会失败！" >&2
  echo "[env]     请先运行 build_shaderc_android.sh $ARCH" >&2
  exit 1
fi

# --- 开始构建 -------------------------------------------------------------
cd "$BS_ROOT/buildscripts"
exec ./buildall.sh --arch "$ARCH" "$TARGET"
