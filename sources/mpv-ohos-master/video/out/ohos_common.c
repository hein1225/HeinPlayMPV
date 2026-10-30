/*
 * This file is part of mpv.
 *
 * mpv is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Lesser General Public
 * License as published by the Free Software Foundation; either
 * version 2.1 of the License, or (at your option) any later version.
 *
 * mpv is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU Lesser General Public License for more details.
 *
 * You should have received a copy of the GNU Lesser General Public
 * License along with mpv.  If not, see <http://www.gnu.org/licenses/>.
 */

#include "ohos_common.h"
#include "common/msg.h"
#include "video/mp_image.h"
#include "osdep/timer.h"
#include "osdep/threads.h"
#include "vo.h"

#include <string.h>


struct vo_ohos_state {
    struct mp_log *log;
    OHNativeWindow *native_window;
    bool color_space_valid;
    OH_NativeBuffer_ColorSpace color_space;
    bool metadata_type_valid;
    OH_NativeBuffer_MetadataType metadata_type;
    bool static_metadata_valid;
    bool hdr_brightness_valid;
    float hdr_brightness;

    // ── VSync 节流（2026-10-29 回退：改回第八版「自造 60Hz 栅格」）──
    //
    // 【为什么回退】2026-10-28 第十一次修正曾把这里换成「系统 OH_NativeVSync
    // 真实上屏时间戳」，2026-10-29 真机复测证明**更差**，已回退：
    //
    //   指标          第八版    第九版    方案A(实测)
    //   est-fps       55.1~58.4  52.6     46.2~57.7 / 63.0~65.9
    //   jitter        0.73       1.13      0.90~1.56
    //   drop(vo)/分   81         122       ~161 / ~202
    //   delayed/分    34         60        ~288 / ~262
    //   mistimed/分   122        177       ~415 / ~457
    //
    // 根因（源码 + SDK 头文件 + 真机日志三方互证）：
    //   ① **时钟域不同源**。OH_NativeVSync 走「系统硬件 vsync 通道」
    //      （本机面板 120Hz），而 mpv 的 display-sync 闭环要的是
    //      **Flutter 合成器的实际出帧节奏（60Hz）**。两者不是同一个时钟域，
    //      拿前者的差值当「显示周期」喂给 vo.c 估计器，等于喂错时钟。
    //      表现为 vsync_samples 差值忽大忽小 → jitter 0.9~1.56 → 估计器
    //      失去参考 → delayed/mistimed/drop 全面恶化。
    //   ② **上报语义错位**。vo.h:291 要求 last_queue_display_time 是
    //      「本帧预计上屏时刻」（未来时刻）；方案A 上报的是「已经过去的
    //      vsync 事件时刻」，语义相反。
    //   ③ **双重节流**。Vulkan FIFO 下 vkQueuePresentKHR 本身已阻塞到
    //      vblank；方案A 又在 get_vsync 里无条件等一次系统 vsync 回调，
    //      等于每帧多等一个周期 → 实际帧率被拖低。
    //   ④ **单位自校验从未真正验证过**。方案A 的两条自校验日志用的是
    //      MP_VERBOSE，而播放器 logLevel=Info ⇒ 这两条**永远不会打印**，
    //      验收标准第 6 条从一开始就不可能被满足（本次日志中确实没有
    //      `NativeVSync timestamp unit: scale=` 与 `clock offset=`）。
    //
    // 【第八版的两条铁律，继续保留】
    //   1. 栅格是纯计数器，只按 period 前进，绝不吸收真实时间误差。
    //      过冲由下一帧 wait 变小自然补偿，不需要也不允许重锚。
    //   2. 上报的必须是栅格时刻（预计上屏时刻），不是函数返回时刻。
    //      这样 vsync_samples 恒等于 period、jitter≈0，
    //      check_estimated_display_fps 永远不会夺权。
    //
    // 【本轮新增】把栅格的关键量提到 MP_INFO 级（Info 就能看到），
    // 下轮真机可直接判定「栅格是否脱钩」，不必再靠 est-fps 反推。
    int64_t vsync_period_ns;   // 一个显示周期（纳秒）
    int64_t next_vsync_ns;     // 下一个栅格时刻（纯计数器，只按 period 前进）
    // 诊断计数（MP_INFO 级输出用）
    int64_t diag_calls;        // get_vsync 调用次数
    int64_t diag_skips;        // 触发「跳过整周期」的次数
    int64_t diag_max_lag_ns;   // 观测到的最大落后量
};

