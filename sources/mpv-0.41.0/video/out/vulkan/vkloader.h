#pragma once

/*
 * Vulkan 动态加载器（Android 兼容层）
 *
 * 背景：mpv 原先直接链接 libvulkan.so，导致 libmpv.so 的 NEEDED 里出现
 * libvulkan.so，且 NDK 默认开启 BIND_NOW，加载器会在 System.loadLibrary()
 * 阶段强制解析全部 UND 符号。而旧设备（Android 7/8，API 24-27）的系统
 * libvulkan.so 并不导出 vkGetPhysicalDeviceProperties2 /
 * vkGetPhysicalDeviceQueueFamilyProperties2（这两个命令到 Vulkan 1.1 /
 * CDD Android 9 才强制），于是加载期直接 UnsatisfiedLinkError 闪退。
 *
 * fvp(libmdk) 与 legacy 版 mpv 之所以在 Android 7+ 正常，正是因为它们
 * 从不把 libvulkan.so 写进 NEEDED，而是运行时 dlopen 动态取函数。
 *
 * 本文件提供同样的机制：dlopen("libvulkan.so") 取得 vkGetInstanceProcAddr，
 * 再按 Vulkan 规范逐层解析所需命令。这样：
 *   - libmpv.so 不再 NEEDED libvulkan.so
 *   - 加载期无需解析任何 vk* 符号
 *   - 缺符号的设备只在实际走 Vulkan 路径时才失败，且可优雅降级
 */

#include <stdbool.h>
#include <vulkan/vulkan.h>

// 打开系统 Vulkan loader。成功返回 true。
// 失败（设备无 libvulkan.so）时返回 false，调用方应据此降级到 OpenGL。
bool mpvk_loader_open(void);

// 关闭 loader，释放 dlopen 句柄。
void mpvk_loader_close(void);

// 返回由 dlopen 取得的 vkGetInstanceProcAddr；未打开或无此符号时返回 NULL。
PFN_vkGetInstanceProcAddr mpvk_loader_get_proc_addr(void);

// 经 vkGetInstanceProcAddr 解析一个全局/实例级命令。
// inst 可为 VK_NULL_HANDLE（解析全局命令）。符号不存在时返回 NULL。
PFN_vkVoidFunction mpvk_get_proc(VkInstance inst, const char *name);
