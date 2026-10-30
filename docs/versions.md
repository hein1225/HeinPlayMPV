# 版本、来源与校验

本文件登记本仓库收录的每一份 mpv 内核的**来源、版本、编译参数与校验值**。
HeinPlay 主仓库的 CI 依赖这里的登记来固定「用哪个内核」。

---

## Android —— mpv 0.41.0（mpv-android 官方 + NDK 自编）

| 项 | 值 |
|---|---|
| mpv 源码 | `mpv-player/mpv` tag `0.41.0`，commit `41f6a645068483470267271e1d09966ca3b9f413`（2025-12-21） |
| 源码位置 | `sources/mpv-0.41.0/` |
| 包装工程 | `build/android/mpv-android/`（mpv-android 官方 app + buildscripts，不含 `deps/`、`prefix/`） |
| 构建脚本 | `build/android/build_android_mpv.sh` |
| NDK | r27（mpv-android buildscripts 默认） |
| ABI | `arm64-v8a`、`armeabi-v7a`（**不含 x86/x86_64**：Flutter release 引擎无对应产物，出 x86 包会出现「能装上但 mpv 后端加载失败」） |
| 产物 | `prebuilt/android/<abi>/`：`libmpv.so`、`libavcodec.so`、`libavformat.so`、`libavfilter.so`、`libavutil.so`、`libavdevice.so`、`libswresample.so`、`libswscale.so`、`libshaderc_shared.so` |
| 额外说明 | `libshaderc_shared.so` 是 mpv → libplacebo → Vulkan 渲染链的必需依赖（shaderc），缺它 mpv 的 Vulkan 输出会起不来 |
| 头文件 | `prebuilt/include/mpv/`（与 `libmpv.so` 同源，禁止换成别处版本） |

## HarmonyOS NEXT —— mpv master + 鸿蒙移植补丁

| 项 | 值 |
|---|---|
| mpv 源码 | `mpv-player/mpv` master 快照（2026-09-28），源码位置 `sources/mpv-ohos-master/`（已剔除 `arm64-v8a-build/` 构建输出） |
| 移植补丁 | `patches/mpv_ohos_master.patch`（鸿蒙适配主线）<br>`patches/libplacebo-ohos-vk-extensions.patch`（libplacebo 鸿蒙 Vulkan 扩展）<br>`patches/context.c.ohos-vk-extensions.patch`、`patches/vulkan_ohos.h.native-buffer.patch`（上下文与原生 buffer 修正）<br>`patches/heinplay/`（HeinPlay 定制） |
| 交叉工具链 | lycium（OpenHarmony NDK 交叉编译）—— 见 `thirdparty/README.md`，体积大不入库 |
| 第三方 | shaderc、vulkan-headers（1.4.337）、libplacebo —— 同上 |
| 构建脚本 | `build/ohos/build_mpv.sh`（主）、`watch_and_build.sh`（增量监视）、`heartbeat.sh`、`scripts/`、`reference/`（参考工程） |
| 产物 | `prebuilt/ohos/arm64-v8a/libmpv.so`（37MB）、`libuv.so` |
| 说明 | 鸿蒙侧 mpv 能正常跑 Vulkan（2026-10 实测），无需移植到其他渲染后端 |

## Windows x64 —— 官方 mpv-dev 包

| 项 | 值 |
|---|---|
| 来源 | mpv-player-windows（SourceForge） |
| 版本 | `mpv-dev-x86_64-v3-20261018-git-01e2533f31`（2026-10-18） |
| 内容 | `bin/libmpv-2.dll`（124MB）、`lib/mpv.lib`、`include/mpv/*.h` |
| 分发方式 | **Release 资产**（dll 124MB > GitHub 单文件 100MB 上限） |
| 获取脚本 | `build/windows/fetch_mpv_windows.sh` |

## Linux x64 —— 自编译 libmpv

| 项 | 值 |
|---|---|
| 源码 | `mpv-player/mpv` master（2026-09-28） |
| 版本 | libmpv **ABI 2.6**（`libmpv.so.2.6.0`） |
| 构建参数 | `meson setup build -Dprefix=/usr/local --buildtype=release -Dlibmpv=true -Dcplayer=false -Dbuild-date=false -Dlua=disabled -Djavascript=disabled -Dtests=false -Dvulkan=enabled -Dgl=enabled -Degl-x11=enabled -Dx11=enabled` |
| 构建脚本 | `build/linux/build_mpv_linux.sh` |
| 依赖（Debian 13） | `libavcodec-dev libavformat-dev libavfilter-dev libavutil-dev libswscale-dev libswresample-dev libass-dev libplacebo-dev libvulkan-dev libgl1-mesa-dev libegl1-mesa-dev libx11-dev libwayland-dev libxkbcommon-dev libuchardet-dev libjpeg-dev libarchive-dev libdrm-dev libgbm-dev libva-dev libvdpau-dev python3-jinja2 meson ninja-build` |
| 关键坑 | libplacebo 需 **≥7.360.1**（mpv master 硬性要求），Debian 13 自带 7.349.0 **不够**，须自行编译；Vulkan 头需 **≥1.4.321**（`VkSwapchainPresentFenceInfoKHR`） |
| 产物 | `prebuilt/linux/x86_64/libmpv.so.2` + `mpv.pc`（pkg-config 模板见 `linux/mpv.pc.in`） |

## 校验值

各 Release 资产的 SHA256 随资产一并发布（`sha256sums.txt`）。HeinPlay CI 下载后必须校验：

```bash
sha256sum -c sha256sums.txt
```
