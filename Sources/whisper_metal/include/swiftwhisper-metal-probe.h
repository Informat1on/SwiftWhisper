// swiftwhisper-metal-probe.h — fork-owned addition, not part of upstream ggml/whisper.cpp.
//
// Answers "which Metal capability is actually available on this machine" without
// paying for (or duplicating) a second Metal device init. See
// swiftwhisper-metal-probe.m for the full rationale and the required call order.

#pragma once

#ifdef __cplusplus
extern "C" {
#endif

// 0 = Metal unavailable or not viable (no device / queue / shader library)
// 1 = Metal is alive, tensor API not available
// 2 = Metal is alive, tensor API available
int swiftwhisper_metal_probe(void);

#ifdef __cplusplus
}
#endif
