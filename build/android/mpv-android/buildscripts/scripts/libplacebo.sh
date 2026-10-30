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

# 【本工程改造】启用 Vulkan + shaderc
#
# 背景：上游默认 `-Dvulkan=disabled`，因为官方 mpv-android 要覆盖 API 21，
# 而 libvulkan 直到 API 24 才存在。本工程主工程 minSdk=24，满足 Vulkan 门槛。
#
# shaderc 是 Vulkan 后端编译 SPIR-V 着色器的必需依赖，缺了它 libplacebo 的
# Vulkan 后端无法工作（src/meson.build 会告警 "Building without any GLSL
# compiler ... but with APIs required that require one (vulkan)"）。
#
# 前置：先用 Android NDK 编好 shaderc，并通过 cross-file 的 `pkg_config_libdir`
# 把它的 pkgconfig 目录暴露给 meson（否则 configure 结果是 shaderc : NO）。
unset CC CXX
meson setup $build --cross-file "$prefix_dir"/crossfile.txt \
	-Dvulkan=enabled -Dshaderc=enabled -Ddemos=false \
	-Dvk-proc-addr=disabled

ninja -C $build -j$cores
DESTDIR="$prefix_dir" ninja -C $build install

# add missing library for static linking
# this isn't "-lstdc++" due to a meson bug: https://github.com/mesonbuild/meson/issues/11300
${SED:-sed} '/^Libs:/ s|$| -lc++|' "$prefix_dir/lib/pkgconfig/libplacebo.pc" -i
