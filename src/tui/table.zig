const std = @import("std");
const style_mod = @import("style.zig");
const box_mod = @import("box.zig");
const Color = style_mod.Color;
const Style = style_mod.Style;
const BorderStyle = box_mod.BorderStyle;
const stringWidth = box_mod.stringWidth;

pub const Alignment = enum {
    left,
    center,
    right,
};

pub const TableBorderGlyphs = struct {
    top_left: []const u8,
    top_mid: []const u8,
    top_right: []const u8,
    mid_left: []const u8,
    mid_mid: []const u8,
    mid_right: []const u8,
    bot_left: []const u8,
    bot_mid: []const u8,
    bot_right: []const u8,
    horizontal: []const u8,
    vertical: []const u8,
};

pub fn getTableGlyphs(border: BorderStyle) TableBorderGlyphs {
    return switch (border) {
        .ascii => .{
            .top_left = "+",
            .top_mid = "+",
            .top_right = "+",
            .mid_left = "+",
            .mid_mid = "+",
            .mid_right = "+",
            .bot_left = "+",
            .bot_mid = "+",
            .bot_right = "+",
            .horizontal = "-",
            .vertical = "|",
        },
        .single => .{
            .top_left = "┌",
            .top_mid = "┬",
            .top_right = "┐",
            .mid_left = "├",
            .mid_mid = "┼",
            .mid_right = "┤",
            .bot_left = "└",
            .bot_mid = "┴",
            .bot_right = "┘",
            .horizontal = "─",
            .vertical = "│",
        },
        .rounded => .{
            .top_left = "╭",
            .top_mid = "┬",
            .top_right = "╮",
            .mid_left = "├",
            .mid_mid = "┼",
            .mid_right = "┤",
            .bot_left = "╰",
            .bot_mid = "┴",
            .bot_right = "╯",
            .horizontal = "─",
            .vertical = "│",
        },
        .double => .{
            .top_left = "╔",
            .top_mid = "╦",
            .top_right = "╗",
            .mid_left = "╠",
            .mid_mid = "╬",
            .mid_right = "╣",
            .bot_left = "╚",
            .bot_mid = "╩",
            .bot_right = "╝",
            .horizontal = "═",
            .vertical = "║",
        },
        .thick => .{
            .top_left = "┏",
            .top_mid = "┳",
            .top_right = "┓",
            .mid_left = "┣",
            .mid_mid = "╋",
            .mid_right = "┫",
            .bot_left = "┗",
            .bot_mid = "┻",
            .bot_right = "┛",
            .horizontal = "━",
            .vertical = "┃",
        },
        .none => .{
            .top_left = " ",
            .top_mid = " ",
            .top_right = " ",
            .mid_left = " ",
            .mid_mid = " ",
            .mid_right = " ",
            .bot_left = " ",
            .bot_mid = " ",
            .bot_right = " ",
            .horizontal = " ",
            .vertical = " ",
        },
    };
}

