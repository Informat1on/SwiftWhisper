// swift-tools-version:5.5
import PackageDescription

// whisper.cpp v1.7.5 — updated from v1.4.2
// Source layout changed significantly: ggml is now a sub-library with its own
// include/ and src/ trees. We symlink the needed files into Sources/whisper_cpp/
// and point headerSearchPaths at the symlinked directory trees.

var coremlSources: [String] = []
var coremlExclude: [String] = []
var whisperCppLinkerSettings: [LinkerSetting] = []

#if os(Linux)
coremlExclude.append("coreml")
#else
coremlSources = [
    "coreml/whisper-encoder.mm",
    "coreml/whisper-encoder-impl.m",
]
whisperCppLinkerSettings = [
    .linkedFramework("CoreML", .when(platforms: [.macOS, .macCatalyst, .iOS])),
    .linkedFramework("Accelerate", .when(platforms: [.macOS, .macCatalyst, .iOS])),
]
#endif

// Common defines shared by whisper_cpp and whisper_metal
let platformDefines: [CSetting] = [
    .define("GGML_USE_ACCELERATE", .when(platforms: [.macOS, .macCatalyst, .iOS])),
    .define("GGML_USE_METAL", .when(platforms: [.macOS, .macCatalyst, .iOS])),
    // Enable CPU backend in ggml-backend-reg.cpp (registers CPU compute device)
    .define("GGML_USE_CPU"),
    .define("WHISPER_USE_COREML", .when(platforms: [.macOS, .macCatalyst, .iOS])),
    .define("WHISPER_COREML_ALLOW_FALLBACK", .when(platforms: [.macOS, .macCatalyst, .iOS])),
    .define("SWIFT_PACKAGE"),
]

let package = Package(
    name: "SwiftWhisper",
    // whisper.cpp v1.7.5 requires macOS 10.15+ (std::filesystem, MTLGPUFamily, etc.)
    platforms: [
        .macOS(.v10_15),
        .iOS(.v14),
        .watchOS(.v7),
        .tvOS(.v14),
    ],
    products: [
        .library(name: "SwiftWhisper", targets: ["SwiftWhisper"])
    ],
    targets: [
        .target(name: "SwiftWhisper", dependencies: [.target(name: "whisper_cpp")]),

        // ─── whisper_metal ─────────────────────────────────────────────────────────
        // Compiled with -fno-objc-arc because ggml-metal.m uses manual retain/release.
        // The Metal .metal shader is processed as a resource for runtime compilation.
        .target(
            name: "whisper_metal",
            exclude: [
                "ggml_include",
                "ggml_src",
                "include",
            ],
            sources: ["ggml-metal.m"],
            resources: [.process("ggml-metal.metal")],
            publicHeadersPath: "include",
            cSettings: platformDefines + [
                .headerSearchPath("ggml_include"),
                .headerSearchPath("ggml_src"),
                .headerSearchPath("ggml_src/ggml-metal"),
                // Disable ARC: ggml-metal.m uses [obj release] throughout
                .unsafeFlags(["-fno-objc-arc"]),
            ],
            linkerSettings: [
                .linkedFramework("Metal", .when(platforms: [.macOS, .macCatalyst, .iOS])),
                .linkedFramework("Foundation", .when(platforms: [.macOS, .macCatalyst, .iOS])),
            ]
        ),

        // ─── whisper_cpp ───────────────────────────────────────────────────────────
        .target(
            name: "whisper_cpp",
            dependencies: [.target(name: "whisper_metal")],
            exclude: coremlExclude + [
                // header-only symlinked directory trees — not source files
                "ggml_include",
                "ggml_src",
                "whisper_src",
            ],
            sources: [
                // whisper core
                "whisper.cpp",
                // ggml core
                "ggml.c",
                "ggml-alloc.c",
                "ggml-backend.cpp",
                "ggml-backend-reg.cpp",
                "ggml-quants.c",
                "ggml-threading.cpp",
                "gguf.cpp",
                // ggml-cpu
                "ggml-cpu.c",
                "ggml-cpu.cpp",
                "ggml-cpu-aarch64.cpp",
                "ggml-cpu-quants.c",
                "ggml-cpu-traits.cpp",
                "binary-ops.cpp",
                "unary-ops.cpp",
            ] + coremlSources,
            publicHeadersPath: "include",
            cSettings: platformDefines + [
                // ggml public headers (ggml.h, ggml-backend.h, ggml-alloc.h, ggml-cpu.h, gguf.h …)
                .headerSearchPath("ggml_include"),
                // ggml internal/private headers (ggml-impl.h, ggml-backend-impl.h, ggml-common.h …)
                .headerSearchPath("ggml_src"),
                // ggml-cpu internal headers + "ggml-cpu/" relative includes from ggml-quants.c
                .headerSearchPath("ggml_src/ggml-cpu"),
                // ggml-metal public header needed by ggml-backend-reg.cpp
                .headerSearchPath("ggml_src/ggml-metal"),
                // whisper internal headers (whisper-arch.h)
                .headerSearchPath("whisper_src"),
                // CoreML bridge headers
                .headerSearchPath("coreml"),
                // Suppress deprecated warnings from whisper_init_from_file / whisper_init_from_buffer
                // used in Whisper.swift bridge (soft-deprecated in v1.7.5, still functional)
                .unsafeFlags(["-Wno-deprecated-declarations"]),
            ],
            linkerSettings: whisperCppLinkerSettings
        ),

        .testTarget(
            name: "WhisperTests",
            dependencies: [.target(name: "SwiftWhisper")],
            resources: [.copy("TestResources/")]
        )
    ],
    cxxLanguageStandard: .cxx17
)

