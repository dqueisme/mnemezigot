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
    /// KanTUI-inspired Tokyo Night palette
    pub const TokyoNight = struct {
        pub const name = "Tokyo Night";
        pub const bg = "\x1b[48;2;26;27;38m"; // #1a1b26
        pub const fg = "\x1b[38;2;192;202;245m"; // #c0caf5
        pub const fg_bold = "\x1b[1;38;2;192;202;245m";
        pub const fg_muted = "\x1b[38;2;86;95;137m"; // #565f89
        pub const fg_subtle = "\x1b[38;2;65;72;104m"; // #414868
        pub const border = "\x1b[38;2;65;72;104m"; // #414868
        pub const border_focus = "\x1b[38;2;122;162;247m"; // #7aa2f7
        pub const accent = "\x1b[38;2;187;154;247m"; // #bb9af7
        pub const accent_bold = "\x1b[1;38;2;187;154;247m";
        pub const accent_bg = "\x1b[48;2;187;154;247m\x1b[1;38;2;26;27;38m";
        pub const selection_bg = "\x1b[48;2;40;52;87m"; // #283457
        pub const selection_fg = "\x1b[1;38;2;255;255;255m";
        pub const crit = "\x1b[1;38;2;247;118;142m"; // #f7768e
        pub const warn = "\x1b[1;38;2;224;175;104m"; // #e0af68
        pub const low = "\x1b[38;2;115;218;202m"; // #73daca
        pub const success = "\x1b[38;2;158;206;106m"; // #9ece6a
        pub const info = "\x1b[38;2;125;207;255m"; // #7dcfff
        pub const col_backlog = "\x1b[38;2;122;162;247m"; // #7aa2f7
        pub const col_sprint = "\x1b[38;2;125;207;255m"; // #7dcfff
        pub const col_progress = "\x1b[38;2;255;158;100m"; // #ff9e64
        pub const col_review = "\x1b[38;2;187;154;247m"; // #bb9af7
        pub const col_done = "\x1b[38;2;158;206;106m"; // #9ece6a
        pub const reset = "\x1b[0m";
    };

    pub const CatppuccinMocha = struct {
        pub const name = "Catppuccin Mocha";
        pub const bg = "\x1b[48;2;30;30;46m"; // #1e1e2e
        pub const fg = "\x1b[38;2;205;214;244m"; // #cdd6f4
        pub const fg_bold = "\x1b[1;38;2;205;214;244m";
        pub const fg_muted = "\x1b[38;2;108;112;134m"; // #6c7086
        pub const fg_subtle = "\x1b[38;2;69;71;90m"; // #45475a
        pub const border = "\x1b[38;2;88;91;112m"; // #585b70
        pub const border_focus = "\x1b[38;2;137;180;250m"; // #89b4fa
        pub const accent = "\x1b[38;2;203;166;247m"; // #cba6f7
        pub const accent_bold = "\x1b[1;38;2;203;166;247m";
        pub const accent_bg = "\x1b[48;2;203;166;247m\x1b[1;38;2;30;30;46m";
        pub const selection_bg = "\x1b[48;2;49;50;68m"; // #313244
        pub const selection_fg = "\x1b[1;38;2;255;255;255m";
        pub const crit = "\x1b[1;38;2;243;139;168m"; // #f38ba8
        pub const warn = "\x1b[1;38;2;249;226;175m"; // #f9e2af
        pub const low = "\x1b[38;2;148;226;213m"; // #94e2d5
        pub const success = "\x1b[38;2;166;227;161m"; // #a6e3a1
        pub const info = "\x1b[38;2;137;220;235m"; // #89dceb
        pub const col_backlog = "\x1b[38;2;137;180;250m"; // #89b4fa
        pub const col_sprint = "\x1b[38;2;137;220;235m"; // #89dceb
        pub const col_progress = "\x1b[38;2;250;179;135m"; // #fab387
        pub const col_review = "\x1b[38;2;203;166;247m"; // #cba6f7
        pub const col_done = "\x1b[38;2;166;227;161m"; // #a6e3a1
        pub const reset = "\x1b[0m";
    };

    /// Herdr-inspired One Dark palette (https://github.com/herdrdev/herdr)
    pub const OneDark = struct {
        pub const name = "One Dark";
        pub const bg = "\x1b[48;2;40;44;52m"; // #282c34
        pub const fg = "\x1b[38;2;171;178;191m"; // #abb2bf (Herdr soft white text)
        pub const fg_bold = "\x1b[1;38;2;255;255;255m";
        pub const fg_muted = "\x1b[38;2;92;99;112m"; // #5c6370 (Dim text)
        pub const fg_subtle = "\x1b[38;2;62;68;81m"; // #3e4451
        pub const border = "\x1b[38;2;62;68;81m"; // #3e4451
        pub const border_focus = "\x1b[38;2;97;175;239m"; // #61afef (Herdr active border)
        pub const accent = "\x1b[38;2;198;120;221m"; // #c678dd (One Dark Purple)
        pub const accent_bold = "\x1b[1;38;2;198;120;221m";
        pub const accent_bg = "\x1b[48;2;198;120;221m\x1b[1;38;2;40;44;52m";
        pub const selection_bg = "\x1b[48;2;51;70;89m"; // #334659 (Herdr selection row)
        pub const selection_fg = "\x1b[1;38;2;255;255;255m";
        pub const crit = "\x1b[1;38;2;224;108;117m"; // #e06c75 (Critical / Error)
        pub const warn = "\x1b[1;38;2;229;192;123m"; // #e5c07b (In Progress / Important)
        pub const low = "\x1b[38;2;86;182;194m"; // #56b6c2
        pub const success = "\x1b[38;2;152;195;121m"; // #98c379 (Done / Success)
        pub const info = "\x1b[38;2;97;175;239m"; // #61afef
        pub const col_backlog = "\x1b[38;2;97;175;239m";
        pub const col_sprint = "\x1b[38;2;86;182;194m";
        pub const col_progress = "\x1b[38;2;229;192;123m";
        pub const col_review = "\x1b[38;2;198;120;221m";
        pub const col_done = "\x1b[38;2;152;195;121m";
        pub const reset = "\x1b[0m";

        // Aliases for compatibility
        pub const panel_bg = bg;
        pub const active_tab_bg = "\x1b[48;2;49;54;64m";
        pub const border_dim = border;
        pub const text = fg;
        pub const text_bright = fg_bold;
        pub const text_muted = fg_muted;
        pub const green = success;
        pub const yellow = warn;
        pub const red = crit;
        pub const cyan = low;
        pub const mauve = accent;
    };
};

