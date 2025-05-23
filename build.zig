const std = @import("std");

// Although this function looks imperative, note that its job is to
// declaratively construct a build graph that will be executed by an external
// runner.
pub fn build(b: *std.Build) void {
    const sqliteFolder = "src/sqlite-amalgamation-3490200";
    const sqliteCFile = comptime std.fmt.comptimePrint("{s}/sqlite3.c", .{sqliteFolder});

    // Standard target options allows the person running `zig build` to choose
    // what target to build for. Here we do not override the defaults, which
    // means any target is allowed, and the default is native. Other options
    // for restricting supported target set are available.
    const target = b.standardTargetOptions(.{});

    // Standard optimization options allow the person running `zig build` to select
    // between Debug, ReleaseSafe, ReleaseFast, and ReleaseSmall. Here we do not
    // set a preferred release mode, allowing the user to decide how to optimize.
    const optimize = b.standardOptimizeOption(.{});

    const lib = b.addStaticLibrary(.{
        .name = "mite",
        // In this case the main source file is merely a path, however, in more
        // complicated build scripts, this could be a generated file.
        .root_source_file = b.path("src/mite.zig"),
        .target = target,
        .optimize = optimize,
    });
    lib.addIncludePath(.{ .src_path = .{ .owner = b, .sub_path = sqliteFolder } });

    // This declares intent for the library to be installed into the standard
    // location when the user invokes the "install" step (the default step when
    // running `zig build`).
    b.installArtifact(lib);

    const exe = b.addExecutable(.{
        .name = "mite",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    exe.addIncludePath(.{ .src_path = .{ .owner = b, .sub_path = sqliteFolder } });
    exe.addCSourceFile(.{ .file = .{ .cwd_relative = sqliteCFile } });

    // This declares intent for the executable to be installed into the
    // standard location when the user invokes the "install" step (the default
    // step when running `zig build`).
    b.installArtifact(exe);

    // This *creates* a Run step in the build graph, to be executed when another
    // step is evaluated that depends on it. The next line below will establish
    // such a dependency.
    const run_cmd = b.addRunArtifact(exe);

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

    // Creates a step for unit testing. This only builds the test executable
    // but does not run it.
    const test_mite = b.addTest(.{
        .name = "test-mite",
        .root_source_file = b.path("src/test-mite.zig"),
        .target = target,
        .optimize = optimize,
    });
    test_mite.addIncludePath(.{ .src_path = .{ .owner = b, .sub_path = sqliteFolder } });
    test_mite.addCSourceFile(.{ .file = .{ .cwd_relative = sqliteCFile } });
    b.installArtifact(test_mite);
    const run_test_mite = b.addRunArtifact(test_mite);

    const exe_unit_tests = b.addTest(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    const run_exe_unit_tests = b.addRunArtifact(exe_unit_tests);

    const test_mite_mock_sqlite = b.addTest(.{
        .name = "test-mite-mock_sqlite",
        .root_source_file = b.path("src/test-mite-mock-sqlite.zig"),
        .target = target,
        .optimize = optimize,
    });
    test_mite_mock_sqlite.addIncludePath(.{ .src_path = .{ .owner = b, .sub_path = sqliteFolder } });
    b.installArtifact(test_mite_mock_sqlite);
    const run_test_mite_mock_sqlite = b.addRunArtifact(test_mite_mock_sqlite);

    // Similar to creating the run step earlier, this exposes a `test` step to
    // the `zig build --help` menu, providing a way for the user to request
    // running the unit tests.
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_test_mite.step);
    test_step.dependOn(&run_exe_unit_tests.step);
    test_step.dependOn(&run_test_mite_mock_sqlite.step);

    const install_docs = b.addInstallDirectory(.{
        .source_dir = lib.getEmittedDocs(),
        .install_dir = .prefix,
        .install_subdir = "docs",
    });

    const docs_step = b.step("docs", "Install docs into zig-out/docs");
    docs_step.dependOn(&install_docs.step);
}
