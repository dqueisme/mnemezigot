const std = @import("std");
const style_mod = @import("style.zig");
const Color = style_mod.Color;
const Style = style_mod.Style;

pub const BorderStyle = enum {
    none,
    ascii,
    single,
    rounded,
    double,
    thick,

    pub const BorderGlyphs = struct {
        top_left: []const u8,
        top_right: []const u8,
        bottom_left: []const u8,
        bottom_right: []const u8,
        horizontal: []const u8,
        vertical: []const u8,
    };

    pub fn glyphs(self: BorderStyle) BorderGlyphs {
        return switch (self) {
            .none => .{
                .top_left = " ",
                .top_right = " ",
                .bottom_left = " ",
                .bottom_right = " ",
                .horizontal = " ",
                .vertical = " ",
            },
            .ascii => .{
                .top_left = "+",
                .top_right = "+",
                .bottom_left = "+",
                .bottom_right = "+",
                .horizontal = "-",
                .vertical = "|",
            },
            .single => .{
                .top_left = "┌",
                .top_right = "┐",
                .bottom_left = "└",
                .bottom_right = "┘",
                .horizontal = "─",
                .vertical = "│",
            },
            .rounded => .{
                .top_left = "╭",
                .top_right = "╮",
                .bottom_left = "╰",
                .bottom_right = "╯",
                .horizontal = "─",
                .vertical = "│",
            },
            .double => .{
                .top_left = "╔",
                .top_right = "╗",
                .bottom_left = "╚",
                .bottom_right = "╝",
                .horizontal = "═",
                .vertical = "║",
            },
            .thick => .{
                .top_left = "┏",
                .top_right = "┓",
                .bottom_left = "┗",
                .bottom_right = "┛",
                .horizontal = "━",
                .vertical = "┃",
            },
        };
    }
};

pub const TitleAlign = enum {
    left,
    center,
    right,
};

pub const BoxConfig = struct {
    title: ?[]const u8 = null,
    title_align: TitleAlign = .left,
    border: BorderStyle = .rounded,
    border_color: Color = .cyan,
    title_color: Color = .bright_white,
    content_color: Color = .none,
    width: ?usize = null,
    padding_x: usize = 1,
};

/// Calculate visible display column width of UTF-8 string (treating ascii as 1 col)
pub fn stringWidth(s: []const u8) usize {
    var width: usize = 0;
    var i: usize = 0;
    while (i < s.len) {
        // Skip ANSI escape sequences when counting width
        if (s[i] == 0x1b and i + 1 < s.len and s[i + 1] == '[') {
            i += 2;
            while (i < s.len and s[i] != 'm') : (i += 1) {}
            if (i < s.len and s[i] == 'm') i += 1;
            continue;
        }

        const len = std.unicode.utf8ByteSequenceLength(s[i]) catch 1;
        width += 1;
        i += len;
    }
    return width;
}

/// Render a styled box container with multi-line content
pub fn render(writer: anytype, config: BoxConfig, content: []const u8) !void {
    const border_chars = config.border.glyphs();

    // 1. Calculate max content line width
    var max_line_width: usize = if (config.title) |t| stringWidth(t) + 4 else 0;
    var line_iter = std.mem.splitScalar(u8, content, '\n');
    while (line_iter.next()) |line| {
        const w = stringWidth(line);
        if (w > max_line_width) max_line_width = w;
    }

    const inner_width: usize = if (config.width) |req_w|
        if (req_w >= 2 + config.padding_x * 2) req_w - 2 - config.padding_x * 2 else max_line_width
    else
        max_line_width;

    const total_inner_width = inner_width + config.padding_x * 2;

    // 2. Render Top Border (with optional title embedded)
    try config.border_color.writeAnsi(writer, false);
    try writer.writeAll(border_chars.top_left);

    if (config.title) |title| {
        const t_len = stringWidth(title);
        const avail = if (total_inner_width > t_len + 2) total_inner_width - (t_len + 2) else 0;

        const left_fill = switch (config.title_align) {
            .left => @min(avail, @as(usize, 1)),
            .center => avail / 2,
            .right => avail - @min(avail, @as(usize, 1)),
        };
        const right_fill = avail - left_fill;

        for (0..left_fill) |_| try writer.writeAll(border_chars.horizontal);
        try style_mod.resetAnsi(writer);

        try writer.writeAll(" ");
        try style_mod.writeStyled(writer, title, config.title_color, .none, .{ .bold = true });
        try writer.writeAll(" ");

        try config.border_color.writeAnsi(writer, false);
        for (0..right_fill) |_| try writer.writeAll(border_chars.horizontal);
    } else {
        for (0..total_inner_width) |_| try writer.writeAll(border_chars.horizontal);
    }

    try writer.writeAll(border_chars.top_right);
    try style_mod.resetAnsi(writer);
    try writer.writeAll("\n");

    // 3. Render Content Lines
    var content_iter = std.mem.splitScalar(u8, content, '\n');
    while (content_iter.next()) |line| {
        try config.border_color.writeAnsi(writer, false);
        try writer.writeAll(border_chars.vertical);
        try style_mod.resetAnsi(writer);

        for (0..config.padding_x) |_| try writer.writeAll(" ");

        try config.content_color.writeAnsi(writer, false);
        try writer.writeAll(line);
        try style_mod.resetAnsi(writer);

        const current_w = stringWidth(line);
        const pad_spaces = if (inner_width > current_w) inner_width - current_w else 0;
        for (0..pad_spaces) |_| try writer.writeAll(" ");

        for (0..config.padding_x) |_| try writer.writeAll(" ");

        try config.border_color.writeAnsi(writer, false);
        try writer.writeAll(border_chars.vertical);
        try style_mod.resetAnsi(writer);
        try writer.writeAll("\n");
    }

    // 4. Render Bottom Border
    try config.border_color.writeAnsi(writer, false);
    try writer.writeAll(border_chars.bottom_left);
    for (0..total_inner_width) |_| try writer.writeAll(border_chars.horizontal);
    try writer.writeAll(border_chars.bottom_right);
    try style_mod.resetAnsi(writer);
    try writer.writeAll("\n");
}

test "Box rendering with rounded borders and title" {
    var buf: std.ArrayList(u8) = .empty;
    defer buf.deinit(std.testing.allocator);
    const w = style_mod.bufferWriter(std.testing.allocator, &buf);

    try render(w, .{
        .title = "Status",
        .border = .rounded,
        .border_color = .none,
        .title_color = .none,
    }, "System OK\nMemory: 40MB");

    const out = buf.items;
    try std.testing.expect(std.mem.indexOf(u8, out, "╭") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "Status") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "System OK") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "╰") != null);
}