pub const Table = struct {
    allocator: std.mem.Allocator,
    headers: std.ArrayList([]const u8),
    rows: std.ArrayList(std.ArrayList([]const u8)),
    border_style: BorderStyle = .rounded,
    border_color: Color = .cyan,
    header_color: Color = .bright_yellow,
    header_style: Style = .{ .bold = true },
    row_color: Color = .none,
    padding_x: usize = 1,

    pub fn init(allocator: std.mem.Allocator) Table {
        return .{
            .allocator = allocator,
            .headers = std.ArrayList([]const u8).empty,
            .rows = std.ArrayList(std.ArrayList([]const u8)).empty,
        };
    }

    pub fn deinit(self: *Table) void {
        for (self.rows.items) |*row| {
            row.deinit(self.allocator);
        }
        self.rows.deinit(self.allocator);
        self.headers.deinit(self.allocator);
    }

    pub fn setHeaders(self: *Table, hdrs: []const []const u8) !void {
        self.headers.clearRetainingCapacity();
        for (hdrs) |h| {
            try self.headers.append(self.allocator, h);
        }
    }

    pub fn addRow(self: *Table, cells: []const []const u8) !void {
        var row = std.ArrayList([]const u8).empty;
        for (cells) |c| {
            try row.append(self.allocator, c);
        }
        try self.rows.append(self.allocator, row);
    }

    pub fn render(self: *Table, writer: anytype) !void {
        const col_count = self.headers.items.len;
        if (col_count == 0) return;

        // 1. Calculate max width per column
        const col_widths = try self.allocator.alloc(usize, col_count);
        defer self.allocator.free(col_widths);

        for (self.headers.items, 0..) |h, i| {
            col_widths[i] = stringWidth(h);
        }

        for (self.rows.items) |row| {
            for (row.items, 0..) |cell, i| {
                if (i < col_count) {
                    const w = stringWidth(cell);
                    if (w > col_widths[i]) col_widths[i] = w;
                }
            }
        }

        const glyphs = getTableGlyphs(self.border_style);

        // 2. Render Top Border
        try self.border_color.writeAnsi(writer, false);
        try writer.writeAll(glyphs.top_left);
        for (col_widths, 0..) |w, i| {
            for (0..w + self.padding_x * 2) |_| try writer.writeAll(glyphs.horizontal);
            if (i + 1 < col_count) {
                try writer.writeAll(glyphs.top_mid);
            }
        }
        try writer.writeAll(glyphs.top_right);
        try style_mod.resetAnsi(writer);
        try writer.writeAll("\n");

        // 3. Render Header Row
        try self.border_color.writeAnsi(writer, false);
        try writer.writeAll(glyphs.vertical);
        try style_mod.resetAnsi(writer);

        for (self.headers.items, 0..) |h, i| {
            for (0..self.padding_x) |_| try writer.writeAll(" ");

            try style_mod.writeStyled(writer, h, self.header_color, .none, self.header_style);

            const sw = stringWidth(h);
            const pad = if (col_widths[i] > sw) col_widths[i] - sw else 0;
            for (0..pad + self.padding_x) |_| try writer.writeAll(" ");

            try self.border_color.writeAnsi(writer, false);
            try writer.writeAll(glyphs.vertical);
            try style_mod.resetAnsi(writer);
        }
        try writer.writeAll("\n");

        // 4. Render Middle Separator
        try self.border_color.writeAnsi(writer, false);
        try writer.writeAll(glyphs.mid_left);
        for (col_widths, 0..) |w, i| {
            for (0..w + self.padding_x * 2) |_| try writer.writeAll(glyphs.horizontal);
            if (i + 1 < col_count) {
                try writer.writeAll(glyphs.mid_mid);
            }
        }
        try writer.writeAll(glyphs.mid_right);
        try style_mod.resetAnsi(writer);
        try writer.writeAll("\n");

        // 5. Render Data Rows
        for (self.rows.items) |row| {
            try self.border_color.writeAnsi(writer, false);
            try writer.writeAll(glyphs.vertical);
            try style_mod.resetAnsi(writer);

            for (0..col_count) |i| {
                const cell = if (i < row.items.len) row.items[i] else "";
                for (0..self.padding_x) |_| try writer.writeAll(" ");

                try self.row_color.writeAnsi(writer, false);
                try writer.writeAll(cell);
                try style_mod.resetAnsi(writer);

                const sw = stringWidth(cell);
                const pad = if (col_widths[i] > sw) col_widths[i] - sw else 0;
                for (0..pad + self.padding_x) |_| try writer.writeAll(" ");

                try self.border_color.writeAnsi(writer, false);
                try writer.writeAll(glyphs.vertical);
                try style_mod.resetAnsi(writer);
            }
            try writer.writeAll("\n");
        }

        // 6. Render Bottom Border
        try self.border_color.writeAnsi(writer, false);
        try writer.writeAll(glyphs.bot_left);
        for (col_widths, 0..) |w, i| {
            for (0..w + self.padding_x * 2) |_| try writer.writeAll(glyphs.horizontal);
            if (i + 1 < col_count) {
                try writer.writeAll(glyphs.bot_mid);
            }
        }
        try writer.writeAll(glyphs.bot_right);
        try style_mod.resetAnsi(writer);
        try writer.writeAll("\n");
    }
};

test "Table rendering with columns and rows" {
    var tbl = Table.init(std.testing.allocator);
    defer tbl.deinit();

    tbl.border_color = .none;
    tbl.header_color = .none;

    try tbl.setHeaders(&.{ "ID", "Nama", "Peran" });
    try tbl.addRow(&.{ "1", "Huda", "PM" });
    try tbl.addRow(&.{ "2", "Dimas", "Senior Dev" });

    var buf: std.ArrayList(u8) = .empty;
    defer buf.deinit(std.testing.allocator);
    const w = style_mod.bufferWriter(std.testing.allocator, &buf);

    try tbl.render(w);

    const out = buf.items;
    try std.testing.expect(std.mem.indexOf(u8, out, "Nama") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "Dimas") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "Senior Dev") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "╭") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "╰") != null);
}