pub const ThemeDef = struct {
    name: []const u8,
    bg: []const u8,
    fg: []const u8,
    fg_bold: []const u8,
    fg_muted: []const u8,
    fg_subtle: []const u8,
    border: []const u8,
    border_focus: []const u8,
    accent: []const u8,
    accent_bold: []const u8,
    accent_bg: []const u8,
    selection_bg: []const u8,
    selection_fg: []const u8,
    crit: []const u8,
    warn: []const u8,
    low: []const u8,
    success: []const u8,
    info: []const u8,
    col_backlog: []const u8,
    col_sprint: []const u8,
    col_progress: []const u8,
    col_review: []const u8,
    col_done: []const u8,
    reset: []const u8,

    pub fn columnColor(self: ThemeDef, clean_name: []const u8) []const u8 {
        if (std.mem.indexOf(u8, clean_name, "Backlog") != null) return self.col_backlog;
        if (std.mem.indexOf(u8, clean_name, "Sprint") != null) return self.col_sprint;
        if (std.mem.indexOf(u8, clean_name, "Progress") != null) return self.col_progress;
        if (std.mem.indexOf(u8, clean_name, "Review") != null or std.mem.indexOf(u8, clean_name, "Staged") != null) return self.col_review;
        if (std.mem.indexOf(u8, clean_name, "Done") != null) return self.col_done;
        return self.border_focus;
    }
};

