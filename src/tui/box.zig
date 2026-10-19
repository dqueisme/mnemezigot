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

pub fn isWideChar(cp: u21) bool {
    if (cp >= 0x1100 and cp <= 0x115F) return true;
    if (cp >= 0x231A and cp <= 0x231B) return true;
    if (cp >= 0x23E9 and cp <= 0x23F3) return true;
    if (cp >= 0x25FD and cp <= 0x25FE) return true;
    // Note: 0x2600..0x27BF are Dingbats/Misc Symbols (e.g. ✓ U+2713, ❯ U+276F, ✕ U+2715) which are single-width (1 col) in terminals.
    if (cp >= 0x2B05 and cp <= 0x2B55) return true;
    if (cp >= 0x2E80 and cp <= 0xA4CF) return true;
    if (cp >= 0xAC00 and cp <= 0xD7A3) return true;
    if (cp >= 0xF900 and cp <= 0xFAFF) return true;
    if (cp >= 0xFE10 and cp <= 0xFE19) return true;
    if (cp >= 0xFE30 and cp <= 0xFE6F) return true;
    if (cp >= 0xFF00 and cp <= 0xFF60) return true;
    if (cp >= 0xFFE0 and cp <= 0xFFE6) return true;
    if (cp >= 0x1F000 and cp <= 0x1FBFF) return true;
    return false;
}

/// Calculate visible display column width of UTF-8 string (treating ascii as 1 col, emoji/wide as 2)
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
        if (len >= 3 and i + len <= s.len) {
            const cp = std.unicode.utf8Decode(s[i .. i + len]) catch 0;
            if (isWideChar(cp)) {
                width += 2;
                i += len;
                continue;
            }
        }
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

/// Truncate UTF-8 string to fit within max_width visible display columns.
/// Appends '…' if truncated and max_width >= 2. Skips ANSI escape sequences.
pub fn truncateWidth(allocator: std.mem.Allocator, str: []const u8, max_width: usize) ![]const u8 {
    if (max_width == 0) return "";
    var cur_w: usize = 0;
    var byte_idx: usize = 0;

    const total_w = stringWidth(str);
    if (total_w <= max_width) {
        return try allocator.dupe(u8, str);
    }

    // Reserve 1 display column for '…' if max_width >= 2
    const limit = if (max_width >= 2) max_width - 1 else max_width;

    while (byte_idx < str.len) {
        if (str[byte_idx] == 0x1b and byte_idx + 1 < str.len and str[byte_idx + 1] == '[') {
            byte_idx += 2;
            while (byte_idx < str.len and str[byte_idx] != 'm') : (byte_idx += 1) {}
            if (byte_idx < str.len and str[byte_idx] == 'm') byte_idx += 1;
            continue;
        }

        const len = std.unicode.utf8ByteSequenceLength(str[byte_idx]) catch 1;
        var w: usize = 1;
        if (len >= 3 and byte_idx + len <= str.len) {
            const cp = std.unicode.utf8Decode(str[byte_idx .. byte_idx + len]) catch 0;
            if (isWideChar(cp)) w = 2;
        }

        if (cur_w + w > limit) {
            if (max_width >= 2) {
                return try std.fmt.allocPrint(allocator, "{s}…", .{str[0..byte_idx]});
            } else {
                return try allocator.dupe(u8, str[0..byte_idx]);
            }
        }

        cur_w += w;
        byte_idx += len;
    }

    return try allocator.dupe(u8, str);
}

/// Word wrap UTF-8 text into lines with at most max_width visible columns.
pub fn wrapText(allocator: std.mem.Allocator, text: []const u8, max_width: usize, out_lines: *std.ArrayList([]const u8)) !void {
    if (max_width == 0) return;
    var line_iter = std.mem.splitScalar(u8, text, '\n');
    while (line_iter.next()) |raw_line| {
        if (raw_line.len == 0) {
            try out_lines.append(allocator, try allocator.dupe(u8, ""));
            continue;
        }

        var word_iter = std.mem.tokenizeScalar(u8, raw_line, ' ');
        var cur_buf: std.ArrayList(u8) = .empty;
        errdefer cur_buf.deinit(allocator);
        var cur_w = style_mod.bufferWriter(allocator, &cur_buf);
        var cur_len: usize = 0;

        while (word_iter.next()) |word| {
            const w = stringWidth(word);
            if (cur_len == 0) {
                if (w > max_width) {
                    const truncated = try truncateWidth(allocator, word, max_width);
                    defer allocator.free(truncated);
                    try cur_w.writeAll(truncated);
                    cur_len = stringWidth(truncated);
                } else {
                    try cur_w.writeAll(word);
                    cur_len = w;
                }
            } else if (cur_len + 1 + w <= max_width) {
                try cur_w.writeAll(" ");
                try cur_w.writeAll(word);
                cur_len += 1 + w;
            } else {
                try out_lines.append(allocator, try cur_buf.toOwnedSlice(allocator));
                cur_buf = std.ArrayList(u8).empty;
                cur_w = style_mod.bufferWriter(allocator, &cur_buf);
                if (w > max_width) {
                    const truncated = try truncateWidth(allocator, word, max_width);
                    defer allocator.free(truncated);
                    try cur_w.writeAll(truncated);
                    cur_len = stringWidth(truncated);
                } else {
                    try cur_w.writeAll(word);
                    cur_len = w;
                }
            }
        }
        if (cur_buf.items.len > 0) {
            try out_lines.append(allocator, try cur_buf.toOwnedSlice(allocator));
        } else {
            cur_buf.deinit(allocator);
        }
    }
}

