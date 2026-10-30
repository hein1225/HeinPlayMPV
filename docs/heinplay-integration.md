# HeinPlay 消费本仓库的方式

HeinPlay 主仓库**不含任何 mpv 内核文件**（源码、二进制、构建脚本都没有）。
线上构建（GitHub Actions）与本地构建都通过**固定 tag 的 Release 资产**取用预编译内核。

## 一、固定 tag

| tag | 用途 | 对应 mpv 版本 |
|---|---|---|
| `mpv-v1.4.1` | HeinPlay 1.4.1 系列（Android / tvLegacy / 鸿蒙 / Windows / Linux） | Android 0.41.0、鸿蒙 master 2026-09、Windows 20261018、Linux ABI 2.6 |

tag 命名：`mpv-v<HeinPlay 版本>`。HeinPlay 换版本时，**先在本仓库打新的 tag 并发布资产**，
再在 HeinPlay 的 workflow 里把 `MPV_DEPS_TAG` 改成新值 —— 两者的对应关系只以本文件为准。

## 二、Release 资产与落地路径

| 资产 | 落地到 HeinPlay 的位置 | 谁用 |
|---|---|---|
| `mpv-headers.tar.gz` | `hain_tv/third_party/include/mpv/` | Android（`-DMPV_INCLUDE_DIR`）、Windows 桌面壳 |
| `android-arm64-v8a.tar.gz` | `hain_tv/android/app/src/main/jniLibs/arm64-v8a/` | Android 主工程 APK |
| `android-armeabi-v7a.tar.gz` | `hain_tv/android/app/src/main/jniLibs/armeabi-v7a/` | Android 主工程 APK |
| `android-tvlegacy-arm64-v8a.tar.gz` | `hain_tv_legacy/android/app/src/main/jniLibs/arm64-v8a/` | tvLegacy APK |
| `android-tvlegacy-armeabi-v7a.tar.gz` | `hain_tv_legacy/android/app/src/main/jniLibs/armeabi-v7a/` | tvLegacy APK |
| `windows-mpv-x86_64.tar.gz` | `hain_tv/third_party/mpv-windows/` | Windows 便携版 |
| `linux-mpv-x86_64.tar.gz` | `hain_tv/third_party/mpv-linux/` | Linux AppImage |
| `ohos-mpv-arm64-v8a.tar.gz` | `hain_tv_ohos/ohos/mpv_arkts/libs/arm64-v8a/` | 鸿蒙 HAP（本地构建；线上鸿蒙 job 目前只出 unsigned.hap，依赖同样从本仓库取） |
| `sha256sums.txt` | — | 校验 |

## 三、HeinPlay CI 中的消费步骤（约定）

```bash
TAG=mpv-v1.4.1
BASE=https://github.com/hein1225/HeinPlayMPV/releases/download/$TAG
curl -fsSL -o mpv-headers.tar.gz "$BASE/mpv-headers.tar.gz"
tar -xzf mpv-headers.tar.gz -C hain_tv/third_party/   # → third_party/include/mpv/*
```

或直接用本仓库提供的封装：

```bash
bash scripts/fetch_release.sh mpv-v1.4.1 --dest ../HeinPlay
```

## 四、本地开发机

本地开发机（192.168.8.10）本来就保留了完整构建树（`.mpv-android/`、`.mpv-build/`），
本地构建**不需要**下载 Release 资产；Release 资产的存在是为了让 CI 与干净环境能复现同样结果。

## 五、版本升级流程

1. 本仓库：更新源码快照 / 打补丁 → 重新构建各平台产物 → 打新 tag（如 `mpv-v1.4.2`）→ 发布资产。
2. HeinPlay：改 workflow 里的 `MPV_DEPS_TAG` → 触发构建 → 真机验证起播与渲染。
3. 回填 [`versions.md`](versions.md) 的校验值与来源说明。

## 六、兼容性约定

- **头文件必须与 `libmpv.so` 同源**：Android 的 Gradle 用 `-DMPV_INCLUDE_DIR` 显式指定，
  指向 `third_party/include`；历史上曾指向鸿蒙源码树导致 ABI 漂移，禁止再犯。
- **ABI 集合固定为 `arm64-v8a` + `armeabi-v7a`**：与 Flutter release 引擎一致。
- **Windows dll 只能走 Release 资产**：124MB 超过 GitHub 单文件 100MB 上限，入库必被拒。
