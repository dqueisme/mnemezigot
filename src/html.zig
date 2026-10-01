const std = @import("std");

/// HTML Attribute pair
pub const Attribute = struct {
    name: []const u8,
    value: []const u8,
};

/// Type-safe HTML Node
pub const Node = struct {
    tag: []const u8,
    attrs: []const Attribute = &.{},
    children: []const []const u8 = &.{},
    is_text: bool = false,
    text_content: []const u8 = "",

    /// Render HTML Node to string with auto-escaping for text content
    pub fn render(self: Node, allocator: std.mem.Allocator) ![]const u8 {
        if (self.is_text) {
            return try escapeHtml(allocator, self.text_content);
        }

        var buf: std.ArrayList(u8) = .empty;
        defer buf.deinit(allocator);

        try std.fmt.format(buf.writer(allocator), "<{s}", .{self.tag});

        for (self.attrs) |attr| {
            const escaped_val = try escapeHtml(allocator, attr.value);
            defer allocator.free(escaped_val);
            try std.fmt.format(buf.writer(allocator), " {s}=\"{s}\"", .{ attr.name, escaped_val });
        }

        // Self-closing void tags
        if (std.mem.eql(u8, self.tag, "img") or std.mem.eql(u8, self.tag, "input") or std.mem.eql(u8, self.tag, "br") or std.mem.eql(u8, self.tag, "meta") or std.mem.eql(u8, self.tag, "link")) {
            try buf.appendSlice(allocator, " />");
            return buf.toOwnedSlice(allocator);
        }

        try buf.append(allocator, '>');

        for (self.children) |child| {
            try buf.appendSlice(allocator, child);
        }

        try std.fmt.format(buf.writer(allocator), "</{s}>", .{self.tag});

        return buf.toOwnedSlice(allocator);
    }
};

/// Helper to escape special HTML characters to prevent XSS
pub fn escapeHtml(allocator: std.mem.Allocator, input: []const u8) ![]const u8 {
    var buf: std.ArrayList(u8) = .empty;
    defer buf.deinit(allocator);

    for (input) |ch| {
        switch (ch) {
            '<' => try buf.appendSlice(allocator, "&lt;"),
            '>' => try buf.appendSlice(allocator, "&gt;"),
            '&' => try buf.appendSlice(allocator, "&amp;"),
            '"' => try buf.appendSlice(allocator, "&quot;"),
            '\'' => try buf.appendSlice(allocator, "&#39;"),
            else => try buf.append(allocator, ch),
        }
    }

    return buf.toOwnedSlice(allocator);
}

/// Helper functions to construct HTML elements
pub fn element(tag: []const u8, attrs: []const Attribute, children: []const []const u8) Node {
    return .{
        .tag = tag,
        .attrs = attrs,
        .children = children,
    };
}

pub fn text(content: []const u8) Node {
    return .{
        .tag = "",
        .is_text = true,
        .text_content = content,
    };
}

pub fn attr(name: []const u8, value: []const u8) Attribute {
    return .{ .name = name, .value = value };
}

test "HTML Builder Node rendering & escaping" {
    const allocator = std.testing.allocator;

    const escaped_text = try text("<script>alert('xss')</script>").render(allocator);
    defer allocator.free(escaped_text);
    try std.testing.expectEqualStrings("&lt;script&gt;alert(&#39;xss&#39;)&lt;/script&gt;", escaped_text);

    const btn = element("button", &.{ attr("class", "btn primary"), attr("hx-get", "/api/data") }, &.{ "Click Me" });
    const rendered_btn = try btn.render(allocator);
    defer allocator.free(rendered_btn);

    try std.testing.expectEqualStrings("<button class=\"btn primary\" hx-get=\"/api/data\">Click Me</button>", rendered_btn);
}
