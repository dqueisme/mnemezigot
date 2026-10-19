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
    var default_cols: u16 = 80;
    var default_rows: u16 = 24;
    if (builtin.link_libc) {
        if (std.c.getenv("COLUMNS")) |col_ptr| {
            const col_slice = std.mem.span(col_ptr);
            if (std.fmt.parseInt(u16, col_slice, 10)) |c| {
                if (c > 0) default_cols = c;
            } else |_| {}
        }
        if (std.c.getenv("LINES")) |row_ptr| {
            const row_slice = std.mem.span(row_ptr);
            if (std.fmt.parseInt(u16, row_slice, 10)) |r| {
                if (r > 0) default_rows = r;
            } else |_| {}
        }
    }
    return .{ .cols = default_cols, .rows = default_rows };
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

    pub fn disableLineWrap(writer: anytype) !void {
        try writer.writeAll("\x1b[?7l");
    }

    pub fn enableLineWrap(writer: anytype) !void {
        try writer.writeAll("\x1b[?7h");
    }

    pub fn beginSync(writer: anytype) !void {
        try writer.writeAll("\x1b[?2025h");
    }

    pub fn endSync(writer: anytype) !void {
        try writer.writeAll("\x1b[?2025l");
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

            raw.cc[@intFromEnum(std.posix.V.MIN)] = 1;
            raw.cc[@intFromEnum(std.posix.V.TIME)] = 0;

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

/// Standard input reader for terminal interactive sessions
pub const StdinReader = struct {
    pub fn readByte(self: @This()) !u8 {
        _ = self;
        var buf: [1]u8 = undefined;
        const n = try std.posix.read(std.posix.STDIN_FILENO, &buf);
        if (n == 0) return error.EndOfStream;
        return buf[0];
    }

    pub fn readByteTimeout(self: @This(), timeout_ms: i32) !?u8 {
        _ = self;
        var pfd = [1]std.posix.pollfd{.{
            .fd = std.posix.STDIN_FILENO,
            .events = std.posix.POLL.IN,
            .revents = 0,
        }};
        const ready = try std.posix.poll(&pfd, timeout_ms);
        if (ready == 0) return null;
        var buf: [1]u8 = undefined;
        const n = try std.posix.read(std.posix.STDIN_FILENO, &buf);
        if (n == 0) return null;
        return buf[0];
    }
};

pub fn stdinReader() StdinReader {
    return .{};
}

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
    timeout,
};

