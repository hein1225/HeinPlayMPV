# HeinPlayMPV

**HeinPlay 专用的 mpv 内核工程仓库** —— 独立于 [HeinPlay](https://github.com/hein1225/HeinPlay) 主仓库，
把 HeinPlay 各平台（Android / Android TV / Android tvLegacy / HarmonyOS NEXT / Windows / Linux）
用到的 **mpv 内核、移植补丁、构建脚本与预编译产物** 集中收管。

> **为什么要独立**
> mpv 内核的体积（源码 16MB/份、预编译二进制 40MB~124MB/份）、编译链（NDK / lycium 交叉工具链 /
> Vulkan SDK）、以及为鸿蒙做的移植补丁，**与播放器业务代码是完全不同的生命周期**：
> 内核要跨版本跟进上游、要在多个平台间复用同一套补丁，而 HeinPlay 的播放逻辑（起播预热、
> 代理解密、渲染后端选择）要按 1.4.x 迭代。放在一起会让主仓库既臃肿又难以回溯。
>
> **两个仓库的关系**：相互独立（各自版本、各自发版、各自的 CI），又相互关联
> —— HeinPlay 通过**固定 tag 的 Release 资产**消费本仓库的预编译产物，版本号在
> `docs/heinplay-integration.md` 中一一登记，杜绝「用了哪个内核」的含糊。

---

## 一、版本矩阵

| 平台 | mpv 版本 | 来源 | 产物形态 | 产物位置 |
|---|---|---|---|---|
| **Android**（arm64-v8a / armeabi-v7a） | **0.41.0**（`41f6a645` 2025-12-21 Release） | mpv-android 官方 + NDK 构建 | `libmpv.so` + 独立 ffmpeg `.so` + `libshaderc_shared.so` | `prebuilt/android/<abi>/` |
| **HarmonyOS NEXT**（arm64-v8a） | **mpv master**（2026-09-28 快照）+ 鸿蒙移植补丁 | 自建交叉编译链（lycium + shaderc + Vulkan headers） | `libmpv.so`（37MB）+ `libuv.so` | `prebuilt/ohos/arm64-v8a/` |
| **Windows** x64 | **mpv-dev-x86_64-v3-20261018-git-01e2533f31** | mpv-player-windows 官方 dev 包 | `libmpv-2.dll`（124MB）+ `mpv.lib` | **Release 资产**（超 GitHub 单文件 100MB 上限，不能入库） |
| **Linux** x64 | **libmpv ABI 2.6**（master 2026-09-28 自编译） | meson 自建 | `libmpv.so.2` | `prebuilt/linux/x86_64/` |
| **头文件** | mpv master 2026-09 | 上游源码树 | `client.h` / `render.h` / `render_gl.h` | `prebuilt/include/mpv/` |

版本细节、编译参数与校验和见 [`docs/versions.md`](docs/versions.md)。

## 二、目录结构

```
HeinPlayMPV/
├── README.md                     本文件
├── docs/
│   ├── versions.md               各版本来源、编译参数、SHA256
│   └── heinplay-integration.md   HeinPlay 消费本仓库的方式（tag ↔ 资产 ↔ 落地路径）
├── sources/
│   ├── mpv-0.41.0/               Android 用的 mpv 上游源码快照（0.41.0）
│   └── mpv-ohos-master/          鸿蒙用的 mpv 源码快照（master, 已剔除构建输出）
├── patches/                      移植补丁（鸿蒙 Vulkan / libplacebo 扩展 / HeinPlay 定制）
│   ├── mpv_ohos_master.patch
│   ├── libplacebo-ohos-vk-extensions.patch
│   ├── context.c.ohos-vk-extensions.patch
│   ├── vulkan_ohos.h.native-buffer.patch
│   └── heinplay/                 HeinPlay 定制补丁
├── build/
│   ├── android/                  mpv-android 构建（build_android_mpv.sh + mpv-android 源码）
│   ├── ohos/                     鸿蒙交叉编译脚本（build_mpv.sh / watch_and_build.sh / reference）
│   ├── linux/                    Linux meson 自编译脚本
│   └── windows/                  官方 dev 包获取脚本
├── thirdparty/                   第三方依赖（ffmpeg / libplacebo / shaderc / lycium / vulkan-headers）
│                                 —— 只锁版本 + 提供获取脚本，**大体积不入库**
├── prebuilt/                     预编译产物（Android / 鸿蒙 / Linux + 头文件）
└── scripts/
    ├── pack_release.sh           把各平台产物打成 Release 资产
    └── fetch_release.sh          在任意机器上一键取回指定 tag 的资产
```

## 三、预编译产物与 Release 资产

大体积产物（Windows dll、Android 套件）通过 **tag + Release 资产** 分发：

```bash
# 取回某个 tag 的全部资产（CI 与本机通用）
bash scripts/fetch_release.sh mpv-v1.4.1
```

资产清单与固定 tag 见 [`docs/heinplay-integration.md`](docs/heinplay-integration.md)。

> GitHub 的 **100MB 单文件限制只作用于 git 仓库内的文件**，Release 资产单文件上限 2GB ——
> 这正是 `libmpv-2.dll`（124MB）能分发、却不能进 git 仓库的原因。

## 四、各平台构建方法

### Android（NDK）
```bash
cd build/android
bash build_android_mpv.sh          # 产出 arm64-v8a / armeabi-v7a 两套 .so
```

### HarmonyOS NEXT（交叉编译）
```bash
cd build/ohos
bash build_mpv.sh                  # 依赖 thirdparty/ 里的 lycium 工具链，见该目录 README
```
鸿蒙端的移植要点（Vulkan 扩展、原生 buffer、libplacebo 补丁）见 `patches/` 内的补丁头注释。

### Linux（meson）
```bash
bash build/linux/build_mpv_linux.sh
```

### Windows（官方包）
```bash
bash build/windows/fetch_mpv_windows.sh     # 下载官方 mpv-dev 包并解到 prebuilt/windows/
```

## 五、与 HeinPlay 的边界

| 归属 HeinPlayMPV（本仓库） | 归属 HeinPlay（主仓库） |
|---|---|
| mpv 上游源码与移植补丁 | 播放业务逻辑（起播预热、代理解密、渲染后端选择） |
| mpv 预编译二进制与头文件 | Dart 侧 `mpv_backend.dart` 与各平台胶水层（JNI 壳 / ArkTS 桥 / 桌面壳） |
| 各平台 mpv 构建脚本与工具链 | 应用本体（UI、登录、搜索、播放页） |

一句话：**内核归本仓库，胶水归 HeinPlay**，通过固定 tag 的 Release 资产衔接。

## 六、许可

- mpv / libmpv：**LGPL-2.1+**（源码树内 `LICENSE.LGPL` / `LICENSE.GPL`，产物包随附）。
  HeinPlay 以**动态链接**方式使用，用户可自行替换随包分发的 `libmpv-2.dll` / `libmpv.so.2`，
  满足 LGPL 的替换要求。
- libplacebo / ffmpeg / shaderc 等第三方各自的许可见 `thirdparty/README.md`。
