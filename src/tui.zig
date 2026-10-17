const std = @import("std");

pub const style = @import("tui/style.zig");
pub const Color = style.Color;
pub const Style = style.Style;
pub const BufferWriter = style.BufferWriter;
pub const bufferWriter = style.bufferWriter;
pub const StdoutWriter = style.StdoutWriter;
pub const stdoutWriter = style.stdoutWriter;
pub const writeStyled = style.writeStyled;
pub const resetAnsi = style.resetAnsi;

pub const terminal = @import("tui/terminal.zig");
pub const WindowSize = terminal.WindowSize;
pub const getWindowSize = terminal.getWindowSize;
pub const Cursor = terminal.Cursor;
pub const Screen = terminal.Screen;

pub const box = @import("tui/box.zig");
pub const BorderStyle = box.BorderStyle;
pub const BoxConfig = box.BoxConfig;
pub const TitleAlign = box.TitleAlign;
pub const renderBox = box.render;
pub const stringWidth = box.stringWidth;

pub const table = @import("tui/table.zig");
pub const Table = table.Table;
pub const Alignment = table.Alignment;

pub const widgets = @import("tui/widgets.zig");
pub const BadgeVariant = widgets.BadgeVariant;
pub const badge = widgets.badge;
pub const progressBar = widgets.progressBar;
pub const ProgressBarConfig = widgets.ProgressBarConfig;
pub const spinner = widgets.spinner;
pub const SpinnerStyle = widgets.SpinnerStyle;
pub const list = widgets.list;
pub const ListType = widgets.ListType;
pub const keyVal = widgets.keyVal;

pub const prompt = @import("tui/prompt.zig");
pub const confirm = prompt.confirm;
pub const ask = prompt.ask;

pub const builder = @import("tui/builder.zig");
pub const Builder = builder.Builder;

test {
    std.testing.refAllDecls(@This());
}

test "TUI Integration full dashboard render" {
    var b = Builder.init(std.testing.allocator);
    defer b.deinit();

    _ = try b.title("MNEMEZIGOT FULLSTACK CONTROL CENTER");
    _ = try b.badge(.success, "SERVER ACTIVE");
    _ = try b.newline();

    _ = try b.keyVal("Framework", "Mnemezigot (Zig 0.16.0)");
    _ = try b.keyVal("Database", "SQLite 3.46 WAL Mode");
    _ = try b.keyVal("Memory Target", "< 15 MB");

    _ = try b.box(.{
        .title = "Cluster Health",
        .border = .rounded,
        .border_color = .cyan,
    }, "Node 1: Online (1.2 ms)\nNode 2: Online (1.4 ms)\nNode 3: Online (1.1 ms)");

    var tbl = Table.init(std.testing.allocator);
    defer tbl.deinit();
    try tbl.setHeaders(&.{ "Service", "Port", "Protocol", "Status" });
    try tbl.addRow(&.{ "Web UI", "8080", "HTTP / WASM", "OK" });
    try tbl.addRow(&.{ "REST API", "8080", "JSON", "OK" });
    try tbl.addRow(&.{ "gRPC-Web", "8080", "Protobuf", "OK" });

    var tbl_buf: std.ArrayList(u8) = .empty;
    defer tbl_buf.deinit(std.testing.allocator);
    const tbl_writer = bufferWriter(std.testing.allocator, &tbl_buf);
    try tbl.render(tbl_writer);

    _ = try b.text(tbl_buf.items);

    const rendered = b.string();
    try std.testing.expect(std.mem.indexOf(u8, rendered, "MNEMEZIGOT FULLSTACK CONTROL CENTER") != null);
    try std.testing.expect(std.mem.indexOf(u8, rendered, "SERVER ACTIVE") != null);
    try std.testing.expect(std.mem.indexOf(u8, rendered, "SQLite 3.46 WAL Mode") != null);
    try std.testing.expect(std.mem.indexOf(u8, rendered, "Cluster Health") != null);
    try std.testing.expect(std.mem.indexOf(u8, rendered, "gRPC-Web") != null);
}