static bool is_hdr(const struct pl_color_space *color)
{
    return color->transfer == PL_COLOR_TRC_PQ ||
           color->transfer == PL_COLOR_TRC_HLG;
}

static OH_NativeBuffer_ColorSpace get_color_space(
    const struct pl_color_space *color)
{
    if (color->transfer == PL_COLOR_TRC_PQ)
        return OH_COLORSPACE_DISPLAY_BT2020_PQ;
    if (color->transfer == PL_COLOR_TRC_HLG)
        return OH_COLORSPACE_DISPLAY_BT2020_HLG;
    return OH_COLORSPACE_DISPLAY_SRGB;
}

static OH_NativeBuffer_StaticMetadata get_static_metadata(
    const struct pl_color_space *color)
{
    struct pl_raw_primaries prim = color->hdr.prim;
    if (!pl_primaries_valid(&prim)) {
        const struct pl_raw_primaries *container =
            pl_raw_primaries_get(color->primaries);
        if (!container)
            container = pl_raw_primaries_get(PL_COLOR_PRIM_BT_2020);
        prim = *container;
    }

    return (OH_NativeBuffer_StaticMetadata){
        .smpte2086 = {
            .displayPrimaryRed = {prim.red.x, prim.red.y},
            .displayPrimaryGreen = {prim.green.x, prim.green.y},
            .displayPrimaryBlue = {prim.blue.x, prim.blue.y},
            .whitePoint = {prim.white.x, prim.white.y},
            .maxLuminance = color->hdr.max_luma,
            .minLuminance = color->hdr.min_luma,
        },
        .cta861 = {
            .maxContentLightLevel = color->hdr.max_cll,
            .maxFrameAverageLightLevel = color->hdr.max_fall,
        },
    };
}

static void set_output_color(struct vo_ohos_state *ctx,
                             struct pl_color_space color)
{
    pl_color_space_infer(&color);

    bool hdr = is_hdr(&color);
    OH_NativeBuffer_ColorSpace color_space = get_color_space(&color);
    OH_NativeBuffer_MetadataType metadata_type = hdr
        ? (color.transfer == PL_COLOR_TRC_HLG ? OH_VIDEO_HDR_HLG
                                              : OH_VIDEO_HDR_HDR10)
        : OH_VIDEO_NONE;
    float hdr_brightness = hdr ? 1.0f : 0.0f;

    if (!ctx->color_space_valid || ctx->color_space != color_space) {
        int ret = OH_NativeWindow_SetColorSpace(ctx->native_window, color_space);
        if (ret == 0) {
            ctx->color_space = color_space;
            ctx->color_space_valid = true;
            MP_VERBOSE(ctx, "NativeWindow output switched to %s\n",
                       hdr ? (color.transfer == PL_COLOR_TRC_HLG
                                  ? "BT.2020 HLG" : "BT.2020 PQ")
                           : "sRGB");
        } else {
            MP_WARN(ctx, "Failed to set NativeWindow color space: %d\n", ret);
        }
    }

    bool metadata_type_changed = !ctx->metadata_type_valid ||
                                 ctx->metadata_type != metadata_type;
    if (metadata_type_changed) {
        int ret = OH_NativeWindow_SetMetadataValue(
            ctx->native_window, OH_HDR_METADATA_TYPE, sizeof(metadata_type),
            (uint8_t *)&metadata_type);
        if (ret == 0) {
            ctx->metadata_type = metadata_type;
            ctx->metadata_type_valid = true;
        } else {
            MP_WARN(ctx, "Failed to set NativeWindow HDR metadata type: %d\n",
                    ret);
        }
    }

    if (hdr && (metadata_type_changed || !ctx->static_metadata_valid)) {
        OH_NativeBuffer_StaticMetadata metadata = get_static_metadata(&color);
        int ret = OH_NativeWindow_SetMetadataValue(
            ctx->native_window, OH_HDR_STATIC_METADATA, sizeof(metadata),
            (uint8_t *)&metadata);
        if (ret == 0) {
            ctx->static_metadata_valid = true;
        } else {
            MP_WARN(ctx, "Failed to set NativeWindow HDR static metadata: %d\n",
                    ret);
        }
    } else if (!hdr) {
        ctx->static_metadata_valid = false;
    }

    if (!ctx->hdr_brightness_valid || ctx->hdr_brightness != hdr_brightness) {
        int ret = OH_NativeWindow_NativeWindowHandleOpt(
            ctx->native_window, SET_HDR_WHITE_POINT_BRIGHTNESS, hdr_brightness);
        if (ret == 0) {
            ctx->hdr_brightness = hdr_brightness;
            ctx->hdr_brightness_valid = true;
        } else {
            MP_WARN(ctx, "Failed to set NativeWindow HDR brightness: %d\n", ret);
        }
    }
}

