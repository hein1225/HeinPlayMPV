#include <dlfcn.h>

#include "common.h"
#include "vkloader.h"

static void *vk_lib_handle;
static PFN_vkGetInstanceProcAddr vk_get_instance_proc_addr;

// Android 的 Vulkan loader 位于 /system/lib[64]/libvulkan.so。
// 这里只按名字 dlopen，交给系统解析，避免写死路径（不同厂商 ROM 路径可能有差异）。
static const char *vk_lib_names[] = {
    "libvulkan.so",
#if defined(__LP64__)
    "libvulkan.so.1",
#endif
};

bool mpvk_loader_open(void)
{
    if (vk_get_instance_proc_addr)
        return true;

    for (int i = 0; i < MP_ARRAY_SIZE(vk_lib_names); i++) {
        vk_lib_handle = dlopen(vk_lib_names[i], RTLD_NOW | RTLD_LOCAL);
        if (vk_lib_handle)
            break;
    }

    if (!vk_lib_handle)
        return false;

    // 立即解析唯一的必需入口点。这一步拿不到就说明设备根本没有可用 Vulkan，
    // 早失败早降级，好过后续拿到空指针再崩。
    vk_get_instance_proc_addr =
        (PFN_vkGetInstanceProcAddr)dlsym(vk_lib_handle, "vkGetInstanceProcAddr");

    if (!vk_get_instance_proc_addr) {
        dlclose(vk_lib_handle);
        vk_lib_handle = NULL;
        return false;
    }

    return true;
}

void mpvk_loader_close(void)
{
    vk_get_instance_proc_addr = NULL;
    if (vk_lib_handle) {
        dlclose(vk_lib_handle);
        vk_lib_handle = NULL;
    }
}

PFN_vkGetInstanceProcAddr mpvk_loader_get_proc_addr(void)
{
    return vk_get_instance_proc_addr;
}

PFN_vkVoidFunction mpvk_get_proc(VkInstance inst, const char *name)
{
    if (!vk_get_instance_proc_addr)
        return NULL;

    return vk_get_instance_proc_addr(inst, name);
}
