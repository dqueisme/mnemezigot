const std = @import("std");

/// CLI Watcher / Hot Reload Tool for Mnemezigot Framework
/// Scans source directory for file modifications (.zig) and auto-restarts application.
pub fn main() !void {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print("\n======================================================\n", .{});
    std.debug.print("👀 Mnemezigot CLI Watcher / Hot Reload Tool (Zig 0.16)\n", .{});
    std.debug.print("⚡ Watching current directory for .zig file changes...\n", .{});
    std.debug.print("======================================================\n\n", .{});

    var child_proc: ?std.process.Child = null;

    // Start initial build & run
    child_proc = try spawnApp();

    const io = std.Io.Threaded.global_single_threaded.io();
    var last_check = std.Io.Clock.real.now(io).toMilliseconds();

    while (true) {
        std.Io.sleep(io, std.Io.Duration.fromSeconds(1), .awake) catch {}; // Check every second

        const modified = try checkFileModifications(allocator, ".", last_check);
        if (modified) {
            std.debug.print("\n🔄 [Mnemezigot Watcher] Change detected! Rebuilding server...\n", .{});
            last_check = std.Io.Clock.real.now(io).toMilliseconds();

            if (child_proc) |*proc| {
                proc.kill(io);
                child_proc = null;
            }

            child_proc = spawnApp() catch |err| blk: {
                std.debug.print("❌ [Mnemezigot Watcher] Failed to restart app: {}\n", .{err});
                break :blk null;
            };
        }
    }
}

fn spawnApp() !std.process.Child {
    const io = std.Io.Threaded.global_single_threaded.io();
    const argv = [_][]const u8{ "zig", "build", "run" };
    const proc = try std.process.spawn(io, .{ .argv = &argv });
    std.debug.print("🚀 [Mnemezigot Watcher] Server process started (PID: {?d})\n", .{proc.id});
    return proc;
}

fn checkFileModifications(allocator: std.mem.Allocator, dir_path: []const u8, threshold_ms: i64) !bool {
    const io = std.Io.Threaded.global_single_threaded.io();
    var dir = std.Io.Dir.cwd().openDir(io, dir_path, .{ .iterate = true }) catch return false;
    defer dir.close(io);

    var iter = dir.iterate();
    while (try iter.next(io)) |entry| {
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

            const stat = dir.statFile(io, entry.name, .{}) catch continue;
            const mtime_ms = stat.mtime.toMilliseconds();

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
