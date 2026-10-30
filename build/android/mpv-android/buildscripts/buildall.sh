#!/bin/bash -e

cd "$( dirname "${BASH_SOURCE[0]}" )"
. ./include/depinfo.sh

cleanbuild=0
nodeps=0
onlydeps=0
target=mpv-android
arch=armv7l

getdeps () {
	varname="dep_${1//-/_}[*]"
	echo ${!varname}
}

wasbuilt () {
	# don't use associative arrays to support bash 3 on macOS (thanks Tim Apple)
	varname="built_${1//-/_}"
	return "${!varname:-1}"
}

markbuilt () {
	varname="built_${1//-/_}"
	declare -g "$varname=0"
}

loadndk () {
	local ndk="$PWD/sdk/android-ndk-${v_ndk}"
	local toolchain=$(echo "$ndk/toolchains/llvm/prebuilt/"*)
	if [ ! -d "$toolchain" ]; then
		echo "Can't find toolchain inside NDK" >&2
		return 1
	fi
	export ANDROID_NDK_ROOT="$ndk"
	export PATH="$toolchain/bin:$ndk:$PWD/sdk/bin:$PATH"
}

loadarch () {
	unset CC CXX CPATH LIBRARY_PATH C_INCLUDE_PATH CPLUS_INCLUDE_PATH
	unset CFLAGS CXXFLAGS CPPFLAGS LDFLAGS
	unset PKG_CONFIG_PATH

	# 【本工程改造】APILVL 由上游的 23 抬到 24：libvulkan 自 API 24 才有
	#   （NDK sysroot 的 libvulkan.so stub 在 API 21/23 下不存在），而本工程
	#   要启用 Vulkan。此处保持 24 = Android 7.0，与主工程 minSdk 一致。
	#
	#   【历史教训】曾一度把它抬到 28，试图让 NDK stub 导出
	#   vkGetPhysicalDeviceProperties2 / vkGetPhysicalDeviceQueueFamilyProperties2。
	#   这是**错误方向**：APILVL 只影响链接所用的 stub，真机运行的始终是
	#   设备自带 /system/lib[64]/libvulkan.so。Android 7/8 设备普遍不导出这两个
	#   Vulkan 1.1 命令，加之 libmpv.so 带 BIND_NOW（NDK 默认加固），加载期必须
	#   解析全部 UND 符号 —— 于是 System.loadLibrary("mpv") 抛
	#   UnsatisfiedLinkError，与 gpu-api 选择无关，GL 路线同样崩溃。
	#
	#   真正的修复是**不再把 libvulkan.so 链接进 libmpv.so**，改为运行时 dlopen
	#   动态取函数（见 video/out/vulkan/vkloader.c 与 meson.build 的 vulkan 段）。
	#   fvp(libmdk) 与旧 mpv 内核同样不 NEEDED libvulkan.so，这正是它们能在
	#   Android 7+ 正常工作的根本原因。修复后本值回到 24 即可。
	local apilvl=${APILVL:-24}
	# ndk_triple: the target triple
	local cc_triple # how the compilers are actually prefixed
	if [[ "$1" == "armv7l" ]]; then
		export ndk_triple=arm-linux-androideabi
		cc_triple=armv7a-linux-androideabi$apilvl
		prefix_name=armv7l
	elif [[ "$1" == "arm64" ]]; then
		export ndk_triple=aarch64-linux-android
		cc_triple=$ndk_triple$apilvl
		prefix_name=arm64
	elif [[ "$1" == "x86" ]]; then
		export ndk_triple=i686-linux-android
		cc_triple=$ndk_triple$apilvl
		prefix_name=x86
	elif [[ "$1" == "x86_64" ]]; then
		export ndk_triple=x86_64-linux-android
		cc_triple=$ndk_triple$apilvl
		prefix_name=x86_64
	else
		echo "Invalid architecture" >&2
		exit 1
	fi
	export ndk_suffix=_$prefix_name
	export prefix_dir="$PWD/prefix/$prefix_name"
	export CC=$cc_triple-clang
	export CXX=$cc_triple-clang++
	# 【本工程改造】追加 -Wl,-z,lazy：NDK r27 的 clang 驱动**默认**给动态库打上
	#   DF_BIND_NOW / DF_1_NOW（实测：不加任何 -z 参数即出现 FLAGS = BIND_NOW、
	#   FLAGS_1 = NOW）。BIND_NOW 会在 dlopen/System.loadLibrary 阶段强制解析
	#   全部 UND 符号，任何一个缺失都直接加载失败。本工程已通过 vkloader
	#   消除了 libvulkan.so 硬依赖（见 meson.build vulkan 段），这里再加上
	#   惰性绑定作为兜底：未来若引入其他设备相关的符号，也不会在加载期炸掉，
	#   而是推迟到真正调用时才失败，便于上层降级。实测 -z,lazy 可精确移除
	#   上述两个标记，且与 mpv 需要的 -Wl,-Bsymbolic 并存无冲突。
	export LDFLAGS="-Wl,-O1,--icf=safe -Wl,-z,max-page-size=16384 -Wl,-z,lazy"
	export AR=llvm-ar
	export RANLIB=llvm-ranlib

	# set up correct paths for pkg-config
	if ! command -v pkg-config >/dev/null; then
		echo "pkg-config is missing!" >&2
		return 1
	fi
	export PKG_CONFIG_SYSROOT_DIR="$prefix_dir"
	export PKG_CONFIG_LIBDIR="$PKG_CONFIG_SYSROOT_DIR/lib/pkgconfig"
}

