const std = @import("std");

const builtin = @import("builtin");

pub const WindowSize = struct {
    cols: u16 = 80,
    rows: u16 = 24,
};

/// Get terminal window dimensions using ioctl (TIOCGWINSZ) on stdout fd
pub fn getWindowSize() WindowSize {
    const TIOCGWINSZ: u32 = 0x5413; // Standard Linux / POSIX TIOCGWINSZ
    const winsize = extern struct {
        ws_row: u16,
        ws_col: u16,
        ws_xpixel: u16,
        ws_ypixel: u16,
    };

    var ws: winsize = undefined;
    if (builtin.os.tag == .linux) {
        const rc = std.posix.system.ioctl(std.posix.STDOUT_FILENO, TIOCGWINSZ, @intFromPtr(&ws));
        if (rc == 0 and ws.ws_col > 0 and ws.ws_row > 0) {
            return .{
                .cols = ws.ws_col,
                .rows = ws.ws_row,
            };
        }
    }
    return .{ .cols = 80, .rows = 24 };
}

/// Cursor navigation and control
pub const Cursor = struct {
    pub fn moveTo(writer: anytype, col: u16, row: u16) !void {
        try writer.print("\x1b[{d};{d}H", .{ row, col });
    }

    pub fn up(writer: anytype, n: u16) !void {
        try writer.print("\x1b[{d}A", .{n});
    }

    pub fn down(writer: anytype, n: u16) !void {
        try writer.print("\x1b[{d}B", .{n});
    }

    pub fn right(writer: anytype, n: u16) !void {
        try writer.print("\x1b[{d}C", .{n});
    }

    pub fn left(writer: anytype, n: u16) !void {
        try writer.print("\x1b[{d}D", .{n});
    }

    pub fn hide(writer: anytype) !void {
        try writer.writeAll("\x1b[?25l");
    }

    pub fn show(writer: anytype) !void {
        try writer.writeAll("\x1b[?25h");
    }

    pub fn save(writer: anytype) !void {
        try writer.writeAll("\x1b[s");
    }

    pub fn restore(writer: anytype) !void {
        try writer.writeAll("\x1b[u");
    }
};

/// Screen clear and buffer controls
pub const Screen = struct {
    pub fn clear(writer: anytype) !void {
        try writer.writeAll("\x1b[2J\x1b[H");
    }

    pub fn clearLine(writer: anytype) !void {
        try writer.writeAll("\x1b[2K\r");
    }

    pub fn clearToEndOfLine(writer: anytype) !void {
        try writer.writeAll("\x1b[K");
    }

    pub fn enterAltScreen(writer: anytype) !void {
        try writer.writeAll("\x1b[?1049h");
    }

    pub fn exitAltScreen(writer: anytype) !void {
        try writer.writeAll("\x1b[?1049l");
    }
};

test "Terminal cursor and screen escapes" {
    const style = @import("style.zig");
    var buf: std.ArrayList(u8) = .empty;
    defer buf.deinit(std.testing.allocator);
    const w = style.bufferWriter(std.testing.allocator, &buf);

    try Cursor.moveTo(w, 10, 5);
    try Cursor.hide(w);
    try Screen.clear(w);
    try Cursor.show(w);

    const out = buf.items;
    try std.testing.expect(std.mem.indexOf(u8, out, "\x1b[5;10H") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "\x1b[?25l") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "\x1b[2J\x1b[H") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "\x1b[?25h") != null);
}
