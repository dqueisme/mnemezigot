const std = @import("std");

const builtin = @import("builtin");

/// ANSI Terminal Color definitions
pub const Color = union(enum) {
    none,
    black,
    red,
    green,
    yellow,
    blue,
    magenta,
    cyan,
    white,
    bright_black,
    bright_red,
    bright_green,
    bright_yellow,
    bright_blue,
    bright_magenta,
    bright_cyan,
    bright_white,
    rgb: struct { r: u8, g: u8, b: u8 },
    index: u8,

    pub fn writeAnsi(self: Color, writer: anytype, is_bg: bool) !void {
        const bg_offset: u8 = if (is_bg) 10 else 0;
        switch (self) {
            .none => {},
            .black => try writer.print("\x1b[{d}m", .{30 + bg_offset}),
            .red => try writer.print("\x1b[{d}m", .{31 + bg_offset}),
            .green => try writer.print("\x1b[{d}m", .{32 + bg_offset}),
            .yellow => try writer.print("\x1b[{d}m", .{33 + bg_offset}),
            .blue => try writer.print("\x1b[{d}m", .{34 + bg_offset}),
            .magenta => try writer.print("\x1b[{d}m", .{35 + bg_offset}),
            .cyan => try writer.print("\x1b[{d}m", .{36 + bg_offset}),
            .white => try writer.print("\x1b[{d}m", .{37 + bg_offset}),
            .bright_black => try writer.print("\x1b[{d}m", .{90 + bg_offset}),
            .bright_red => try writer.print("\x1b[{d}m", .{91 + bg_offset}),
            .bright_green => try writer.print("\x1b[{d}m", .{92 + bg_offset}),
            .bright_yellow => try writer.print("\x1b[{d}m", .{93 + bg_offset}),
            .bright_blue => try writer.print("\x1b[{d}m", .{94 + bg_offset}),
            .bright_magenta => try writer.print("\x1b[{d}m", .{95 + bg_offset}),
            .bright_cyan => try writer.print("\x1b[{d}m", .{96 + bg_offset}),
            .bright_white => try writer.print("\x1b[{d}m", .{97 + bg_offset}),
            .rgb => |rgb| {
                const code: u8 = if (is_bg) 48 else 38;
                try writer.print("\x1b[{d};2;{d};{d};{d}m", .{ code, rgb.r, rgb.g, rgb.b });
            },
            .index => |idx| {
                const code: u8 = if (is_bg) 48 else 38;
                try writer.print("\x1b[{d};5;{d}m", .{ code, idx });
            },
        }
    }
};

/// ANSI Text Attributes / Formatting Styles
pub const Style = struct {
    bold: bool = false,
    dim: bool = false,
    italic: bool = false,
    underline: bool = false,
    blink: bool = false,
    inverse: bool = false,
    hidden: bool = false,
    strikethrough: bool = false,

    pub const none: Style = .{};
    pub const bold_only: Style = .{ .bold = true };
    pub const dim_only: Style = .{ .dim = true };

    pub fn writeAnsi(self: Style, writer: anytype) !void {
        if (self.bold) try writer.writeAll("\x1b[1m");
        if (self.dim) try writer.writeAll("\x1b[2m");
        if (self.italic) try writer.writeAll("\x1b[3m");
        if (self.underline) try writer.writeAll("\x1b[4m");
        if (self.blink) try writer.writeAll("\x1b[5m");
        if (self.inverse) try writer.writeAll("\x1b[7m");
        if (self.hidden) try writer.writeAll("\x1b[8m");
        if (self.strikethrough) try writer.writeAll("\x1b[9m");
    }
};

/// Write ANSI reset sequence
pub fn resetAnsi(writer: anytype) !void {
    try writer.writeAll("\x1b[0m");
}

/// Apply full styling (fg, bg, style) before writing text, then reset
pub fn writeStyled(writer: anytype, text: []const u8, fg: Color, bg: Color, style: Style) !void {
    try style.writeAnsi(writer);
    try fg.writeAnsi(writer, false);
    try bg.writeAnsi(writer, true);
    try writer.writeAll(text);
    try resetAnsi(writer);
}

