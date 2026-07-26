// swift-tools-version:5.9
import PackageDescription

// whisper.cpp v1.9.1 — updated from v1.7.5.
//
// Source layout notes:
//  * ggml/whisper sources are per-file symlinks created by scripts/sync-sources.sh —
//    SwiftPM does not follow *directory* symlinks when collecting a target's
//    sources (the target silently ends up empty).  Directory symlinks are still
//    fine for headerSearchPath, hence ggml_include / ggml_src / whisper_src.
//    arch/arm/* keeps its nesting because of relative includes ("../../quants.h").
//  * CoreML lives in its own target: upstream builds whisper.coreml with ARC,
//    while ggml-metal's ObjC files use manual retain/release.
//  * ggml-metal.metal is a *generated* self-contained copy (headers inlined) —
//    see scripts/sync-metal-shader.sh.  A symlink does not survive SwiftPM
//    resource packaging and the runtime shader compiler has no include path.

var coremlTargets: [Target] = []
var coremlDependencies: [Target.Dependency] = []
var coremlDefines: [CSetting] = []

#if !os(Linux)
coremlDefines = [
    .define("WHISPER_USE_COREML"),
    .define("WHISPER_COREML_ALLOW_FALLBACK"),
]
coremlDependencies = [.target(name: "whisper_coreml")]
coremlTargets = [
    // ─── whisper_coreml ────────────────────────────────────────────────────────
    // Upstream (src/CMakeLists.txt, target whisper.coreml) compiles these three
    // files with ARC enabled — keep them away from the non-ARC Metal target.
    .target(
        name: "whisper_coreml",
        sources: [
            "coreml/whisper-compat.m",
            "coreml/whisper-encoder.mm",
            "coreml/whisper-encoder-impl.m",
        ],
        publicHeadersPath: "include",
        cSettings: [
            .headerSearchPath("coreml"),
            .unsafeFlags(["-fobjc-arc"]),
        ],
        linkerSettings: [
            .linkedFramework("CoreML"),
            .linkedFramework("Foundation"),
        ]
    )
]
#endif

// Defines shared by every C-family target.  Mirrors the Apple branch of the
// upstream CMake build (ggml/src/CMakeLists.txt, src/CMakeLists.txt); deliberately
// omits GGML_SHARED / GGML_BACKEND_SHARED (we link statically) and -mcpu=native
// (a native build would SIGILL on older Apple Silicon).
let platformDefines: [CSetting] = [
    .define("GGML_USE_ACCELERATE", .when(platforms: [.macOS, .macCatalyst, .iOS])),
    .define("ACCELERATE_NEW_LAPACK", .when(platforms: [.macOS, .macCatalyst, .iOS])),
    .define("ACCELERATE_LAPACK_ILP64", .when(platforms: [.macOS, .macCatalyst, .iOS])),
    .define("GGML_USE_METAL", .when(platforms: [.macOS, .macCatalyst, .iOS])),
    .define("GGML_USE_CPU"),
    .define("GGML_USE_CPU_REPACK"),
    .define("GGML_SCHED_MAX_COPIES", to: "4"),
    .define("_DARWIN_C_SOURCE", .when(platforms: [.macOS, .macCatalyst, .iOS])),
    .define("_XOPEN_SOURCE", to: "600"),
    .define("SWIFT_PACKAGE"),
    // CMake generates these from the ggml project version / git describe; ggml.c
    // returns them from ggml_version()/ggml_commit() and does not compile without.
    // Keep in sync with whisper.cpp/ggml/CMakeLists.txt on every submodule bump.
    .define("GGML_VERSION", to: "\"0.15.1\""),
    .define("GGML_COMMIT", to: "\"f049fff9\""),
    .define("WHISPER_VERSION", to: "\"1.9.1\""),
]

