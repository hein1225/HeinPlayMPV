#!/usr/bin/env bash
# 从本仓库的 Release 资产取回 mpv 依赖，并落地到 HeinPlay 工作树的对应位置。
#
#   bash scripts/fetch_release.sh <tag> [--dest <HeinPlay 目录>] [--only <资产名,资产名>]
#
# 例：
#   bash scripts/fetch_release.sh mpv-v1.4.1 --dest ../HeinPlay
#   bash scripts/fetch_release.sh mpv-v1.4.1 --dest ../HeinPlay --only mpv-headers.tar.gz
#
# 资产名与落地路径的对应关系见 docs/heinplay-integration.md。
set -euo pipefail

TAG="${1:?用法: fetch_release.sh <tag> [--dest <dir>] [--only <assets>]}"
shift || true
DEST="${HEINPLAY_DIR:-}"
ONLY=""
while [ $# -gt 0 ]; do
  case "$1" in
    --dest) DEST="$2"; shift 2;;
    --only) ONLY="$2"; shift 2;;
    *) echo "未知参数: $1" >&2; exit 2;;
  esac
done
[ -n "$DEST" ] || { echo "需要 --dest <HeinPlay 目录>" >&2; exit 2; }

BASE="https://github.com/hein1225/HeinPlayMPV/releases/download/$TAG"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

have() { [ -z "$ONLY" ] || [[ ",$ONLY," == *",$1,"* ]]; }

fetch() { # fetch <资产名>
  local a="$1"
  echo "==> 下载 $a"
  curl -fsSL --retry 3 -o "$TMP/$a" "$BASE/$a"
}

# ---- 校验和（可选但强烈建议）----
if have sha256sums.txt || [ -z "$ONLY" ]; then
  fetch sha256sums.txt || true
  if [ -f "$TMP/sha256sums.txt" ]; then
    ( cd "$TMP" && sha256sum -c sha256sums.txt ) || {
      echo "校验失败：资产与 sha256sums.txt 不一致" >&2; exit 1; }
  fi
fi

apply() { # apply <资产名> <目标目录>
  local a="$1" dst="$2"
  [ -f "$TMP/$a" ] || { echo "缺少资产 $a" >&2; exit 1; }
  mkdir -p "$dst"
  tar -xzf "$TMP/$a" -C "$dst"
  echo "    → $dst"
}

# Android 用 0.41.0 头（与 libmpv.so 同源）；Windows/Linux 用 master 头
if have mpv-headers-android.tar.gz; then
  fetch mpv-headers-android.tar.gz
  apply mpv-headers-android.tar.gz "$DEST/hain_tv/third_party"
fi
if have mpv-headers.tar.gz; then
  fetch mpv-headers.tar.gz
  apply mpv-headers.tar.gz "$DEST/hain_tv/third_party"
fi

for ABI in arm64-v8a armeabi-v7a; do
  A="android-$ABI.tar.gz"
  if have "$A"; then
    fetch "$A"
    # 包内结构为 <abi>/xxx.so → 直接解到 jniLibs/ 下
    mkdir -p "$DEST/hain_tv/android/app/src/main/jniLibs"
    apply "$A" "$DEST/hain_tv/android/app/src/main/jniLibs"
  fi
  A="android-tvlegacy-$ABI.tar.gz"
  if have "$A"; then
    fetch "$A"
    mkdir -p "$DEST/hain_tv_legacy/android/app/src/main/jniLibs"
    apply "$A" "$DEST/hain_tv_legacy/android/app/src/main/jniLibs"
  fi
done

if have windows-mpv-x86_64.tar.gz; then
  fetch windows-mpv-x86_64.tar.gz
  # 包内结构为 mpv-windows/{bin,lib,include} → 解到 third_party/ 下
  apply windows-mpv-x86_64.tar.gz "$DEST/hain_tv/third_party"
fi

if have linux-mpv-x86_64.tar.gz; then
  fetch linux-mpv-x86_64.tar.gz
  apply linux-mpv-x86_64.tar.gz "$DEST/hain_tv/third_party"
fi

if have ohos-mpv-arm64-v8a.tar.gz; then
  fetch ohos-mpv-arm64-v8a.tar.gz
  mkdir -p "$DEST/hain_tv_ohos/ohos/mpv_arkts/libs/arm64-v8a"
  apply ohos-mpv-arm64-v8a.tar.gz "$DEST/hain_tv_ohos/ohos/mpv_arkts/libs/arm64-v8a"
fi

echo
echo "mpv 依赖已就位：$DEST（tag=$TAG）"