pub const StdoutWriter = struct {
    pub fn writeAll(self: StdoutWriter, bytes: []const u8) !void {
        _ = self;
        var written: usize = 0;
        while (written < bytes.len) {
            const count: isize = if (builtin.link_libc)
                std.c.write(1, bytes[written..].ptr, bytes[written..].len)
            else if (builtin.os.tag == .linux)
                @intCast(std.posix.system.write(1, bytes[written..].ptr, bytes[written..].len))
            else
                break;

            if (count <= 0) break;
            written += @intCast(count);
        }
    }

    pub fn print(self: StdoutWriter, comptime fmt: []const u8, args: anytype) !void {
        var buf: [16384]u8 = undefined;
        const msg = std.fmt.bufPrint(&buf, fmt, args) catch return;
        try self.writeAll(msg);
    }
};

pub fn stdoutWriter() StdoutWriter {
    return .{};
}

pub const BufferWriter = struct {
    list: *std.ArrayList(u8),
    allocator: std.mem.Allocator,

    pub fn writeAll(self: BufferWriter, bytes: []const u8) !void {
        try self.list.appendSlice(self.allocator, bytes);
    }

    pub fn print(self: BufferWriter, comptime fmt: []const u8, args: anytype) !void {
        try self.list.print(self.allocator, fmt, args);
    }
};

pub fn bufferWriter(allocator: std.mem.Allocator, list: *std.ArrayList(u8)) BufferWriter {
    return .{ .list = list, .allocator = allocator };
}

test "Color and Style ANSI formatting" {
    var buf: std.ArrayList(u8) = .empty;
    defer buf.deinit(std.testing.allocator);

    const w = bufferWriter(std.testing.allocator, &buf);
    try writeStyled(w, "Hello TUI", .cyan, .none, .{ .bold = true });

    const str = buf.items;
    try std.testing.expect(std.mem.startsWith(u8, str, "\x1b[1m\x1b[36mHello TUI\x1b[0m"));
}

/// Predefined ANSI color palettes and themes for TUI applications
pub const Palette = struct {
    /// Herdr-inspired One Dark palette (https://github.com/herdrdev/herdr)
    pub const OneDark = struct {
        pub const accent = "\x1b[38;2;97;175;239m"; // #61afef (One Dark Blue)
        pub const accent_bold = "\x1b[1;38;2;97;175;239m";
        pub const panel_bg = "\x1b[48;2;40;44;52m"; // #282c34
        pub const selection_bg = "\x1b[48;2;51;70;89m"; // #334659 (Herdr selection row)
        pub const active_tab_bg = "\x1b[48;2;49;54;64m"; // #313640
        pub const border_dim = "\x1b[38;2;92;99;112m"; // #5c6370 (Herdr overlay0)
        pub const border_focus = "\x1b[38;2;97;175;239m"; // #61afef (Herdr active border)
        pub const text = "\x1b[38;2;171;178;191m"; // #abb2bf (Herdr soft white text)
        pub const text_bright = "\x1b[1;38;2;255;255;255m"; // #ffffff (Bold White)
        pub const text_muted = "\x1b[38;2;92;99;112m"; // #5c6370 (Dim text)
        pub const green = "\x1b[38;2;152;195;121m"; // #98c379 (Done / Success)
        pub const yellow = "\x1b[38;2;229;192;123m"; // #e5c07b (In Progress / Important)
        pub const red = "\x1b[38;2;224;108;117m"; // #e06c75 (Critical / Error)
        pub const cyan = "\x1b[38;2;86;182;194m"; // #56b6c2 (Info / In Review)
        pub const mauve = "\x1b[38;2;198;120;221m"; // #c678dd (Metadata / Wikilinks)
        pub const reset = "\x1b[0m";
    };
};

pub const Theme = Palette;

test "Palette OneDark ANSI values" {
    try std.testing.expect(Palette.OneDark.accent.len > 0);
    try std.testing.expectEqualStrings("\x1b[0m", Palette.OneDark.reset);
}