bool vo_ohos_init(struct vo *vo)
{
    vo->ohos = talloc_zero(vo, struct vo_ohos_state);
    struct vo_ohos_state *ctx = vo->ohos;

    *ctx = (struct vo_ohos_state){
        .log = mp_log_new(ctx, vo->log, "ohos"),
    };

    if (vo->opts->WinID == 0 || vo->opts->WinID == -1) {
        MP_FATAL(ctx, "Missing surface pointer\n");
        goto fail;
    }

    uint64_t surface = 0;
    memcpy(&surface, &vo->opts->WinID, sizeof(vo->opts->WinID));
    OH_NativeWindow_CreateNativeWindowFromSurfaceId(surface, &ctx->native_window);
    if (!ctx->native_window) {
        MP_FATAL(ctx, "Failed to create OHNativeWindow\n");
        goto fail;
    }

    // VSync 周期：优先用 display-fps-override（本平台下发的是合成率 60），
    // 否则兜底 60Hz。这个 period 同时是「栅格步长」和「上报给 vo.c 的
    // 显示周期估计」，两者必须同源，否则估计器会拿错时钟。
    double fps = vo->opts->display_fps_override;
    if (fps <= 0)
        fps = 60.0;
    ctx->vsync_period_ns = (int64_t)(1e9 / fps);

    // 栅格从 0 起（首次 get_vsync 时按真实时间锚定），纯计数器只按 period 前进。
    ctx->next_vsync_ns = 0;
    ctx->diag_calls = 0;
    ctx->diag_skips = 0;
    ctx->diag_max_lag_ns = 0;

    // 🔴 MP_INFO 级（不是 VERBOSE）：Info 就能在真机日志里看到，
    // 避免「验收标准要求的诊断行因为日志级别不够而永远不打印」。
    MP_INFO(ctx, "VSync driver=self-grid period=%.3fms (%.2fHz) "
                 "(display-fps-override=%.1f)\n",
            ctx->vsync_period_ns / 1e6, 1e9 / ctx->vsync_period_ns, fps);

    return true;
fail:
    talloc_free(ctx);
    vo->ohos = NULL;
    return false;
}

void vo_ohos_uninit(struct vo *vo)
{
    struct vo_ohos_state *ctx = vo->ohos;
    if (!ctx)
        return;

    if (ctx->native_window)
        OH_NativeWindow_DestroyNativeWindow(ctx->native_window);

    talloc_free(ctx);
    vo->ohos = NULL;
}

// 🔴🔴🔴 2026-10-29 回退：改用第八版「自造 60Hz 栅格」。
//
// 【为什么回退方案A】见结构体里的对照表与四条根因，核心是：
//   OH_NativeVSync 是**系统硬件 vsync 通道**（本机面板 120Hz），
//   而 mpv display-sync 闭环要的是 **Flutter 合成器的出帧节奏（60Hz）**。
//   时钟域不同源 ⇒ 喂给 vo.c 估计器的差值忽大忽小 ⇒ jitter 0.9~1.56、
//   delayed/mistimed/drop 全面恶化。真机复测（2026-10-29）确认比
//   第八/九版更卡。
//
// 【第八版两条铁律，必须保留】
//   1. 栅格是纯计数器，只按 period 前进，绝不吸收真实时间误差。
//      过冲由下一帧 wait 变小自然补偿，不需要也不允许重锚。
//   2. 上报的必须是栅格时刻（预计上屏时刻），不是函数返回时刻。
//      这样 vsync_samples 恒等于 period、jitter≈0，
//      estimated == nominal，check_estimated_display_fps 永远不会夺权。
//
// 【本轮新增】诊断量提到 MP_INFO 级，下轮真机可直接判定栅格是否脱钩，
// 不用再靠 est-fps 反推（第九版/方案A 两次都栽在「反推」上）。


