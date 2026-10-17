const std = @import("std");
const style_mod = @import("style.zig");
const box_mod = @import("box.zig");
const table_mod = @import("table.zig");
const widgets_mod = @import("widgets.zig");
const terminal_mod = @import("terminal.zig");

pub const Color = style_mod.Color;
pub const Style = style_mod.Style;
pub const BorderStyle = box_mod.BorderStyle;
pub const BoxConfig = box_mod.BoxConfig;
pub const Table = table_mod.Table;
pub const BadgeVariant = widgets_mod.BadgeVariant;
pub const ProgressBarConfig = widgets_mod.ProgressBarConfig;
pub const SpinnerStyle = widgets_mod.SpinnerStyle;
pub const ListType = widgets_mod.ListType;

/// Fluent, stateful TUI Layout and Screen Builder
pub const Builder = struct {
    allocator: std.mem.Allocator,
    buffer: std.ArrayList(u8),

    pub fn init(allocator: std.mem.Allocator) Builder {
        return .{
            .allocator = allocator,
            .buffer = std.ArrayList(u8).empty,
        };
    }

    pub fn deinit(self: *Builder) void {
        self.buffer.deinit(self.allocator);
    }

    pub fn reset(self: *Builder) void {
        self.buffer.clearRetainingCapacity();
    }

    fn writer(self: *Builder) style_mod.BufferWriter {
        return style_mod.bufferWriter(self.allocator, &self.buffer);
    }

    /// Add a prominent styled header/title with underline
    pub fn title(self: *Builder, title_text: []const u8) !*Builder {
        const w = self.writer();
        try style_mod.writeStyled(w, title_text, .bright_cyan, .none, .{ .bold = true });
        try w.writeAll("\n");
        for (0..box_mod.stringWidth(title_text)) |_| {
            try style_mod.writeStyled(w, "═", .cyan, .none, .{});
        }
        try w.writeAll("\n");
        return self;
    }

    /// Add a section subtitle
    pub fn subtitle(self: *Builder, sub_text: []const u8) !*Builder {
        const w = self.writer();
        try style_mod.writeStyled(w, sub_text, .bright_yellow, .none, .{ .bold = true });
        try w.writeAll("\n");
        return self;
    }

    /// Add plain text followed by newline
    pub fn text(self: *Builder, content: []const u8) !*Builder {
        const w = self.writer();
        try w.writeAll(content);
        try w.writeAll("\n");
        return self;
    }

    /// Add styled text followed by newline
    pub fn styledText(self: *Builder, content: []const u8, fg: Color, style: Style) !*Builder {
        const w = self.writer();
        try style_mod.writeStyled(w, content, fg, .none, style);
        try w.writeAll("\n");
        return self;
    }

    /// Add a status badge
    pub fn badge(self: *Builder, variant: BadgeVariant, label: []const u8) !*Builder {
        const w = self.writer();
        try widgets_mod.badge(w, variant, label);
        return self;
    }

    /// Add an aligned key-value pair
    pub fn keyVal(self: *Builder, key: []const u8, val: []const u8) !*Builder {
        const w = self.writer();
        try widgets_mod.keyVal(w, key, val, 16);
        return self;
    }

    /// Add a framed box container
    pub fn box(self: *Builder, config: BoxConfig, content: []const u8) !*Builder {
        const w = self.writer();
        try box_mod.render(w, config, content);
        return self;
    }

    /// Add a visual progress bar
    pub fn progress(self: *Builder, current: usize, total: usize, config: ProgressBarConfig) !*Builder {
        const w = self.writer();
        try widgets_mod.progressBar(w, current, total, config);
        try w.writeAll("\n");
        return self;
    }

    /// Add an item list
    pub fn list(self: *Builder, items: []const []const u8, list_type: ListType) !*Builder {
        const w = self.writer();
        try widgets_mod.list(w, items, list_type);
        return self;
    }

    /// Add a horizontal divider line
    pub fn divider(self: *Builder, char: []const u8, width: usize) !*Builder {
        const w = self.writer();
        for (0..width) |_| {
            try w.writeAll(char);
        }
        try w.writeAll("\n");
        return self;
    }

    /// Add empty newline
    pub fn newline(self: *Builder) !*Builder {
        const w = self.writer();
        try w.writeAll("\n");
        return self;
    }

    /// Render built output to any writer
    pub fn render(self: *const Builder, out_writer: anytype) !void {
        try out_writer.writeAll(self.buffer.items);
    }

    /// Extract rendered string as owned slice
    pub fn toOwnedSlice(self: *Builder) ![]u8 {
        return self.buffer.toOwnedSlice(self.allocator);
    }

    /// Peek rendered bytes
    pub fn string(self: *const Builder) []const u8 {
        return self.buffer.items;
    }
};

test "TUI Builder fluent construction" {
    var b = Builder.init(std.testing.allocator);
    defer b.deinit();

    _ = try (try (try (try b.title("Mnemezigot Control Panel"))
        .keyVal("Framework", "Zig 0.16"))
        .keyVal("Database", "SQLite WAL"))
        .box(.{ .title = "Server Info", .border = .rounded }, "Status: Running\nPort: 8080");

    const out = b.string();
    try std.testing.expect(std.mem.indexOf(u8, out, "Mnemezigot Control Panel") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "Framework") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "Server Info") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "Port: 8080") != null);
}
