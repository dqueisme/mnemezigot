const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // 1. Build Frontend WASM (target: wasm32-freestanding)
    const wasm_target = b.resolveTargetQuery(.{
        .cpu_arch = .wasm32,
        .os_tag = .freestanding,
    });

    // Optimize WASM for minimal size (ReleaseSmall)
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

    // Output directly to frontend/static/app.wasm
    const install_wasm = b.addInstallArtifact(wasm, .{
        .dest_dir = .{ .override = .{ .custom = "../frontend/static" } },
    });

    const wasm_step = b.step("wasm", "Build frontend WASM module");
    wasm_step.dependOn(&install_wasm.step);

    // 2. Build Backend Server (target: host native)
    const server = b.addExecutable(.{
        .name = "server",
        .root_module = b.createModule(.{
            .root_source_file = b.path("backend/src/main.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });

    b.installArtifact(server);

    // Make default `zig build` build both wasm and server
    b.getInstallStep().dependOn(&install_wasm.step);

    // 3. Run Server step (`zig build run`)
    const run_cmd = b.addRunArtifact(server);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the backend server");
    run_step.dependOn(&run_cmd.step);
}
