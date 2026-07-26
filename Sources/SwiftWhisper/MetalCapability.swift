import Foundation
import whisper_metal

/// What Metal capability is actually available on this machine, as reported by
/// `swiftwhisper_metal_probe()` (Sources/whisper_metal/swiftwhisper-metal-probe.m).
///
/// Consumers (e.g. VoiceType) use this to decide whether CoreML should be
/// allowed to intercept the whisper encoder: on M5-family chips the GPU
/// tensor cores (Metal 4 tensor API) beat the ANE, so CoreML only gets in
/// the way there.
public enum MetalCapability: Int {
    /// Metal is unavailable or not viable (no device / command queue / shader library).
    case unavailable = 0
    /// Metal is alive, but the tensor API is not available.
    case metal = 1
    /// Metal is alive and the tensor API is available.
    case metalWithTensor = 2
}

public enum WhisperMetal {
    /// Probes the Metal device whisper.cpp will actually use and reports which
    /// capability tier it supports. Safe to call before any whisper context is
    /// created — it goes through the same idempotent `ggml_backend_metal_reg()`
    /// entry point whisper itself uses, so it does not create a second Metal
    /// device or pay for a second shader compilation.
    public static func probeCapability() -> MetalCapability {
        let rawValue = Int(swiftwhisper_metal_probe())
        return MetalCapability(rawValue: rawValue) ?? .unavailable
    }
}
