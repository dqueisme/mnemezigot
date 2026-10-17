const std = @import("std");
const style_mod = @import("style.zig");
const Color = style_mod.Color;
const Style = style_mod.Style;

pub const BadgeVariant = enum {
    success,
    @"error",
    warning,
    info,
    neutral,
};

/// Render a styled status pill badge (e.g. [ SUCCESS ], [ ERROR ])
pub fn badge(writer: anytype, variant: BadgeVariant, label: []const u8) !void {
    const fg: Color = switch (variant) {
        .success => .bright_green,
        .@"error" => .bright_red,
        .warning => .bright_yellow,
        .info => .bright_cyan,
        .neutral => .bright_black,
    };

    try writer.writeAll("[ ");
    try style_mod.writeStyled(writer, label, fg, .none, .{ .bold = true });
    try writer.writeAll(" ]");
}

pub const ProgressBarConfig = struct {
    width: usize = 20,
    fill_char: []const u8 = "█",
    empty_char: []const u8 = "░",
    fill_color: Color = .green,
    empty_color: Color = .bright_black,
    show_percentage: bool = true,
};

/// Render a visual progress bar
pub fn progressBar(writer: anytype, current: usize, total: usize, config: ProgressBarConfig) !void {
    const safe_total = if (total == 0) 1 else total;
    const clamped_current = @min(current, safe_total);
    const percentage = @as(f64, @floatFromInt(clamped_current)) / @as(f64, @floatFromInt(safe_total));
    const filled_slots = @as(usize, @intFromFloat(percentage * @as(f64, @floatFromInt(config.width))));
    const empty_slots = if (config.width > filled_slots) config.width - filled_slots else 0;

    try writer.writeAll("[");
    try config.fill_color.writeAnsi(writer, false);
    for (0..filled_slots) |_| {
        try writer.writeAll(config.fill_char);
    }
    try style_mod.resetAnsi(writer);

    try config.empty_color.writeAnsi(writer, false);
    for (0..empty_slots) |_| {
        try writer.writeAll(config.empty_char);
    }
    try style_mod.resetAnsi(writer);
    try writer.writeAll("]");

    if (config.show_percentage) {
        const pct_int = @as(u32, @intFromFloat(percentage * 100.0));
        try writer.print(" {d}%", .{pct_int});
    }
}

pub const SpinnerStyle = enum {
    dots,
    line,
    block,
    arrow,

    pub fn frames(self: SpinnerStyle) []const []const u8 {
        return switch (self) {
            .dots => &.{ "⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏" },
            .line => &.{ "|", "/", "-", "\\" },
            .block => &.{ "▌", "▀", "▐", "▄" },
            .arrow => &.{ "←", "↖", "↑", "↗", "→", "↘", "↓", "↙" },
        };
    }

    pub fn getFrame(self: SpinnerStyle, tick: usize) []const u8 {
        const f = self.frames();
        return f[tick % f.len];
    }
};

/// Render single spinner tick frame with label
pub fn spinner(writer: anytype, style: SpinnerStyle, tick: usize, color: Color, label: []const u8) !void {
    const frame = style.getFrame(tick);
    try color.writeAnsi(writer, false);
    try writer.writeAll(frame);
    try style_mod.resetAnsi(writer);
    try writer.print(" {s}", .{label});
}

pub const ListType = enum {
    bullet,
    numbered,
    check,
};

/// Render list items
pub fn list(writer: anytype, items: []const []const u8, list_type: ListType) !void {
    for (items, 0..) |item, i| {
        switch (list_type) {
            .bullet => try writer.print("  • {s}\n", .{item}),
            .numbered => try writer.print("  {d}. {s}\n", .{ i + 1, item }),
            .check => try writer.print("  [✓] {s}\n", .{item}),
        }
    }
}

/// Render aligned Key: Value pair
pub fn keyVal(writer: anytype, key: []const u8, val: []const u8, min_key_width: usize) !void {
    try style_mod.writeStyled(writer, key, .cyan, .none, .{ .bold = true });
    try writer.writeAll(":");

    const k_len = key.len + 1;
    const pad = if (min_key_width > k_len) min_key_width - k_len else 1;
    for (0..pad) |_| try writer.writeAll(" ");

    try writer.print("{s}\n", .{val});
}

test "Widgets rendering" {
    var buf: std.ArrayList(u8) = .empty;
    defer buf.deinit(std.testing.allocator);
    const w = style_mod.bufferWriter(std.testing.allocator, &buf);

    try badge(w, .success, "ACTIVE");
    try w.writeAll(" ");
    try progressBar(w, 50, 100, .{ .width = 10 });
    try w.writeAll("\n");
    try spinner(w, .dots, 2, .cyan, "Compiling...");
    try w.writeAll("\n");
    try list(w, &.{ "Item 1", "Item 2" }, .bullet);
    try keyVal(w, "Version", "0.16.0", 12);

    const out = buf.items;
    try std.testing.expect(std.mem.indexOf(u8, out, "ACTIVE") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "50%") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "Compiling...") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "• Item 1") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "Version") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "0.16.0") != null);
}
