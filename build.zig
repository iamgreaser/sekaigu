// SPDX-License-Identifier: AGPL-3.0-or-later
const builtin = @import("builtin");
const std = @import("std");
const Build = std.Build;
const CompileStep = Build.CompileStep;
const FileSource = Build.FileSource;

pub fn build(b: *Build) void {
    b.reference_trace = 100;
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Generate modified Unifont 15.0.01 as "sekaigu yunifon JP 15.0.01.0"
    var exeYunifonGen = b.addExecutable(.{
        .name = "yunifongen",
        .root_source_file = FileSource.relative("tools/yunifongen.zig"),
        // The target MUST be native, as we're gonna run this.
        .target = std.zig.CrossTarget.fromTarget(builtin.target),
        // Debug builds run fast enough and also build quickly.
        .optimize = .Debug,
    });
    var runYunifonGen = b.addRunArtifact(exeYunifonGen);
    var fontHex = runYunifonGen.addOutputFileArg("sekaigu_yunifon_jp-15.0.01.0.hex");
    runYunifonGen.addFileSourceArg(FileSource.relative(
        "thirdparty/unifont/unifont_jp-15.0.01.hex",
    ));
    runYunifonGen.addFileSourceArg(FileSource.relative(
        "thirdparty/unifont/unifont_upper-15.0.01.hex",
    ));

    // Generate font atlas
    var exeHex2Atlas = b.addExecutable(.{
        .name = "hex2atlas",
        .root_source_file = FileSource.relative("tools/hex2atlas.zig"),
        // The target MUST be native, as we're gonna run this.
        .target = std.zig.CrossTarget.fromTarget(builtin.target),
        // Debug builds build and run faster than the ReleaseSafe and ReleaseFast versions take to build.
        // The Release* builds do run really fast, but we only need this for one atlas.
        // ReleaseSmall also builds quickly, but doesn't catch undefined behaviour.
        .optimize = .Debug,
    });
    var runHex2Atlas = b.addRunArtifact(exeHex2Atlas);
    runHex2Atlas.addArg(""); // We don't need a PBM output
    var fontRaw = runHex2Atlas.addOutputFileArg("unifont.rgba4444");
    var fontMap = runHex2Atlas.addOutputFileArg("unifont.map");
    runHex2Atlas.addArg("1024"); // Width
    runHex2Atlas.addArg("1024"); // Height
    runHex2Atlas.addArg("12"); // Layers
    runHex2Atlas.addFileSourceArg(fontHex);
    var fontRawMod = b.createModule(.{ .source_file = fontRaw });
    var fontMapMod = b.createModule(.{ .source_file = fontMap });

    // Generate wasm version
    const wasmExe = buildTarget(
        b,
        std.zig.CrossTarget.parse(.{
            .arch_os_abi = "wasm32-freestanding",
        }) catch unreachable,
        optimize,
    );
    wasmExe.addModule("font_raw_bin", fontRawMod);
    wasmExe.addModule("font_map_bin", fontMapMod);
    b.installArtifact(wasmExe);
    const wasmMod = b.createModule(.{
        .source_file = wasmExe.getOutputSource(),
    });

    // Generate native version
    const exe = buildTarget(b, target, optimize);
    exe.addModule("sekaigu_wasm_bin", wasmMod);
    exe.addModule("font_raw_bin", fontRawMod);
    exe.addModule("font_map_bin", fontMapMod);
    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);

    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);
}

pub fn buildTarget(b: *Build, target: std.zig.CrossTarget, optimize: std.builtin.Mode) *CompileStep {
    var exe = if (target.toTarget().isWasm())
        b.addSharedLibrary(.{
            .name = "sekaigu",
            .root_source_file = FileSource.relative("src/main.zig"),
            .target = target,
            .optimize = optimize,
        })
    else
        b.addExecutable(.{
            .name = "sekaigu",
            .root_source_file = FileSource.relative("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .linkage = .dynamic,
        });
    // zig build only strips on ReleaseSmall. I'd like to strip on all Release* things, especially ReleaseSafe --GM
    if (optimize != .Debug) {
        exe.strip = true; // There is no zig build API for this yet AFAIK --GM
    }
    if (target.toTarget().isWasm()) {
        // GH issue #14818 sets .rdynamic. If we don't do that, we don't get our symbols in. --GM
        exe.rdynamic = true;
    }
    switch (target.os_tag orelse builtin.target.os.tag) {
        .windows => {
            // TODO: Add more crap when needed --GM
            // TODO: Look into jettisoning libc --GM
            exe.linkLibC();
            exe.linkSystemLibrary("opengl32");
            exe.linkSystemLibrary("ws2_32");
        },
        .freestanding => {
            // Could be wasm32, if so, disable stack smashing protection as it is currently broken --GM
            exe.stack_protector = false;
        },
        else => {
            exe.linkLibC();
            exe.linkSystemLibrary("GL");
            exe.linkSystemLibrary("X11");

            // Non-native 32-bit builds need these paths for me --GM
            // exe.addIncludePath("/usr/include");
            // exe.addLibraryPath("/usr/lib32");
        },
    }

    return exe;
}
