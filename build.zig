const std = @import("std");

// Although this function looks imperative, it does not perform the build
// directly and instead it mutates the build graph (`b`) that will be then
// executed by an external runner. The functions in `std.Build` implement a DSL
// for defining build steps and express dependencies between them, allowing the
// build runner to parallelize the build automatically (and the cache system to
// know when a step doesn't need to be re-run).
pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const exe = b.addExecutable(.{
        .name = "porterman",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
        }),
        // XXX: Native backend currently crashing due to Zig bug.
        // https://github.com/ziglang/zig/issues/24364
        .use_llvm = true,
    });

    // This declares intent for the executable to be installed into the
    // install prefix when running `zig build` (i.e. when executing the default
    // step). By default the install prefix is `zig-out/` but can be overridden
    // by passing `--prefix` or `-p`.
    b.installArtifact(exe);

    // dvui
    const dvui_dep = b.dependency("dvui", .{
        .target = target,
        .optimize = optimize,
        .backend = .sdl3,
    });
    exe.root_module.addImport("dvui", dvui_dep.module("dvui_sdl3"));

    // zqlite
    const zqlite_dep = b.dependency("zqlite", .{
        .target = target,
        .optimize = optimize,
    });
    exe.linkLibC();
    if (b.systemIntegrationOption("sqlite3", .{})) {
        exe.linkSystemLibrary("sqlite3");
    } else {
        exe.addCSourceFile(.{
            .file = b.path("lib/sqlite3.c"),
            .flags = &[_][]const u8{
                "-DSQLITE_DQS=0",
                "-DSQLITE_DEFAULT_WAL_SYNCHRONOUS=1",
                "-DSQLITE_USE_ALLOCA=1",
                "-DSQLITE_THREADSAFE=1",
                "-DSQLITE_TEMP_STORE=3",
                "-DSQLITE_ENABLE_API_ARMOR=1",
                "-DSQLITE_ENABLE_UNLOCK_NOTIFY",
                "-DSQLITE_ENABLE_UPDATE_DELETE_LIMIT=1",
                "-DSQLITE_DEFAULT_FILE_PERMISSIONS=0600",
                "-DSQLITE_OMIT_DECLTYPE=1",
                "-DSQLITE_OMIT_DEPRECATED=1",
                "-DSQLITE_OMIT_LOAD_EXTENSION=1",
                "-DSQLITE_OMIT_PROGRESS_CALLBACK=1",
                "-DSQLITE_OMIT_SHARED_CACHE",
                "-DSQLITE_OMIT_TRACE=1",
                "-DSQLITE_OMIT_UTF16=1",
                "-DHAVE_USLEEP=0",
            },
        });
    }
    exe.root_module.addImport("zqlite", zqlite_dep.module("zqlite"));

    // This creates a top level step. Top level steps have a name and can be
    // invoked by name when running `zig build` (e.g. `zig build run`).
    // This will evaluate the `run` step rather than the default step.
    // For a top level step to actually do something, it must depend on other
    // steps (e.g. a Run step, as we will see in a moment).
    const run_step = b.step("run", "Run the app");

    // This creates a RunArtifact step in the build graph. A RunArtifact step
    // invokes an executable compiled by Zig. Steps will only be executed by the
    // runner if invoked directly by the user (in the case of top level steps)
    // or if another step depends on it, so it's up to you to define when and
    // how this Run step will be executed. In our case we want to run it when
    // the user runs `zig build run`, so we create a dependency link.
    const run_cmd = b.addRunArtifact(exe);
    run_step.dependOn(&run_cmd.step);

    // By making the run step depend on the default step, it will be run from the
    // installation directory rather than directly from within the cache directory.
    run_cmd.step.dependOn(b.getInstallStep());

    // This allows the user to pass arguments to the application in the build
    // command itself, like this: `zig build run -- arg1 arg2 etc`
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    // Creates an executable that will run `test` blocks from the executable's
    // root module. Note that test executables only test one module at a time,
    // hence why we have to create two separate ones.
    const exe_tests = b.addTest(.{
        .root_module = exe.root_module,
    });

    // A run step that will run the second test executable.
    const run_exe_tests = b.addRunArtifact(exe_tests);

    // A top level step for running all tests. dependOn can be called multiple
    // times and since the two run steps do not depend on one another, this will
    // make the two of them run in parallel.
    const test_step = b.step("test", "Run tests");
    test_step.dependOn(&run_exe_tests.step);
}
