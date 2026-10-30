#!/usr/bin/env bash
# 获取官方 mpv-player-windows 的 x86_64 dev 包（libmpv-2.dll + mpv.lib + 头文件）。
#
#   bash build/windows/fetch_mpv_windows.sh [版本号]
#
# 例：bash build/windows/fetch_mpv_windows.sh mpv-dev-x86_64-v3-20261018-git-01e2533f31
#
# ⚠️ libmpv-2.dll 约 124MB，**超过 GitHub 单文件 100MB 上限**，不能进 git 仓库，
#    必须以 Release 资产形式分发（见 scripts/pack_release.sh）。
set -euo pipefail

VER="${1:-mpv-dev-x86_64-v3-20261018-git-01e2533f31}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
DEST="$ROOT/prebuilt/windows"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT

URL="https://sourceforge.net/projects/mpv-player-windows/files/libmpv/${VER}/mpv-dev-x86_64-v3-${VER#mpv-dev-x86_64-v3-}.7z/download"
echo "==> 下载 $VER"
curl -fsSL --retry 3 -o "$TMP/pkg.7z" "$URL"

mkdir -p "$DEST"
if command -v 7z >/dev/null; then
  7z x -y -o"$TMP/x" "$TMP/pkg.7z" >/dev/null
else
  echo "需要 p7zip（7z）来解压 .7z" >&2; exit 1
fi
# 官方包结构：<pkg>/libmpv-2.dll、<pkg>/mpv.lib、<pkg>/include/...
PKG="$(find "$TMP/x" -maxdepth 2 -name 'libmpv-2.dll' -printf '%h\n' | head -1)"
[ -n "$PKG" ] || { echo "包里没找到 libmpv-2.dll" >&2; exit 1; }
mkdir -p "$DEST/bin" "$DEST/lib" "$DEST/include"
cp -L "$PKG/libmpv-2.dll" "$DEST/bin/"
cp -L "$PKG/mpv.lib" "$DEST/lib/" 2>/dev/null || true
cp -rL "$PKG/include" "$DEST/" 2>/dev/null || true
echo "已就位：$DEST"
du -sh "$DEST"
