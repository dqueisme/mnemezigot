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

/// Terminal Raw Mode manager using POSIX termios
pub const RawMode = struct {
    orig_termios: ?std.posix.termios = null,
    active: bool = false,

    pub fn enable() RawMode {
        if (builtin.os.tag == .linux or builtin.os.tag == .macos) {
            const orig = std.posix.tcgetattr(std.posix.STDIN_FILENO) catch return .{ .active = false };
            var raw = orig;

            raw.iflag.BRKINT = false;
            raw.iflag.ICRNL = false;
            raw.iflag.INPCK = false;
            raw.iflag.ISTRIP = false;
            raw.iflag.IXON = false;

            raw.oflag.OPOST = false;
            raw.cflag.CSIZE = .CS8;

            raw.lflag.ECHO = false;
            raw.lflag.ICANON = false;
            raw.lflag.IEXTEN = false;
            raw.lflag.ISIG = false;

            raw.cc[std.posix.V.MIN] = 1;
            raw.cc[std.posix.V.TIME] = 0;

            std.posix.tcsetattr(std.posix.STDIN_FILENO, .NOW, raw) catch return .{ .active = false };
            return .{ .orig_termios = orig, .active = true };
        }
        return .{ .active = false };
    }

    pub fn disable(self: *RawMode) void {
        if (self.active and self.orig_termios != null) {
            _ = std.posix.tcsetattr(std.posix.STDIN_FILENO, .NOW, self.orig_termios.?) catch {};
            self.active = false;
        }
    }
};

/// Keyboard Event / Key Code
pub const Key = union(enum) {
    up,
    down,
    left,
    right,
    enter,
    escape,
    backspace,
    tab,
    page_up,
    page_down,
    home,
    end,
    char: u8,
    ctrl: u8,
    none,
};

/// Parse a key press event from an input byte stream
pub fn readKey(reader: anytype) !Key {
    const b1 = reader.readByte() catch |err| {
        if (err == error.EndOfStream) return .none;
        return err;
    };

    if (b1 == 0x1b) {
        const b2 = reader.readByte() catch |err| {
            if (err == error.EndOfStream) return .escape;
            return err;
        };

        if (b2 == '[') {
            const b3 = reader.readByte() catch |err| {
                if (err == error.EndOfStream) return .escape;
                return err;
            };

            switch (b3) {
                'A' => return .up,
                'B' => return .down,
                'C' => return .right,
                'D' => return .left,
                'H' => return .home,
                'F' => return .end,
                '1'...'9' => {
                    const b4 = reader.readByte() catch |err| {
                        if (err == error.EndOfStream) return .escape;
                        return err;
                    };
                    if (b4 == '~') {
                        switch (b3) {
                            '1', '7' => return .home,
                            '4', '8' => return .end,
                            '5' => return .page_up,
                            '6' => return .page_down,
                            '3' => return .backspace,
                            else => return .escape,
                        }
                    }
                    return .escape;
                },
                else => return .escape,
            }
        } else if (b2 == 'O') {
            const b3 = reader.readByte() catch |err| {
                if (err == error.EndOfStream) return .escape;
                return err;
            };
            switch (b3) {
                'A' => return .up,
                'B' => return .down,
                'C' => return .right,
                'D' => return .left,
                'H' => return .home,
                'F' => return .end,
                else => return .escape,
            }
        }
        return .escape;
    }

    if (b1 == '\r' or b1 == '\n') return .enter;
    if (b1 == '\t') return .tab;
    if (b1 == 0x7f or b1 == 0x08) return .backspace;
    if (b1 >= 1 and b1 <= 26) {
        return .{ .ctrl = b1 + 96 };
    }

    return .{ .char = b1 };
}

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

test "Key reader parsing" {
    const MockReader = struct {
        slice: []const u8,
        pos: usize = 0,

        pub fn readByte(self: *@This()) !u8 {
            if (self.pos >= self.slice.len) return error.EndOfStream;
            const b = self.slice[self.pos];
            self.pos += 1;
            return b;
        }
    };

    var r1 = MockReader{ .slice = "\x1b[A\x1b[B\x1b[C\x1b[D\r\tq\x03" };
    try std.testing.expectEqual(Key.up, try readKey(&r1));
    try std.testing.expectEqual(Key.down, try readKey(&r1));
    try std.testing.expectEqual(Key.right, try readKey(&r1));
    try std.testing.expectEqual(Key.left, try readKey(&r1));
    try std.testing.expectEqual(Key.enter, try readKey(&r1));
    try std.testing.expectEqual(Key.tab, try readKey(&r1));
    try std.testing.expectEqual(Key{ .char = 'q' }, try readKey(&r1));
    try std.testing.expectEqual(Key{ .ctrl = 'c' }, try readKey(&r1));
}
