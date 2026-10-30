#!/bin/bash
# ============================================================================
# 用 Android NDK 编译 shaderc（libplacebo Vulkan 后端所需的 SPIR-V 编译器）
# ============================================================================
#
# 为什么需要：
#   libplacebo 的 Vulkan 后端要把 GLSL 编成 SPIR-V，依赖 shaderc。
#   缺了它 meson configure 结果是 `shaderc : NO`，并告警：
#     "Building without any GLSL compiler (shaderc, glslang), but with APIs
#      required that require one (vulkan, d3d11)."
#
# 为什么不用 .mpv-build 里那份：
#   已有的 shaderc 是**鸿蒙产物**（用 ohos.toolchain.cmake、含 OHOS 标记），
#   Android 不可用，必须用 NDK 重编。
#
# 产物：.mpv-build/shaderc-android/prefix/<abi>/{include,lib}
#   · libshaderc_combined.a —— libplacebo 静态链接用
#
# 坑：
#   shaderc 的 CMake 默认生成 Unix Makefiles（不是 Ninja），别用 ninja 调。
#   glslc/test 会被 SHADERC_ENABLE_TESTS 拉进来但缺 spirv-dis 目标，
#   必须用 SHADERC_SKIP_TESTS=ON 关掉，否则 Generate 阶段直接失败。
#
# 用法：./build_shaderc_android.sh <arm64-v8a|armeabi-v7a>
# ============================================================================

set -e

ABI="${1:-arm64-v8a}"
case "$ABI" in
  arm64-v8a)   ANDROID_ABI=arm64-v8a;   EXTRA="" ;;
  armeabi-v7a) ANDROID_ABI=armeabi-v7a; EXTRA="-DANDROID_ARM_NEON=ON" ;;
  *) echo "不支持的 ABI: $ABI（支持 arm64-v8a / armeabi-v7a）" >&2; exit 1 ;;
esac

NDK="/opt/team/tool-deps/android-sdk/ndk/27.0.12077973"
SRC="/workspace/code/HeinPlay/.mpv-build/src/shaderc"
OUT="/workspace/code/HeinPlay/.mpv-build/shaderc-android"
API=24

export PATH="/opt/team/tool-deps/android-sdk/cmake/3.22.1/bin:$PATH"

echo "[shaderc] ABI=$ANDROID_ABI API=$API"
echo "[shaderc] 源码 = $SRC"

# 清理旧的鸿蒙构建目录干扰（shaderc 源码树里那份 arm64-v8a-build）
cmake -S "$SRC" -B "$OUT/$ABI" \
  -DCMAKE_TOOLCHAIN_FILE="$NDK/build/cmake/android.toolchain.cmake" \
  -DANDROID_ABI="$ANDROID_ABI" \
  -DANDROID_PLATFORM="android-$API" \
  $EXTRA \
  -DCMAKE_BUILD_TYPE=Release \
  -DSHADERC_ENABLE_WERROR_COMPILE=OFF \
  -DSHADERC_SKIP_TESTS=ON \
  -DSHADERC_SKIP_EXAMPLES=ON \
  -DSHADERC_SKIP_COPYRIGHT_CHECK=ON \
  -DSHADERC_ENABLE_INSTALL=ON \
  -DSPIRV_SKIP_TESTS=ON \
  -DSPIRV_SKIP_EXECUTABLES=ON \
  -DCMAKE_INSTALL_PREFIX="$OUT/prefix/$ABI"

# 注意是 make 不是 ninja（cmake 默认生成 Unix Makefiles）
make -C "$OUT/$ABI" -j"$(nproc)"
make -C "$OUT/$ABI" install

echo "[shaderc] 完成 -> $OUT/prefix/$ABI"
ls -la "$OUT/prefix/$ABI/lib/libshaderc_combined.a"
