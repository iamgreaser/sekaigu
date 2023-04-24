const builtin = @import("builtin");
const std = @import("std");
const Build = std.Build;
const CompileStep = Build.CompileStep;
const FileSource = Build.FileSource;

pub fn build(b: *Build) void {
    b.reference_trace = 100;
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

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
    runHex2Atlas.addFileSourceArg(FileSource.relative(
        "indat/unifont/unifont-jp-with-upper-15.0.01.hex",
    ));
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
    wasmExe.install();
    const wasmMod = b.createModule(.{
        .source_file = wasmExe.getOutputSource(),
    });

    // Generate native version
    const exe = buildTarget(b, target, optimize);
    exe.addModule("sekaigu_wasm_bin", wasmMod);
    exe.addModule("font_raw_bin", fontRawMod);
    exe.addModule("font_map_bin", fontMapMod);
    exe.install();

    const run_cmd = exe.run();

    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    // Creates a step for unit testing.
    // FIXME: Doesn't seem to actually work --GM
    if (!target.toTarget().isWasm()) {
        const exe_tests = b.addTest(.{
            .root_source_file = .{ .path = "src/main.zig" },
            .target = target,
            .optimize = optimize,
        });
        exe_tests.addIncludePath("/usr/include/SDL2");
        exe_tests.linkSystemLibrary("c");
        exe_tests.linkSystemLibrary("SDL2");
        exe_tests.linkSystemLibrary("GL");

        const test_step = b.step("test", "Run unit tests");
        test_step.dependOn(&exe_tests.step);
    }
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
    switch (target.os_tag orelse .freestanding) {
        .windows => {
            // FIXME this doesn't link, instead throwing an unsearchable error:
            //     error: lld-link: ___stack_chk_fail was replaced
            // --GM

            // TODO: Update for a direct OpenGL binding which doesn't touch libepoxy --GM

            // Libraries to grab:
            // - SDL2 - MinGW development version
            exe.addIncludePath("./wlibs/include");
            exe.addLibraryPath("./wlibs/lib");

            exe.linkSystemLibrary("kernel32");
            exe.linkSystemLibrary("user32");
            exe.linkSystemLibrary("gdi32");
            exe.linkSystemLibrary("oleaut32");
            exe.linkSystemLibrary("ole32");
            exe.linkSystemLibrary("imm32");
            exe.linkSystemLibrary("winmm");
            exe.linkSystemLibrary("version");
            exe.linkSystemLibrary("setupapi");
            exe.linkSystemLibrary("xinput"); // Not provided by Zig, grab from MinGW-W64, needed for later SDL2 versions
            exe.linkSystemLibrary("SDL2main");
            exe.linkSystemLibrary("mingw32");
        },
        .freestanding => {
            // Could be wasm32, if so, disable stack smashing protection as it is currently broken --GM
            exe.stack_protector = false;
        },
        else => {
            // TODO: Get the actual path properly --GM
            exe.addIncludePath("/usr/include/SDL2");

            // Non-native 32-bit builds need these paths for me --GM
            // exe.addIncludePath("/usr/include");
            // exe.addLibraryPath("/usr/lib32");
        },
    }
    exe.linkSystemLibrary("c");
    exe.linkSystemLibrary("SDL2");
    exe.linkSystemLibrary("GL");

    return exe;
}
