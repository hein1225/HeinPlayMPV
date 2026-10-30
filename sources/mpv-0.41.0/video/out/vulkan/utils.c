#include "video/out/placebo/utils.h"
#include "utils.h"
#include "vkloader.h"

bool mpvk_init(struct mpvk_ctx *vk, struct ra_ctx *ctx, const char *surface_ext)
{
    vk->pllog = mppl_log_create(ctx, ctx->vo->log);
    if (!vk->pllog)
        goto error;

    const char *exts[] = {
        VK_KHR_SURFACE_EXTENSION_NAME,
        surface_ext,
    };

    // libmpv.so 不再链接 libvulkan.so（见 vkloader.h 说明）。这里在运行时
    // dlopen 系统 loader，并把 vkGetInstanceProcAddr 交给 libplacebo，
    // 使其无需依赖直接链接的版本。
    if (!mpvk_loader_open()) {
        mp_err(ctx->vo->log, "Failed to load the Vulkan loader (libvulkan.so). "
               "This device may not support Vulkan.\n");
        goto error;
    }

    mppl_log_set_probing(vk->pllog, true);
    vk->vkinst = pl_vk_inst_create(vk->pllog, &(struct pl_vk_inst_params) {
        .debug = ctx->opts.debug,
        .debug_extra = ctx->opts.debug,
        .get_proc_addr = mpvk_loader_get_proc_addr(),
        .extensions = exts,
        .num_extensions = MP_ARRAY_SIZE(exts),
    });
    mppl_log_set_probing(vk->pllog, false);
    if (!vk->vkinst)
        goto error;

    return true;

error:
    mpvk_uninit(vk);
    return false;
}

void mpvk_uninit(struct mpvk_ctx *vk)
{
    if (vk->surface) {
        mp_assert(vk->vkinst);
        // vkDestroySurfaceKHR 可能在旧设备上缺失；缺失时跳过销毁，
        // 仅泄漏一个 surface（进程退出前无害），避免空指针崩溃。
        PFN_vkDestroySurfaceKHR destroy =
            (PFN_vkDestroySurfaceKHR)mpvk_get_proc(vk->vkinst->instance,
                                                   "vkDestroySurfaceKHR");
        if (destroy)
            destroy(vk->vkinst->instance, vk->surface, NULL);
        vk->surface = VK_NULL_HANDLE;
    }

    pl_vk_inst_destroy(&vk->vkinst);
    pl_log_destroy(&vk->pllog);

    // 所有 vkinst 都已销毁，此时再关闭 loader 句柄才是安全的。
    // 注意：pl_vk_inst 使用期间不能 close，否则函数指针失效。
    mpvk_loader_close();
}