setup_prefix () {
	if [ ! -d "$prefix_dir" ]; then
		mkdir -p "$prefix_dir"
		# enforce flat structure (/usr/local -> /)
		ln -s . "$prefix_dir/usr"
		ln -s . "$prefix_dir/local"
	fi

	local cpu_family=${ndk_triple%%-*}
	[[ "$cpu_family" == "i686" ]] && cpu_family=x86

	# 【本工程改造】定位预编的 shaderc（Android 版）
	# 目录约定：$SHADERC_ROOT/<prefix_name>/{include,lib/pkgconfig}
	# prefix_name 是 arm64 / armv7l / ... 与 $prefix_dir 末段同名。
	shaderc_root="${SHADERC_ROOT:-/workspace/code/HeinPlay/.mpv-build/shaderc-android/prefix}"
	shaderc_dir="$shaderc_root/$prefix_name"
	if [ -d "$shaderc_dir/lib/pkgconfig" ]; then
		shaderc_pc="$shaderc_dir/lib/pkgconfig"
		shaderc_inc="$shaderc_dir/include"
	else
		shaderc_pc="$prefix_dir/lib/pkgconfig"
		shaderc_inc="$prefix_dir/include"
		printf >&2 '\e[1;33m%s\e[m\n' \
			"WARNING: 未找到预编 shaderc ($shaderc_dir)，Vulkan 着色器编译将不可用"
	fi

	# meson wants to be spoonfed this file, so create it ahead of time
	# also define: release build, static libs and no source downloads at runtime(!!!)
	cat >"$prefix_dir/crossfile.tmp" <<CROSSFILE
[built-in options]
buildtype = 'release'
default_library = 'static'
wrap_mode = 'nodownload'
prefix = '/usr/local'
[binaries]
c = '$CC'
cpp = '$CXX'
ar = 'llvm-ar'
nm = 'llvm-nm'
strip = 'llvm-strip'
pkgconfig = 'pkg-config'
pkg-config = 'pkg-config'
[host_machine]
system = 'android'
cpu_family = '$cpu_family'
cpu = '${CC%%-*}'
endian = 'little'
[properties]
# 【本工程改造】把预编好的 shaderc 暴露给 meson。
# libplacebo 的 Vulkan 后端需要 shaderc 编译 SPIR-V；meson 通过 pkg-config
# 探测它，所以这里必须让 pkg_config_libdir 同时覆盖 shaderc 的 pkgconfig
# 目录（默认只指向本 prefix，看不到外部编好的 shaderc）。
# include 路径也要显式给，否则 src/glsl/spirv_shaderc.c 找不到 shaderc.h。
# shaderc 由 .mpv-build/scripts/build_shaderc_android.sh 用同一 NDK/API 编出。
pkg_config_libdir = '$prefix_dir/lib/pkgconfig:SHADERC_PC_DIR_PLACEHOLDER'
c_args = ['-ISHADERC_INC_DIR_PLACEHOLDER']
cpp_args = ['-ISHADERC_INC_DIR_PLACEHOLDER']
CROSSFILE
	# 把 shaderc 占位符换成实际路径
	if [ -z "$shaderc_inc" ] || [ -z "$shaderc_pc" ]; then
		printf >&2 '\e[1;31m%s\e[m\n' \
			"ERROR: shaderc 路径解析为空 (pc=$shaderc_pc inc=$shaderc_inc)，拒绝生成残缺 crossfile"
		exit 1
	fi
	${SED:-sed} -i \
		-e "s|SHADERC_PC_DIR_PLACEHOLDER|$shaderc_pc|" \
		-e "s|SHADERC_INC_DIR_PLACEHOLDER|$shaderc_inc|" \
		"$prefix_dir/crossfile.tmp"
	# also avoid rewriting it needlessly
	if cmp -s "$prefix_dir"/crossfile.{tmp,txt}; then
		rm "$prefix_dir/crossfile.tmp"
	else
		mv "$prefix_dir"/crossfile.{tmp,txt}
	fi
}

