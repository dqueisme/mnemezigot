const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{
        .default_target = .{
            .cpu_model = .native,
        },
    });
    const optimize = b.standardOptimizeOption(.{});

    // 1. Build Frontend WASM (target: wasm32-freestanding, optimized for small size)
    const wasm_target = b.resolveTargetQuery(.{
        .cpu_arch = .wasm32,
        .os_tag = .freestanding,
    });

    const wasm_optimize = b.option(std.builtin.OptimizeMode, "wasm-optimize", "WASM optimization mode") orelse .ReleaseSmall;

    const wasm = b.addExecutable(.{
        .name = "app",
        .root_module = b.createModule(.{
            .root_source_file = b.path("frontend/src/main.zig"),
            .target = wasm_target,
            .optimize = wasm_optimize,
            .strip = true,
        }),
    });
    wasm.rdynamic = true;
    wasm.entry = .disabled;

    // Install app.wasm to zig-out/public/app.wasm
    const install_wasm_dist = b.addInstallArtifact(wasm, .{
        .dest_dir = .{ .override = .{ .custom = "public" } },
    });

    // Also install app.wasm to frontend/static/app.wasm for local dev
    const install_wasm_dev = b.addInstallArtifact(wasm, .{
        .dest_dir = .{ .override = .{ .custom = "../frontend/static" } },
    });

    // Install static HTML/JS/CSS to zig-out/public/
    b.installFile("frontend/static/index.html", "public/index.html");
    b.installFile("frontend/static/bridge.js", "public/bridge.js");
    b.installFile("frontend/static/style.css", "public/style.css");

    const wasm_step = b.step("wasm", "Build frontend WASM module");
    wasm_step.dependOn(&install_wasm_dist.step);
    wasm_step.dependOn(&install_wasm_dev.step);

    // 2. httpz dependency from package manager (build.zig.zon)
    const httpz_dep = b.dependency("httpz", .{
        .target = target,
        .optimize = optimize,
    });

    // 3. Build Backend Server (target: host native with CPU features enabled)
    const server = b.addExecutable(.{
        .name = "server",
        .root_module = b.createModule(.{
            .root_source_file = b.path("backend/src/main.zig"),
            .target = target,
            .optimize = optimize,
            .strip = if (optimize != .Debug) true else false,
            .link_libc = true,
        }),
    });
    server.root_module.addImport("httpz", httpz_dep.module("httpz"));

    // Embedded SQLite 3 Amalgamation
    server.root_module.addCSourceFile(.{
        .file = b.path("c/sqlite3.c"),
        .flags = &.{
            "-std=c99",
            "-DSQLITE_THREADSAFE=1",
            "-DSQLITE_ENABLE_FTS5",
            "-DSQLITE_ENABLE_JSON1",
            "-DSQLITE_DEFAULT_WAL_SYNCHRONOUS=1",
        },
    });
    server.root_module.addIncludePath(b.path("c"));

    // Install server binary to zig-out/server (root of output folder)
    const install_server = b.addInstallArtifact(server, .{
        .dest_dir = .{ .override = .{ .custom = "" } },
    });

    b.getInstallStep().dependOn(&install_server.step);
    b.getInstallStep().dependOn(&install_wasm_dist.step);
    b.getInstallStep().dependOn(&install_wasm_dev.step);

    // 4. Run Server step (`zig build run`)
    const run_cmd = b.addRunArtifact(server);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the backend server");
    run_step.dependOn(&run_cmd.step);
}
