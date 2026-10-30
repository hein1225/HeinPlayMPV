#!/bin/bash
# 监控 mpv 交叉编译，完成后自动替换 so + 构建 hap
set -o pipefail

ROOT=/workspace/code/HeinPlay
MB=$ROOT/.mpv-build
OHOS=$ROOT/hain_tv_ohos
TARGET_SO=$OHOS/ohos/mpv_arkts/libs/arm64-v8a/libmpv.so
NEW_SO=$MB/lycium/usr/mpv/arm64-v8a/lib/libmpv.so

log() { echo "[$(date '+%m-%d %H:%M:%S')] $*"; }

# 精确判断编译进程存活（避免 pgrep -f 自匹配）
build_alive() {
  ps -eo args= 2>/dev/null | grep -E '^bash \./build\.sh mpv$|^/bin/bash \./build\.sh mpv$|^bash build_mpv\.sh$' | grep -qv grep
}

log "=== 监控启动，等待编译进程结束 ==="

for i in $(seq 1 960); do
  if ! build_alive; then
    log "编译进程已退出（第 ${i} 次检查）"
    break
  fi
  sleep 15
done

sleep 5
log "=== 编译结果检查 ==="
tail -20 $MB/logs/run_console.log 2>/dev/null

log "=== 查找 libmpv 产物 ==="
find $MB/lycium/usr/mpv -name 'libmpv*' 2>/dev/null

if [ ! -f "$NEW_SO" ]; then
  log "❌ 未找到 $NEW_SO，编译失败，停止自动构建。"
  log "--- 错误线索 ---"
  grep -E 'build ERROR|ERROR during|BUILD EXIT|请先安装' $MB/logs/run_console.log 2>/dev/null | tail -15
  exit 1
fi

log "✅ 找到产物: $NEW_SO"
ls -lh "$NEW_SO"
file "$NEW_SO"

log "=== 关键符号检查 ==="
NM=$MB/../.deps-staging/toolchain/ohos/ohos-sdk-6.1.0/default/openharmony/native/llvm/bin/llvm-nm
[ -x "$NM" ] || NM=nm
$NM -D "$NEW_SO" 2>/dev/null | grep -iE 'mpv_create|mpv_set_option|OH_NativeWindow|vkCreateSurfaceOHOS|mpv_render_context' | head -10

log "=== 备份旧 so ==="
[ -f "$TARGET_SO" ] && cp "$TARGET_SO" "$TARGET_SO.prebuilt.bak" && log "已备份"

log "=== 替换为专用 so ==="
cp "$NEW_SO" "$TARGET_SO" && log "✅ 替换完成"
ls -lh "$TARGET_SO"; md5sum "$TARGET_SO"

log "=== 开始 flutter build hap ==="
cd $OHOS
source scripts/env_ohos_linux.sh 2>/dev/null
timeout 3000 flutter build hap --release -t lib/main_ohos.dart 2>&1 | tail -30
BUILD_EXIT=${PIPESTATUS[0]}
log "=== flutter build hap EXIT=$BUILD_EXIT ==="

log "=== hap 产物 ==="
find $OHOS -name '*.hap' -newermt '-40 minutes' 2>/dev/null | head -5
ls -lh $OHOS/entry/build/default/outputs/default/*.hap 2>/dev/null

log "=== 全流程结束 ==="