build () {
	if [[ $1 != "mpv-android" && ! -d deps/$1 ]]; then
		printf >&2 '\e[1;31m%s\e[m\n' "Target $1 not found"
		return 1
	fi
	wasbuilt "$1" && return 0
	if [ $nodeps -eq 0 ]; then
		printf >&2 '\e[1;34m%s\e[m\n' "Preparing $1..."
		local deps=$(getdeps $1)
		echo >&2 "Dependencies: $deps"
		for dep in $deps; do
			build $dep
		done
	fi
	printf >&2 '\e[1;34m%s\e[m\n' "Building $1..."
	if [[ "$1" == "mpv-android" ]]; then
		pushd ..
		BUILDSCRIPT=buildscripts/scripts/$1.sh
	else
		pushd deps/$1
		BUILDSCRIPT=../../scripts/$1.sh
	fi
	[ $cleanbuild -eq 1 ] && $BUILDSCRIPT clean
	$BUILDSCRIPT build
	popd
	markbuilt $1
}

usage () {
	printf '%s\n' \
		"Usage: buildall.sh [options] [target]" \
		"Builds the specified target (default: $target)" \
		"" \
		"-n             Do not build dependencies" \
		"--only-deps    Build only dependencies of the specified target" \
		"--clean        Clean build dirs before compiling" \
		"--arch <arch>  Build for specified architecture (default: $arch; supported: armv7l, arm64, x86, x86_64)"
	exit 0
}

while [ $# -gt 0 ]; do
	case "$1" in
		--clean)
		cleanbuild=1
		;;
		-n|--no-deps)
		nodeps=1
		;;
		--only-deps)
		onlydeps=1
		;;
		--arch)
		shift
		arch=$1
		;;
		-h|--help)
		usage
		;;
		-*)
		echo "Unknown flag $1" >&2
		exit 1
		;;
		*)
		target=$1
		;;
	esac
	shift
done

loadndk
loadarch $arch
setup_prefix
if [ $onlydeps -eq 1 ]; then
	deps=$(getdeps $target)
	for dep in $deps; do
		build $dep
	done
else
	build $target
fi

# be helpful and list the output APKs (if they exist)
if wasbuilt "mpv-android"; then
	ls -lh ../app/build/outputs/apk/{default,allstorage}/*/*.apk || :
fi

exit 0
