const std = @import("std");
const mn = @import("mnemezigot");
const tui = mn.tui;

pub fn main() !void {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const w = tui.stdoutWriter();

    // 1. Clear Screen
    try tui.Screen.clear(w);

    // 2. Build TUI Layout
    var b = tui.Builder.init(allocator);
    defer b.deinit();

    _ = try b.title("🚀 MNEMEZIGOT TUI DASHBOARD");
    _ = try b.badge(.success, "ONLINE");
    _ = try b.newline();

    _ = try b.keyVal("Framework", "Mnemezigot (Zig 0.16.0)");
    _ = try b.keyVal("Memory Footprint", "< 12 MB");
    _ = try b.keyVal("Database Engine", "SQLite 3.46 WAL");
    _ = try b.newline();

    _ = try b.box(.{
        .title = "Cluster Node Overview",
        .border = .rounded,
        .border_color = .cyan,
    }, "Node #1: Active | CPU: 12% | Latency: 1.1ms\nNode #2: Active | CPU: 18% | Latency: 1.3ms\nNode #3: Active | CPU: 15% | Latency: 1.0ms");

    _ = try b.newline();
    _ = try b.subtitle("📊 Microservices Status");

    var tbl = tui.Table.init(allocator);
    defer tbl.deinit();
    try tbl.setHeaders(&.{ "Service", "Protocol", "Port", "Status", "Uptime" });
    try tbl.addRow(&.{ "Web UI (WASM)", "HTTP/1.1", "8080", "Healthy", "99.98%" });
    try tbl.addRow(&.{ "REST Gateway", "HTTP/JSON", "8080", "Healthy", "99.99%" });
    try tbl.addRow(&.{ "gRPC-Web Hub", "Protobuf", "8080", "Healthy", "100.00%" });

    var tbl_buf: std.ArrayList(u8) = .empty;
    defer tbl_buf.deinit(allocator);
    const tbl_writer = tui.bufferWriter(allocator, &tbl_buf);
    try tbl.render(tbl_writer);

    _ = try b.text(tbl_buf.items);

    _ = try b.subtitle("📦 Resource Saturation");
    _ = try b.progress(72, 100, .{ .width = 25, .fill_color = .green });
    _ = try b.newline();

    try b.render(w);
}