void vo_ohos_get_vsync(struct vo *vo, struct vo_vsync_info *info)
{
    struct vo_ohos_state *ctx = vo->ohos;
    if (!ctx)
        return;

    // 非 display-sync 模式不做节流，交给原有的定时器逻辑。
    if (!VS_IS_DISP(vo->opts->video_sync))
        return;

    int64_t period = ctx->vsync_period_ns;
    if (period <= 0)
        return;

    int64_t now = mp_time_ns();

    // 首次调用：把栅格锚定到当前时刻。
    if (ctx->next_vsync_ns <= 0)
        ctx->next_vsync_ns = now;

    int64_t target = ctx->next_vsync_ns;

    // 仅真正卡住（落后超过一个周期）时整周期跳过，异常路径。
    // ⚠️ 跳的是**栅格**，上报的仍是 target ⇒ vsync_samples 恒等于 period。
    if (now - target > period) {
        int64_t skip = (now - target) / period;
        target += skip * period;
        ctx->diag_skips++;
    }

    // 落后量诊断（栅格落后真实时间多少）。
    int64_t lag = now - target;
    if (lag > ctx->diag_max_lag_ns)
        ctx->diag_max_lag_ns = lag;

    int64_t wait = target - now;
    if (wait > 0)
        mp_sleep_ns(wait);

    // 🔴 上报栅格时刻（预计上屏时刻），**不是**函数返回时刻。
    //    这是第八版能收敛 jitter 的关键，务必不要改成 now。
    info->last_queue_display_time = target;
    info->vsync_duration = period;
    info->skipped_vsyncs = 0;

    // 栅格只从自身前进，绝不吸收真实时间误差。
    ctx->next_vsync_ns = target + period;

    // ── 诊断（MP_INFO 级）：每 120 次调用打一行汇总 ──
    // 【为什么要有】第九版与方案A 两次都只能靠 est-fps/jitter 反推根因，
    // 反推出来的结论一次错一次。本轮把「跳格次数」「最大落后量」直接
    // 暴露出来，下轮真机日志可直接判定：
    //   · skips 长期为 0 且 max-lag < period ⇒ 栅格未脱钩（健康）
    //   · skips 持续增长 ⇒ 栅格与 flip 节奏脱钩，需继续查
    ctx->diag_calls++;
    if (ctx->diag_calls % 120 == 0) {
        MP_INFO(ctx, "VSync grid: calls=%lld skips=%lld max-lag=%.3fms "
                     "period=%.3fms\n",
                (long long)ctx->diag_calls, (long long)ctx->diag_skips,
                ctx->diag_max_lag_ns / 1e6, period / 1e6);
        ctx->diag_skips = 0;
        ctx->diag_max_lag_ns = 0;
    }
}


OHNativeWindow *vo_ohos_native_window(struct vo *vo)
{
    struct vo_ohos_state *ctx = vo->ohos;
    return ctx->native_window;
}

bool vo_ohos_surface_size(struct vo *vo, int *out_w, int *out_h)
{
    struct vo_ohos_state *ctx = vo->ohos;

    int w = vo->opts->ohos_surface_size.w,
        h = vo->opts->ohos_surface_size.h;
    if (!w || !h)
        OH_NativeWindow_NativeWindowHandleOpt(ctx->native_window, GET_BUFFER_GEOMETRY, &h, &w);

    if (w <= 0 || h <= 0) {
        MP_ERR(ctx, "Failed to get height and width.\n");
        return false;
    }
    *out_w = w;
    *out_h = h;
    return true;
}

struct pl_color_space vo_ohos_preferred_csp(struct vo *vo)
{
    const struct pl_color_space color = vo_get_current_params(vo).color;

    if (color.transfer == PL_COLOR_TRC_PQ)
        return pl_color_space_hdr10;
    if (color.transfer == PL_COLOR_TRC_HLG)
        return pl_color_space_bt2020_hlg;
    return pl_color_space_srgb;
}

bool vo_ohos_set_color(struct vo *vo, struct mp_image_params *params)
{
    struct pl_color_space color = params ? params->color
                                         : pl_color_space_srgb;

    if (is_hdr(&color)) {
        color.primaries = PL_COLOR_PRIM_BT_2020;
        pl_color_space_infer(&color);
    } else {
        color = pl_color_space_srgb;
    }

    if (params)
        params->color = color;

    struct pl_color_space window_color = color;
    if (is_hdr(&color)) {
        struct pl_color_space source = vo_get_current_params(vo).color;
        if (source.transfer == color.transfer)
            window_color.hdr = source.hdr;
    }
    set_output_color(vo->ohos, window_color);
    return true;
}

void vo_ohos_invalidate_color(struct vo *vo)
{
    struct vo_ohos_state *ctx = vo->ohos;

    ctx->color_space_valid = false;
    ctx->metadata_type_valid = false;
    ctx->static_metadata_valid = false;
    ctx->hdr_brightness_valid = false;
}
