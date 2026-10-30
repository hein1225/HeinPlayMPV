#!/bin/bash -e

. ../../include/path.sh

if [ "$1" == "build" ]; then
	true
elif [ "$1" == "clean" ]; then
	rm -rf _build$ndk_suffix
	exit 0
else
	exit 255
fi

mkdir -p _build$ndk_suffix
cd _build$ndk_suffix

cpu=armv7-a
[[ "$ndk_triple" == "aarch64"* ]] && cpu=armv8-a
[[ "$ndk_triple" == "x86_64"* ]] && cpu=generic
[[ "$ndk_triple" == "i686"* ]] && cpu="i686 --disable-asm"

cpuflags=
[[ "$ndk_triple" == "arm"* ]] && cpuflags="$cpuflags -mfpu=neon -mcpu=cortex-a8"

args=(
	--target-os=android --enable-cross-compile
	--cross-prefix=$ndk_triple- --cc=$CC --pkg-config=pkg-config --nm=llvm-nm
	--arch=${ndk_triple%%-*} --cpu=$cpu
	--extra-cflags="-I$prefix_dir/include $cpuflags" --extra-ldflags="-L$prefix_dir/lib"

	# 【本工程改造】--disable-vulkan -> --enable-vulkan
	#
	# 上游禁用是因为 API 21 无 libvulkan。本工程 minSdk=24，故启用。
	# 作用：编出 hwcontext_vulkan，供 hwdec=vulkan 走 Vulkan 硬解互操作。
	# 注：mpv 的 `vo=gpu-next` + `gpu-api=vulkan` 渲染路线由 libplacebo 直接
	# 实现，不依赖这里；但启用后可用 `--hwaccel=vulkan` 与 vulkan hwdec。
	# Vulkan 头（vulkan/vulkan.h）由 NDK sysroot 提供（API>=24 才有 stub）。
	--enable-{jni,mediacodec,mbedtls,libdav1d,libxml2,vulkan}
	--disable-static --enable-shared --enable-{gpl,version3}

	# disable unneeded parts
	--disable-{stripping,doc,programs}
	# to keep the build lean we disable some feature quite aggressively:
	# - muxers, encoders: mpv-android does not have any way to use these
	# - devices: no practical use on Android
	--disable-{muxers,encoders,devices}
	# useful to taking screenshots
	--enable-encoder=mjpeg,png
	# useful for the `dump-cache` command
	--enable-muxer=mov,matroska,mpegts
)
../configure "${args[@]}"

make -j$cores
make DESTDIR="$prefix_dir" install
