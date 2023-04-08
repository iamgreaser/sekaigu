const std = @import("std");

// Although this function looks imperative, note that its job is to
// declaratively construct a build graph that will be executed by an external
// runner.
pub fn build(b: *std.Build) void {
    // Standard target options allows the person running `zig build` to choose
    // what target to build for. Here we do not override the defaults, which
    // means any target is allowed, and the default is native. Other options
    // for restricting supported target set are available.
    const target = b.standardTargetOptions(.{});

    // Standard optimization options allow the person running `zig build` to select
    // between Debug, ReleaseSafe, ReleaseFast, and ReleaseSmall. Here we do not
    // set a preferred release mode, allowing the user to decide how to optimize.
    const optimize = b.standardOptimizeOption(.{});

    var exe = b.addExecutable(.{
        .name = "cockel",
        // In this case the main source file is merely a path, however, in more
        // complicated build scripts, this could be a generated file.
        .root_source_file = .{ .path = "src/main.zig" },
        .target = target,
        .optimize = optimize,
    });
    // zig build only strips on ReleaseSmall. I'd like to strip on all Release* things, especially ReleaseSafe --GM
    if (optimize != .Debug) {
        exe.strip = true; // There is no zig build API for this yet AFAIK --GM
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
        },
    }
    exe.linkSystemLibrary("c");
    exe.linkSystemLibrary("SDL2");
    exe.linkSystemLibrary("epoxy");

    // This declares intent for the executable to be installed into the
    // standard location when the user invokes the "install" step (the default
    // step when running `zig build`).
    exe.install();

    // This *creates* a RunStep in the build graph, to be executed when another
    // step is evaluated that depends on it. The next line below will establish
    // such a dependency.
    const run_cmd = exe.run();

    // By making the run step depend on the install step, it will be run from the
    // installation directory rather than directly from within the cache directory.
    // This is not necessary, however, if the application depends on other installed
    // files, this ensures they will be present and in the expected location.
    run_cmd.step.dependOn(b.getInstallStep());

    // This allows the user to pass arguments to the application in the build
    // command itself, like this: `zig build run -- arg1 arg2 etc`
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    // This creates a build step. It will be visible in the `zig build --help` menu,
    // and can be selected like this: `zig build run`
    // This will evaluate the `run` step rather than the default, which is "install".
    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    // Creates a step for unit testing.
    const exe_tests = b.addTest(.{
        .root_source_file = .{ .path = "src/main.zig" },
        .target = target,
        .optimize = optimize,
    });

    // Similar to creating the run step earlier, this exposes a `test` step to
    // the `zig build --help` menu, providing a way for the user to request
    // running the unit tests.
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&exe_tests.step);
}
