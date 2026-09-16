const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // 1. Dependency from package manager (httpz)
    const httpz_dep = b.dependency("httpz", .{
        .target = target,
        .optimize = optimize,
    });

    // 2. Export Server Framework Module ("mnemezigot")
    const mnemezigot_mod = b.addModule("mnemezigot", .{
        .root_source_file = b.path("src/mnemezigot.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    mnemezigot_mod.addImport("httpz", httpz_dep.module("httpz"));
    mnemezigot_mod.addCSourceFile(.{
        .file = b.path("c/sqlite3.c"),
        .flags = &.{
            "-std=c99",
            "-DSQLITE_THREADSAFE=1",
            "-DSQLITE_ENABLE_FTS5",
            "-DSQLITE_ENABLE_JSON1",
            "-DSQLITE_DEFAULT_WAL_SYNCHRONOUS=1",
        },
    });
    mnemezigot_mod.addIncludePath(b.path("c"));

    // 3. Export WASM Client Framework Module ("mnemezigot_client")
    _ = b.addModule("mnemezigot_client", .{
        .root_source_file = b.path("src/client.zig"),
    });

    // 4. Framework Unit Tests (`zig build test`)
    const main_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/mnemezigot.zig"),
            .target = target,
            .optimize = optimize,
            .link_libc = true,
        }),
    });
    main_tests.root_module.addImport("httpz", httpz_dep.module("httpz"));
    main_tests.root_module.addCSourceFile(.{
        .file = b.path("c/sqlite3.c"),
        .flags = &.{
            "-std=c99",
            "-DSQLITE_THREADSAFE=1",
            "-DSQLITE_ENABLE_FTS5",
            "-DSQLITE_ENABLE_JSON1",
            "-DSQLITE_DEFAULT_WAL_SYNCHRONOUS=1",
        },
    });
    main_tests.root_module.addIncludePath(b.path("c"));

    const run_main_tests = b.addRunArtifact(main_tests);
    const test_step = b.step("test", "Run framework unit tests");
    test_step.dependOn(&run_main_tests.step);
}
