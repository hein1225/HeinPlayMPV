# 第三方依赖（不入库，只锁版本 + 提供获取方式）

mpv 依赖若干体积庞大的第三方工程。它们**与 mpv 内核本身无关**、版本随上游 mpv 要求变动，
因此不在本仓库入库（否则仓库体积会到 GB 级），而是：

1. 在本文件登记**版本与来源**（锁定，避免构建漂移）；
2. 提供获取脚本 `fetch_thirdparty.sh`；
3. 构建产物落到本地目录（默认 `~/.cache/heinplay-mpv/thirdparty/`）。

| 组件 | 版本 | 用途 | 许可 | 大小 |
|---|---|---|---|---|
| ffmpeg | 6.x（Android：mpv-android 锁定版；鸿蒙：自编 `ffmpeg-ohos`） | 解码/封装 | LGPL-2.1+ / GPL | ~120MB 源码 |
| libplacebo | master（≥7.360.1） | mpv 的渲染后端（Vulkan/OpenGL） | LGPL-2.1+ | ~5MB 源码 |
| shaderc | master | libplacebo 的 SPIR-V 着色器编译 | Apache-2.0 | ~430MB 源码 |
| vulkan-headers | 1.4.337 | Vulkan 头（鸿蒙需 ≥1.4.321） | Apache-2.0 | ~5MB |
| lycium | OpenHarmony 交叉编译工具链 | 鸿蒙 NDK 交叉编译 mpv | Apache-2.0 | ~560MB |

## 获取

```bash
bash thirdparty/fetch_thirdparty.sh <组件名> [目标目录]
# 例：
bash thirdparty/fetch_thirdparty.sh libplacebo
bash thirdparty/fetch_thirdparty.sh shaderc
bash thirdparty/fetch_thirdparty.sh vulkan-headers 1.4.337
```

> 鸿蒙端的完整交叉编译链在 HeinPlay 工作机的 `.mpv-build/` 里维护（该目录体积达 GB 级，
> 不适合入库）。该目录的组成、构建顺序与补丁应用方式见 `build/ohos/README.md`。