let package = Package(
    name: "SwiftWhisper",
    // whisper.cpp v1.9.1 requires macOS 13+ (Metal 3 device APIs, std::filesystem).
    platforms: [
        .macOS(.v13),
        .iOS(.v16),
        .watchOS(.v9),
        .tvOS(.v16),
    ],
    products: [
        .library(name: "SwiftWhisper", targets: ["SwiftWhisper"])
    ],
    targets: [
        .target(name: "SwiftWhisper", dependencies: [.target(name: "whisper_cpp")]),

        // ─── whisper_metal ─────────────────────────────────────────────────────────
        // ggml-metal-context.m / ggml-metal-device.m use manual retain/release, so the
        // whole target is compiled with -fno-objc-arc (harmless for the .cpp files).
        .target(
            name: "whisper_metal",
            exclude: [
                "ggml_include",
                "ggml_src",
                "include",
            ],
            sources: [
                "ggml-metal.cpp",
                "ggml-metal-common.cpp",
                "ggml-metal-context.m",
                "ggml-metal-device.m",
                "ggml-metal-device.cpp",
                "ggml-metal-ops.cpp",
            ],
            resources: [.process("ggml-metal.metal")],
            publicHeadersPath: "include",
            cSettings: platformDefines + [
                .headerSearchPath("ggml_include"),
                .headerSearchPath("ggml_src"),
                .headerSearchPath("ggml_src/ggml-metal"),
                .unsafeFlags(["-fno-objc-arc"]),
            ],
            linkerSettings: [
                .linkedFramework("Metal", .when(platforms: [.macOS, .macCatalyst, .iOS])),
                .linkedFramework("MetalKit", .when(platforms: [.macOS, .macCatalyst, .iOS])),
                .linkedFramework("Foundation", .when(platforms: [.macOS, .macCatalyst, .iOS])),
            ]
        ),

        // ─── whisper_cpp ───────────────────────────────────────────────────────────
        .target(
            name: "whisper_cpp",
            dependencies: [.target(name: "whisper_metal")] + coremlDependencies,
            exclude: [
                // symlinked directory trees — reached explicitly through `sources`
                "ggml_include",
                "ggml_src",
                "whisper_src",
                "coreml",
            ],
            sources: [
                // whisper core
                "whisper.cpp",
                // ggml core
                "ggml.c",
                "ggml.cpp",
                "ggml-alloc.c",
                "ggml-backend.cpp",
                "ggml-backend-meta.cpp",
                "ggml-backend-reg.cpp",
                "ggml-backend-dl.cpp",
                "ggml-opt.cpp",
                "ggml-quants.c",
                "ggml-threading.cpp",
                "gguf.cpp",
                // ggml-cpu
                "ggml-cpu.c",
                "ggml-cpu.cpp",
                "binary-ops.cpp",
                "unary-ops.cpp",
                "ops.cpp",
                "quants.c",
                "repack.cpp",
                "traits.cpp",
                "vec.cpp",
                "hbm.cpp",
                // ggml-cpu, ARM-specific kernels
                "arch/arm/quants.c",
                "arch/arm/repack.cpp",
            ],
            publicHeadersPath: "include",
            cSettings: platformDefines + coremlDefines + [
                .headerSearchPath("ggml_include"),
                .headerSearchPath("ggml_src"),
                .headerSearchPath("ggml_src/ggml-cpu"),
                .headerSearchPath("ggml_src/ggml-metal"),
                .headerSearchPath("whisper_src"),
                .headerSearchPath("coreml"),
                // whisper_init_from_file / whisper_init_from_buffer are soft-deprecated
                // upstream but still the API the Swift bridge uses.
                .unsafeFlags(["-Wno-deprecated-declarations"]),
            ],
            linkerSettings: [
                .linkedFramework("Accelerate", .when(platforms: [.macOS, .macCatalyst, .iOS])),
            ]
        ),

        .testTarget(
            name: "WhisperTests",
            dependencies: [.target(name: "SwiftWhisper")],
            resources: [.copy("TestResources/")]
        )
    ] + coremlTargets,
    cxxLanguageStandard: .cxx17
)
