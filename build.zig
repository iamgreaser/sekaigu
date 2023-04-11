const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const wasmExe = buildTarget(
        b,
        std.zig.CrossTarget.parse(.{
            .arch_os_abi = "wasm32-freestanding",
        }) catch unreachable,
        optimize,
    );
    const exe = buildTarget(b, target, optimize);

    wasmExe.install();
    const wasmMod = b.addModule("sekaigu_wasm_bin", .{
        .source_file = wasmExe.getOutputSource(),
    });
    exe.addModule("sekaigu_wasm_bin", wasmMod);
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
        exe_tests.linkSystemLibrary("epoxy");

        const test_step = b.step("test", "Run unit tests");
        test_step.dependOn(&exe_tests.step);
    }
}

pub fn buildTarget(b: *std.Build, target: std.zig.CrossTarget, optimize: std.builtin.Mode) *std.Build.CompileStep {
    var exe = if (target.toTarget().isWasm())
        b.addSharedLibrary(.{
            .name = "sekaigu",
            .root_source_file = .{ .path = "src/main.zig" },
            .target = target,
            .optimize = optimize,
        })
    else
        b.addExecutable(.{
            .name = "sekaigu",
            .root_source_file = .{ .path = "src/main.zig" },
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

            // Libraries to grab:
            // - SDL2 - MinGW development version
            // - libepoxy - build this yourself, zig cc seems to handle it OK?
            //     - We might have to bring this in as a submodule. --GM
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
    exe.linkSystemLibrary("epoxy");

    return exe;
}