pub fn parseKeyFromFirstByte(reader: anytype, b1: u8) !Key {
    if (b1 == 0x1b) {
        const T = @TypeOf(reader);
        const ActualT = switch (@typeInfo(T)) {
            .pointer => |ptr| ptr.child,
            else => T,
        };
        const b2: u8 = if (@typeInfo(ActualT) == .@"struct" and @hasDecl(ActualT, "readByteTimeout"))
            (try reader.readByteTimeout(25)) orelse return .escape
        else
            reader.readByte() catch |err| {
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

/// Parse a key press event from an input byte stream
pub fn readKey(reader: anytype) !Key {
    const b1 = reader.readByte() catch |err| {
        if (err == error.EndOfStream) return .none;
        return err;
    };
    return parseKeyFromFirstByte(reader, b1);
}

/// Read a key press event with a millisecond timeout. Returns .timeout if no key pressed.
pub fn readKeyTimeout(reader: anytype, timeout_ms: i32) !Key {
    const T = @TypeOf(reader);
    const ActualT = switch (@typeInfo(T)) {
        .pointer => |ptr| ptr.child,
        else => T,
    };
    if (!(@typeInfo(ActualT) == .@"struct" and @hasDecl(ActualT, "readByteTimeout"))) {
        return readKey(reader);
    }
    const b1_opt = reader.readByteTimeout(timeout_ms) catch |err| {
        if (err == error.EndOfStream) return .none;
        return err;
    };
    const b1 = b1_opt orelse return .timeout;
    return parseKeyFromFirstByte(reader, b1);
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

/// Read current resident set size (RSS) of the running process (/proc/self/statm on Linux).
/// Returns human-readable string such as "14.2 MB", "850 KB", or "N/A".
pub fn getProcessMemory(arena: std.mem.Allocator) []const u8 {
    if (builtin.os.tag != .linux) return "N/A";
    const fd_res = std.os.linux.open("/proc/self/statm", std.os.linux.O{}, 0);
    const fd = std.posix.errno(fd_res);
    if (fd != .SUCCESS) return "N/A";
    const raw_fd: std.os.linux.fd_t = @intCast(fd_res);
    defer _ = std.os.linux.close(raw_fd);

    var buf: [128]u8 = undefined;
    const read_res = std.os.linux.read(raw_fd, &buf, buf.len);
    const r_err = std.posix.errno(read_res);
    if (r_err != .SUCCESS) return "N/A";
    const bytes_read: usize = @intCast(read_res);
    const content = buf[0..bytes_read];

    var it = std.mem.splitScalar(u8, content, ' ');
    _ = it.next(); // skip total size
    const rss_str = it.next() orelse return "N/A";
    const pages = std.fmt.parseInt(u64, rss_str, 10) catch return "N/A";
    const rss_bytes = pages * 4096;

    if (rss_bytes >= 1024 * 1024 * 1024) {
        const gb = @as(f64, @floatFromInt(rss_bytes)) / (1024.0 * 1024.0 * 1024.0);
        return std.fmt.allocPrint(arena, "{d:.2} GB", .{gb}) catch "N/A";
    } else if (rss_bytes >= 1024 * 1024) {
        const mb = @as(f64, @floatFromInt(rss_bytes)) / (1024.0 * 1024.0);
        return std.fmt.allocPrint(arena, "{d:.1} MB", .{mb}) catch "N/A";
    } else if (rss_bytes >= 1024) {
        const kb = @as(f64, @floatFromInt(rss_bytes)) / 1024.0;
        return std.fmt.allocPrint(arena, "{d:.0} KB", .{kb}) catch "N/A";
    } else {
        return std.fmt.allocPrint(arena, "{d} B", .{rss_bytes}) catch "N/A";
    }
}

pub const getProcessRealMemory = getProcessMemory;

/// Check if a local TCP port is actively listening (/proc/net/tcp on Linux)
pub fn isPortListening(port: u16) bool {
    if (builtin.os.tag != .linux) return false;
    var hex_port_buf: [8]u8 = undefined;
    const hex_port = std.fmt.bufPrint(&hex_port_buf, ":{X:0>4}", .{port}) catch return false;

    const fd_res = std.os.linux.open("/proc/net/tcp", std.os.linux.O{}, 0);
    const fd = std.posix.errno(fd_res);
    if (fd != .SUCCESS) return false;
    const raw_fd: std.os.linux.fd_t = @intCast(fd_res);
    defer _ = std.os.linux.close(raw_fd);

    var buf: [8192]u8 = undefined;
    const read_res = std.os.linux.read(raw_fd, &buf, buf.len);
    const r_err = std.posix.errno(read_res);
    if (r_err != .SUCCESS) return false;
    const bytes_read: usize = @intCast(read_res);
    const content = buf[0..bytes_read];

    var it = std.mem.splitScalar(u8, content, '\n');
    while (it.next()) |line| {
        if (std.mem.indexOf(u8, line, hex_port) != null) {
            if (std.mem.indexOf(u8, line, " 0A ") != null) {
                return true;
            }
        }
    }
    return false;
}

test "getProcessMemory returns valid string on Linux" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const mem = getProcessMemory(arena.allocator());
    try std.testing.expect(mem.len > 0);
}

test "isPortListening checks port correctly" {
    _ = isPortListening(8080);
    try std.testing.expect(!isPortListening(59999));
}
