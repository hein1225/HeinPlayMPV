#!/bin/bash
# ═══════════════════════════════════════════════════════════════════════════
# HeinPlay 鸿蒙 mpv 交叉编译入口（支持硬解）
#
# 🔴 2026-10-05 重写：换用 ErBWs 的 OHOS 分支源码以启用 ohcodec 硬解
#   · mpv      : github.com/ErBWs/mpv      @ feat-ohos-0.41.0 (6edeee0)
#   · FFmpeg   : code.ffmpeg.org/ErBWs/FFmpeg @ feat-ohos-n8.0  (+ --enable-ohcodec)
#   · shaderc  : google/shaderc            @ v2025.4（Vulkan 硬解必需的 SPIR-V 编译器）
#
# 用法：
#   ./build_mpv.sh            全流程（FFmpeg → shaderc → mpv）
#   ./build_mpv.sh mpv        只编 mpv
#   ./build_mpv.sh FFmpeg     只编 FFmpeg
#   ./build_mpv.sh shaderc    只编 shaderc
# ═══════════════════════════════════════════════════════════════════════════
set -o pipefail

source /workspace/code/HeinPlay/hain_tv_ohos/scripts/env_ohos_linux.sh 2>/dev/null

export OHOS_SDK="$OHOS_SDK_HOME/default/openharmony"
export LYCIUM_ROOT=/workspace/code/HeinPlay/.mpv-build/lycium
export SRC_ROOT=/workspace/code/HeinPlay/.mpv-build/src

# 三个外部源码目录（均已本地克隆好，lycium 不再下载/解包）
export MPV_SRC_DIR="$SRC_ROOT/mpv-ohos"
export FFMPEG_SRC_DIR="$SRC_ROOT/ffmpeg-ohos"
export SHADERC_SRC_DIR="$SRC_ROOT/shaderc"

# 并行任务数可通过 JOBS 环境变量覆盖（并行编译两条链时降到 2，避免 4 核互相抢）
export MAKE="${MAKE:-make -j${JOBS:-4}}"
export Ninja="${Ninja:-ninja -j${JOBS:-4}}"
export PATH="$OHOS_SDK/native/build-tools/cmake/bin:$PATH"

TARGET="${1:-all}"

cd "$LYCIUM_ROOT" || exit 1

echo "[$(date)] 启动鸿蒙 mpv 交叉编译（$TARGET）"
echo "clang   : $($OHOS_SDK/native/llvm/bin/clang --version | head -1)"
echo "mpv     : $(cd $MPV_SRC_DIR 2>/dev/null && git log --oneline -1 || echo '缺失!')"
echo "ffmpeg  : $(cd $FFMPEG_SRC_DIR 2>/dev/null && git log --oneline -1 || echo '缺失!')"
echo "shaderc : $(cd $SHADERC_SRC_DIR 2>/dev/null && git log --oneline -1 || echo '缺失!')"

LOG=/workspace/code/HeinPlay/.mpv-build/logs/build_$(date +%Y%m%d_%H%M%S).log
echo "日志    : $LOG"
echo

time ./build.sh "$TARGET" 2>&1 | tee "$LOG"
ret=${PIPESTATUS[0]}

echo "=== BUILD EXIT: ${ret} ==="
echo "[$(date)] 编译结束"
exit $ret
