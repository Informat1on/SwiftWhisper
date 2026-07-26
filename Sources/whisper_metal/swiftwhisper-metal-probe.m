// swiftwhisper-metal-probe.m — fork-owned addition, not part of upstream ggml/whisper.cpp.
// A real file (not a per-file symlink like its ggml-metal-*.m siblings in this
// target) — scripts/sync-sources.sh --check only tracks the upstream symlink
// list and must not touch this file.
//
// Why this exists: VoiceType needs to know, before it decides whether to let
// CoreML intercept the whisper encoder, whether Metal's tensor API (Metal 4,
// M5-family GPU tensor cores) is actually available. On M5 that path beats the
// ANE, so CoreML should get out of the way; on everything before M5 it should
// not. There is no public ggml API for "give me the capability of the device
// whisper will actually use" — only ggml_backend_metal_reg(), which is the
// correct, idempotent entry point (see ggml-metal.cpp) but doesn't expose the
// props struct through the public C API. So we go through the same device the
// backend registry will hand to whisper, and read the private props struct
// off it.
//
// Call order below is load-bearing, not stylistic — see the header comments
// on each step for why:
//
//  1. ggml_backend_metal_reg() — idempotent (static bool initialized, under a
//     mutex; see ggml-metal.cpp:908). Safe to call from a probe before whisper
//     ever touches Metal, and guaranteed to be the SAME device whisper later
//     uses. Do NOT use ggml_metal_device_get(0) instead: despite the name it
//     is not a singleton accessor — ggml-metal-device.cpp:20-26
//     unconditionally does devs.emplace_back(ggml_metal_device_init(device)),
//     so every call creates a brand-new Metal device (full shader
//     recompilation, ~5.8s) that lives in a static until atexit.
//  2. ggml_backend_reg_dev_count(reg) > 0 — MUST be checked before
//     ggml_backend_reg_dev_get(reg, 0). With GGML_METAL_DEVICES=0 the device
//     count is legitimately zero and dev_get on an empty registry asserts.
//  3. ggml_backend_reg_dev_get(reg, 0) — the ggml_backend_dev_t.
//  4. dev->context — this is the ggml_metal_device_t. There is no public
//     accessor for it (the registry's get_proc_address only exposes
//     ggml_backend_get_features), so we read the private
//     struct ggml_backend_device layout from ggml-backend-impl.h directly.
//     ⚠️ This is coupled to that struct's field order/layout. Re-verify this
//     cast against ggml-backend-impl.h on every whisper.cpp submodule bump.
//  5. Command queue and shader library must both be non-NULL. This is the
//     step that actually proves Metal is alive: ggml_metal_device_get_queue()
//     and ggml_metal_device_get_library() (ggml-metal-device.h) wrap state
//     that ggml-metal-device.m creates independently of the checks above —
//     on failure they only GGML_LOG_ERROR and leave the pointer NULL, they do
//     not fail step 1-4. Skipping this step is exactly how a previous session
//     shipped a build that believed Metal worked while it was silently dead.
//  6. Only now read ggml_metal_device_get_props(mdev)->has_tensor.

#import "ggml-metal.h"          // ggml_backend_metal_reg
#import "ggml-backend.h"        // ggml_backend_reg_dev_count/get, ggml_backend_dev_t
#import "ggml-backend-impl.h"   // struct ggml_backend_device (dev->context) — see note above
#import "ggml-metal-device.h"   // ggml_metal_device_get_queue/get_library/get_props

#include "swiftwhisper-metal-probe.h"

int swiftwhisper_metal_probe(void) {
    ggml_backend_reg_t reg = ggml_backend_metal_reg();
    if (reg == NULL) {
        return 0;
    }

    // Must precede dev_get: an empty registry (e.g. GGML_METAL_DEVICES=0)
    // makes index 0 invalid and ggml_backend_reg_dev_get asserts on it.
    if (ggml_backend_reg_dev_count(reg) == 0) {
        return 0;
    }

    ggml_backend_dev_t dev = ggml_backend_reg_dev_get(reg, 0);
    if (dev == NULL) {
        return 0;
    }

    // dev->context is a ggml_metal_device_t. No public accessor exists for
    // it — see the header comment above about why this private-struct read
    // is necessary and what to recheck on every whisper.cpp bump.
    ggml_metal_device_t mdev = (ggml_metal_device_t)dev->context;
    if (mdev == NULL) {
        return 0;
    }

    // The device handle existing is not proof Metal works: the queue and
    // shader library are created independently and only log on failure
    // (ggml-metal-device.m), leaving these NULL without affecting anything
    // checked above. This is the real liveness check.
    if (ggml_metal_device_get_queue(mdev) == NULL) {
        return 0;
    }
    if (ggml_metal_device_get_library(mdev) == NULL) {
        return 0;
    }

    const struct ggml_metal_device_props *props = ggml_metal_device_get_props(mdev);
    if (props == NULL) {
        return 1;
    }

    return props->has_tensor ? 2 : 1;
}
