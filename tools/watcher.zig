const std = @import("std");

/// CLI Watcher / Hot Reload Tool for Mnemezigot Framework
/// Scans source directory for file modifications (.zig) and auto-restarts application.
pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print("\n======================================================\n", .{});
    std.debug.print("👀 Mnemezigot CLI Watcher / Hot Reload Tool (Zig 0.16)\n", .{});
    std.debug.print("⚡ Watching current directory for .zig file changes...\n", .{});
    std.debug.print("======================================================\n\n", .{});

    var child_proc: ?std.process.Child = null;

    // Start initial build & run
    child_proc = try spawnApp(allocator);

    var last_check = std.time.milliTimestamp();

    while (true) {
        std.Thread.sleep(1 * std.time.ns_per_s); // Check every second

        const modified = try checkFileModifications(allocator, ".", last_check);
        if (modified) {
            std.debug.print("\n🔄 [Mnemezigot Watcher] Change detected! Rebuilding server...\n", .{});
            last_check = std.time.milliTimestamp();

            if (child_proc) |*proc| {
                _ = proc.kill() catch {};
                child_proc = null;
            }

            child_proc = spawnApp(allocator) catch |err| {
                std.debug.print("❌ [Mnemezigot Watcher] Failed to restart app: {}\n", .{err});
                null;
            };
        }
    }
}

fn spawnApp(allocator: std.mem.Allocator) !std.process.Child {
    const argv = [_][]const u8{ "zig", "build", "run" };
    var proc = std.process.Child.init(&argv, allocator);
    try proc.spawn();
    std.debug.print("🚀 [Mnemezigot Watcher] Server process started (PID: {d})\n", .{proc.id});
    return proc;
}

fn checkFileModifications(allocator: std.mem.Allocator, dir_path: []const u8, threshold_ms: i64) !bool {
    var dir = std.fs.cwd().openDir(dir_path, .{ .iterate = true }) catch return false;
    defer dir.close();

    var iter = dir.iterate();
    while (try iter.next()) |entry| {
        if (entry.kind == .directory) {
            if (std.mem.startsWith(u8, entry.name, ".") or std.mem.eql(u8, entry.name, "zig-out") or std.mem.eql(u8, entry.name, "zig-cache")) {
                continue;
            }
            const sub_path = try std.fs.path.join(allocator, &.{ dir_path, entry.name });
            defer allocator.free(sub_path);

            if (try checkFileModifications(allocator, sub_path, threshold_ms)) {
                return true;
            }
        } else if (entry.kind == .file and std.mem.endsWith(u8, entry.name, ".zig")) {
            const file_path = try std.fs.path.join(allocator, &.{ dir_path, entry.name });
            defer allocator.free(file_path);

            const stat = std.fs.cwd().statFile(file_path) catch continue;
            const mtime_ms = @divTrunc(stat.mtime, std.time.ns_per_ms);

            if (mtime_ms > threshold_ms) {
                std.debug.print("📝 [Mnemezigot Watcher] File modified: {s}\n", .{file_path});
                return true;
            }
        }
    }

    return false;
}

test "checkFileModifications scan" {
    const allocator = std.testing.allocator;
    const modified = try checkFileModifications(allocator, "src", 0);
    try std.testing.expect(modified);
}
