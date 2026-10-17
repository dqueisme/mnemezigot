const std = @import("std");
const style_mod = @import("style.zig");
const Color = style_mod.Color;
const Style = style_mod.Style;

/// Ask a yes/no confirmation prompt
pub fn confirm(reader: anytype, writer: anytype, prompt_text: []const u8, default_yes: bool) !bool {
    try style_mod.writeStyled(writer, "? ", .bright_cyan, .none, .{ .bold = true });
    try writer.writeAll(prompt_text);

    if (default_yes) {
        try writer.writeAll(" (Y/n): ");
    } else {
        try writer.writeAll(" (y/N): ");
    }

    var buf: [32]u8 = undefined;
    const input = try readLine(reader, &buf);

    if (input.len == 0) return default_yes;
    if (std.ascii.toLower(input[0]) == 'y') return true;
    if (std.ascii.toLower(input[0]) == 'n') return false;

    return default_yes;
}

/// Ask for text input with optional default value
pub fn ask(allocator: std.mem.Allocator, reader: anytype, writer: anytype, prompt_text: []const u8, default_val: ?[]const u8) ![]const u8 {
    try style_mod.writeStyled(writer, "? ", .bright_cyan, .none, .{ .bold = true });
    try writer.writeAll(prompt_text);

    if (default_val) |def| {
        try writer.print(" [{s}]", .{def});
    }
    try writer.writeAll(": ");

    var buf: [512]u8 = undefined;
    const input = try readLine(reader, &buf);

    if (input.len == 0 and default_val != null) {
        return try allocator.dupe(u8, default_val.?);
    }
    return try allocator.dupe(u8, input);
}

/// Helper to read a single line up to \n or \r\n
fn readLine(reader: anytype, buf: []u8) ![]const u8 {
    var idx: usize = 0;
    while (idx < buf.len) {
        const byte = reader.readByte() catch |err| {
            if (err == error.EndOfStream) break;
            return err;
        };
        if (byte == '\n') break;
        if (byte == '\r') continue;
        buf[idx] = byte;
        idx += 1;
    }
    return std.mem.trim(u8, buf[0..idx], " \t");
}

test "Prompt confirm and ask simulation" {
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

    var mock = MockReader{ .slice = "yes\ncustom_value\n" };

    var buf: std.ArrayList(u8) = .empty;
    defer buf.deinit(std.testing.allocator);
    const writer = style_mod.bufferWriter(std.testing.allocator, &buf);

    const is_yes = try confirm(&mock, writer, "Do you want to proceed?", false);
    try std.testing.expect(is_yes);

    const answer = try ask(std.testing.allocator, &mock, writer, "Enter project name", "my-app");
    defer std.testing.allocator.free(answer);
    try std.testing.expectEqualStrings("custom_value", answer);
}
