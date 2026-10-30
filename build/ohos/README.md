# 鸿蒙（HarmonyOS NEXT）mpv 交叉编译

本目录是 HeinPlay 工作机上 `.mpv-build/` 的**可入库部分**：构建脚本、参考工程与移植补丁说明。
体积庞大的部分（lycium 交叉工具链、shaderc、vulkan-headers、ffmpeg-ohos 源码、构建输出）不入库，
获取方式见 [`../../thirdparty/README.md`](../../thirdparty/README.md)。

## 组成

| 文件 | 作用 |
|---|---|
| `build_mpv.sh` | 主构建脚本（交叉编译 mpv → libmpv.so） |
| `watch_and_build.sh` | 增量监视源码变化并重建（开发用） |
| `heartbeat.sh` | 构建心跳/保活脚本 |
| `scripts/` | 构建辅助脚本 |
| `reference/` | 参考工程（5.8MB） |
| `mpv-android-orig-scripts/` | 早期从 mpv-android 借用的脚本 |
| `CMakeLists.txt.experimental-official-20261006.bak` | 官方版 CMake 的备份 |

## 补丁

移植补丁集中在仓库根 `patches/`：

- `mpv_ohos_master.patch` —— 鸿蒙适配主线
- `libplacebo-ohos-vk-extensions.patch` —— libplacebo 的鸿蒙 Vulkan 扩展
- `context.c.ohos-vk-extensions.patch`、`vulkan_ohos.h.native-buffer.patch` —— 上下文与原生 buffer 修正
- `patches/heinplay/` —— HeinPlay 定制补丁

## 产物

`prebuilt/ohos/arm64-v8a/libmpv.so`（37MB）+ `libuv.so`。
鸿蒙端 mpv **能正常跑 Vulkan**，不需要移植到其它渲染后端。
