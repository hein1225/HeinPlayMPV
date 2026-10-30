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
# 【渲染路线（本工程改造）】启用 Vulkan，同时**保留 GL** 作为运行时回退。
#
# mpv 不把两条路线的支持编成互斥的：`-Dvulkan=enabled` 只是让 meson 探测到
# libplacebo 的 Vulkan 后端并编入 `video/out/vulkan/`，GL/EGL 后端（含
# `context_android.c`）依旧照常编译。运行时由 `gpu-api` 选项在两者间选：
#   · gpu-api=vulkan   -> GPU 走 Vulkan（gpu-context=android 时用
#                         VK_ANDROID_external_memory_android_hardware_buffer 直出）
#   · gpu-api=opengl   -> GPU 走 GLES（默认，gpu-context=android 用 EGL）
# 这样即使设备无 Vulkan 驱动，回退到 GL 仍可出画。
#
# 前置：libplacebo 必须先以 -Dvulkan=enabled 编好（见 libplacebo.sh）。
meson setup $build --cross-file "$prefix_dir"/crossfile.txt \
	--default-library shared \
	-Diconv=disabled -Dlua=enabled \
	-Dlibmpv=true -Dcplayer=false \
	-Dvulkan=enabled \
	-Dmanpage-build=disabled

ninja -C $build -j$cores
if [ -f $build/libmpv.a ]; then
	echo >&2 "Meson fucked up, forcing rebuild."
	$0 clean
	exec $0 build
fi
DESTDIR="$prefix_dir" ninja -C $build install
