#!/bin/bash -e

. ../../include/path.sh

build=_build$ndk_suffix

if [ "$1" == "build" ]; then
	true
elif [ "$1" == "clean" ]; then
	rm -rf $build
	exit 0
else
	exit 255
fi

unset CC CXX # meson wants these unset

# 【本工程适配】mpv v0.41.0 已**移除 `libcurl` 选项**（上游把网络协议层统一交给
# ffmpeg 的 protocol 实现，curl 不再是独立可选项）。官方 mpv-android 的脚本仍带
# `-Dlibcurl=enabled`，在本版本上会直接报 `ERROR: Unknown option: "libcurl"`。
# 故此处只保留 `-Dlua=enabled`。
#
# 【渲染路线】不加 `-Dvulkan=enabled`：本工程要覆盖 Android 5.0(API 21)，而
# libvulkan 自 API 24 才有。走 GL 路线（`egl-android` 会自动开启 gl 并编入
# `video/out/opengl/context_android.c`），运行时用 `vo=gpu gpu-context=android`。
meson setup $build --cross-file "$prefix_dir"/crossfile.txt \
	--default-library shared \
	-Diconv=disabled -Dlua=enabled \
	-Dlibmpv=true -Dcplayer=false \
	-Dmanpage-build=disabled

ninja -C $build -j$cores
if [ -f $build/libmpv.a ]; then
	echo >&2 "Meson fucked up, forcing rebuild."
	$0 clean
	exec $0 build
fi
DESTDIR="$prefix_dir" ninja -C $build install
