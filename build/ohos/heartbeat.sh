#!/bin/bash
cd /workspace/code/HeinPlay/.mpv-build
while true; do
  TS=$(date '+%m-%d %H:%M:%S')
  ALIVE=$(ps -eo args= 2>/dev/null | grep -E '^bash \./build\.sh mpv$|^/bin/bash \./build\.sh mpv$' | grep -cv grep)
  LAST=$(tail -1 logs/run_console.log 2>/dev/null | head -c 120)
  OCOUNT=$(find thirdparty/FFmpeg/FFmpeg-arm64-v8a-build -name '*.o' 2>/dev/null | wc -l)
  if [ "$ALIVE" -gt 0 ]; then
    echo "[$TS] 编译中 | FFmpeg目标文件=$OCOUNT | 末尾: $LAST" >> logs/heartbeat.log
  else
    if [ -f lycium/usr/mpv/arm64-v8a/lib/libmpv.so ]; then
      echo "[$TS] 编译已结束 | ✅ libmpv.so 已产出" >> logs/heartbeat.log
    else
      echo "[$TS] ⚠️ 编译已停止但无产物 | 末尾: $LAST" >> logs/heartbeat.log
      grep -E 'build ERROR|请先安装|ERROR during' logs/run_console.log 2>/dev/null | tail -5 >> logs/heartbeat.log
    fi
    break
  fi
  sleep 120
done