/// Helper for generating two-pane split borders (e.g. ╭───┬───╮ and ╰───┴───╯)
pub const TwoPaneBorder = struct {
    pub fn writeTop(
        writer: anytype,
        left_w: usize,
        right_w: usize,
        left_title: ?[]const u8,
        right_title: ?[]const u8,
        left_color: []const u8,
        right_color: []const u8,
    ) !void {
        try writer.print("{s}╭", .{left_color});
        var left_used: usize = 1;
        if (left_title) |lt| {
            try writer.print("─ {s} ", .{lt});
            left_used += 3 + stringWidth(lt);
        }
        if (left_w > left_used + 1) {
            for (0..(left_w - left_used - 1)) |_| try writer.writeAll("─");
        }
        try writer.writeAll("┬");

        try writer.print("{s}", .{right_color});
        var right_used: usize = 0;
        if (right_title) |rt| {
            try writer.print("─ {s} ", .{rt});
            right_used += 3 + stringWidth(rt);
        }
        if (right_w > right_used + 1) {
            for (0..(right_w - right_used - 1)) |_| try writer.writeAll("─");
        }
        try writer.print("╮\x1b[0m", .{});
    }

    pub fn writeBottom(
        writer: anytype,
        left_w: usize,
        right_w: usize,
        left_hint: ?[]const u8,
        right_hint: ?[]const u8,
        left_color: []const u8,
        right_color: []const u8,
    ) !void {
        try writer.print("{s}╰", .{left_color});
        var left_used: usize = 1;
        if (left_hint) |lh| {
            try writer.print("─ {s} ", .{lh});
            left_used += 3 + stringWidth(lh);
        }
        if (left_w > left_used + 1) {
            for (0..(left_w - left_used - 1)) |_| try writer.writeAll("─");
        }
        try writer.writeAll("┴");

        try writer.print("{s}", .{right_color});
        var right_used: usize = 0;
        if (right_hint) |rh| {
            try writer.print("─ {s} ", .{rh});
            right_used += 3 + stringWidth(rh);
        }
        if (right_w > right_used + 1) {
            for (0..(right_w - right_used - 1)) |_| try writer.writeAll("─");
        }
        try writer.print("╯\x1b[0m", .{});
    }
};

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

test "stringWidth calculates single-width symbols correctly" {
    try std.testing.expectEqual(@as(usize, 1), stringWidth("✓"));
    try std.testing.expectEqual(@as(usize, 1), stringWidth("❯"));
    try std.testing.expectEqual(@as(usize, 1), stringWidth("▲"));
    try std.testing.expectEqual(@as(usize, 1), stringWidth("●"));
    try std.testing.expectEqual(@as(usize, 1), stringWidth("·"));
    try std.testing.expectEqual(@as(usize, 13), stringWidth("[1] · Backlog"));
}

test "truncateWidth handles plain and wide text correctly" {
    const alloc = std.testing.allocator;
    const s1 = try truncateWidth(alloc, "Hello World", 8);
    defer alloc.free(s1);
    try std.testing.expectEqualStrings("Hello W…", s1);
    try std.testing.expect(stringWidth(s1) <= 8);

    const s2 = try truncateWidth(alloc, "Short", 10);
    defer alloc.free(s2);
    try std.testing.expectEqualStrings("Short", s2);

    const s3 = try truncateWidth(alloc, "A", 0);
    defer alloc.free(s3);
    try std.testing.expectEqualStrings("", s3);
}

test "wrapText splits words within column budget" {
    const alloc = std.testing.allocator;
    var lines = std.ArrayList([]const u8).empty;
    defer {
        for (lines.items) |l| alloc.free(l);
        lines.deinit(alloc);
    }

    try wrapText(alloc, "The quick brown fox jumps over the lazy dog", 15, &lines);
    try std.testing.expect(lines.items.len >= 3);
    for (lines.items) |l| {
        try std.testing.expect(stringWidth(l) <= 15);
    }
}

test "TwoPaneBorder generates aligned top and bottom split borders" {
    var buf: std.ArrayList(u8) = .empty;
    defer buf.deinit(std.testing.allocator);
    const w = style_mod.bufferWriter(std.testing.allocator, &buf);

    try TwoPaneBorder.writeTop(w, 20, 30, "Left", "Right", "", "");
    try w.writeAll("\n");
    try TwoPaneBorder.writeBottom(w, 20, 30, "1 of 5", null, "", "");

    const out = buf.items;
    try std.testing.expect(std.mem.indexOf(u8, out, "╭─ Left ───────────┬─ Right ─────────────────────╮") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "╰─ 1 of 5 ─────────┴─────────────────────────────╯") != null);
}