pub const THEME_TOKYO_NIGHT = ThemeDef{
    .name = Palette.TokyoNight.name,
    .bg = Palette.TokyoNight.bg,
    .fg = Palette.TokyoNight.fg,
    .fg_bold = Palette.TokyoNight.fg_bold,
    .fg_muted = Palette.TokyoNight.fg_muted,
    .fg_subtle = Palette.TokyoNight.fg_subtle,
    .border = Palette.TokyoNight.border,
    .border_focus = Palette.TokyoNight.border_focus,
    .accent = Palette.TokyoNight.accent,
    .accent_bold = Palette.TokyoNight.accent_bold,
    .accent_bg = Palette.TokyoNight.accent_bg,
    .selection_bg = Palette.TokyoNight.selection_bg,
    .selection_fg = Palette.TokyoNight.selection_fg,
    .crit = Palette.TokyoNight.crit,
    .warn = Palette.TokyoNight.warn,
    .low = Palette.TokyoNight.low,
    .success = Palette.TokyoNight.success,
    .info = Palette.TokyoNight.info,
    .col_backlog = Palette.TokyoNight.col_backlog,
    .col_sprint = Palette.TokyoNight.col_sprint,
    .col_progress = Palette.TokyoNight.col_progress,
    .col_review = Palette.TokyoNight.col_review,
    .col_done = Palette.TokyoNight.col_done,
    .reset = Palette.TokyoNight.reset,
};

pub const THEME_CATPPUCCIN = ThemeDef{
    .name = Palette.CatppuccinMocha.name,
    .bg = Palette.CatppuccinMocha.bg,
    .fg = Palette.CatppuccinMocha.fg,
    .fg_bold = Palette.CatppuccinMocha.fg_bold,
    .fg_muted = Palette.CatppuccinMocha.fg_muted,
    .fg_subtle = Palette.CatppuccinMocha.fg_subtle,
    .border = Palette.CatppuccinMocha.border,
    .border_focus = Palette.CatppuccinMocha.border_focus,
    .accent = Palette.CatppuccinMocha.accent,
    .accent_bold = Palette.CatppuccinMocha.accent_bold,
    .accent_bg = Palette.CatppuccinMocha.accent_bg,
    .selection_bg = Palette.CatppuccinMocha.selection_bg,
    .selection_fg = Palette.CatppuccinMocha.selection_fg,
    .crit = Palette.CatppuccinMocha.crit,
    .warn = Palette.CatppuccinMocha.warn,
    .low = Palette.CatppuccinMocha.low,
    .success = Palette.CatppuccinMocha.success,
    .info = Palette.CatppuccinMocha.info,
    .col_backlog = Palette.CatppuccinMocha.col_backlog,
    .col_sprint = Palette.CatppuccinMocha.col_sprint,
    .col_progress = Palette.CatppuccinMocha.col_progress,
    .col_review = Palette.CatppuccinMocha.col_review,
    .col_done = Palette.CatppuccinMocha.col_done,
    .reset = Palette.CatppuccinMocha.reset,
};

pub const THEME_ONE_DARK = ThemeDef{
    .name = Palette.OneDark.name,
    .bg = Palette.OneDark.bg,
    .fg = Palette.OneDark.fg,
    .fg_bold = Palette.OneDark.fg_bold,
    .fg_muted = Palette.OneDark.fg_muted,
    .fg_subtle = Palette.OneDark.fg_subtle,
    .border = Palette.OneDark.border,
    .border_focus = Palette.OneDark.border_focus,
    .accent = Palette.OneDark.accent,
    .accent_bold = Palette.OneDark.accent_bold,
    .accent_bg = Palette.OneDark.accent_bg,
    .selection_bg = Palette.OneDark.selection_bg,
    .selection_fg = Palette.OneDark.selection_fg,
    .crit = Palette.OneDark.crit,
    .warn = Palette.OneDark.warn,
    .low = Palette.OneDark.low,
    .success = Palette.OneDark.success,
    .info = Palette.OneDark.info,
    .col_backlog = Palette.OneDark.col_backlog,
    .col_sprint = Palette.OneDark.col_sprint,
    .col_progress = Palette.OneDark.col_progress,
    .col_review = Palette.OneDark.col_review,
    .col_done = Palette.OneDark.col_done,
    .reset = Palette.OneDark.reset,
};

pub const OneDark = Palette.OneDark;
pub const TokyoNight = Palette.TokyoNight;
pub const CatppuccinMocha = Palette.CatppuccinMocha;
pub const Theme = Palette;

test "Palette TokyoNight and OneDark ANSI values" {
    try std.testing.expect(Palette.TokyoNight.accent.len > 0);
    try std.testing.expect(Palette.OneDark.accent.len > 0);
    try std.testing.expectEqualStrings("\x1b[0m", Palette.OneDark.reset);
}

