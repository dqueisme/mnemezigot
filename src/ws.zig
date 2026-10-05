const std = @import("std");

const websocket_magic_guid = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11";

pub const Opcode = enum(u4) {
    continuation = 0x0,
    text = 0x1,
    binary = 0x2,
    close = 0x8,
    ping = 0x9,
    pong = 0xA,
};

pub const Frame = struct {
    fin: bool = true,
    opcode: Opcode = .text,
    payload: []const u8,

    pub fn encode(self: Frame, allocator: std.mem.Allocator) ![]const u8 {
        var buf: std.ArrayList(u8) = .empty;
        defer buf.deinit(allocator);

        const first_byte: u8 = (if (self.fin) @as(u8, 0x80) else 0x00) | @intFromEnum(self.opcode);
        try buf.append(allocator, first_byte);

        const len = self.payload.len;
        if (len <= 125) {
            try buf.append(allocator, @intCast(len));
        } else if (len <= 65535) {
            try buf.append(allocator, 126);
            var len_bytes: [2]u8 = undefined;
            std.mem.writeInt(u16, &len_bytes, @intCast(len), .big);
            try buf.appendSlice(allocator, &len_bytes);
        } else {
            try buf.append(allocator, 127);
            var len_bytes: [8]u8 = undefined;
            std.mem.writeInt(u64, &len_bytes, @intCast(len), .big);
            try buf.appendSlice(allocator, &len_bytes);
        }

        try buf.appendSlice(allocator, self.payload);
        return buf.toOwnedSlice(allocator);
    }
};

/// Compute RFC 6455 Sec-WebSocket-Accept header value
pub fn computeAcceptKey(allocator: std.mem.Allocator, client_key: []const u8) ![]const u8 {
    const concat = try std.fmt.allocPrint(allocator, "{s}{s}", .{ client_key, websocket_magic_guid });
    defer allocator.free(concat);

    var sha1_buf: [20]u8 = undefined;
    std.crypto.hash.Sha1.hash(concat, &sha1_buf, .{});

    var b64_buf: [32]u8 = undefined;
    const encoded = std.base64.standard.Encoder.encode(&b64_buf, &sha1_buf);
    return try allocator.dupe(u8, encoded);
}

/// Simple Chat Room & Broadcast Manager for WebSockets
pub const WsHub = struct {
    mutex: std.atomic.Mutex = .unlocked,
    clients: std.ArrayList([]const u8),
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) WsHub {
        return .{
            .clients = std.ArrayList([]const u8).empty,
            .allocator = allocator,
        };
    }

    pub fn registerClient(self: *WsHub, client_id: []const u8) !void {
        while (!self.mutex.tryLock()) {
            std.atomic.spinLoopHint();
        }
        defer self.mutex.unlock();

        const id_copy = try self.allocator.dupe(u8, client_id);
        try self.clients.append(self.allocator, id_copy);
    }

    pub fn unregisterClient(self: *WsHub, client_id: []const u8) void {
        while (!self.mutex.tryLock()) {
            std.atomic.spinLoopHint();
        }
        defer self.mutex.unlock();

        var i: usize = 0;
        while (i < self.clients.items.len) {
            if (std.mem.eql(u8, self.clients.items[i], client_id)) {
                self.allocator.free(self.clients.items[i]);
                _ = self.clients.swapRemove(i);
            } else {
                i += 1;
            }
        }
    }

    pub fn clientCount(self: *WsHub) usize {
        while (!self.mutex.tryLock()) {
            std.atomic.spinLoopHint();
        }
        defer self.mutex.unlock();

        return self.clients.items.len;
    }

    pub fn deinit(self: *WsHub) void {
        for (self.clients.items) |c| {
            self.allocator.free(c);
        }
        self.clients.deinit(self.allocator);
    }
};

test "Sec-WebSocket-Accept key computation" {
    const allocator = std.testing.allocator;
    const client_key = "dGhlIHNhbXBsZSBub25jZQ==";
    const accept_key = try computeAcceptKey(allocator, client_key);
    defer allocator.free(accept_key);

    try std.testing.expectEqualStrings("s3pPLMBiTxaQ9kYGzzhZRbK+xOo=", accept_key);
}

test "WebSocket Frame encoding" {
    const allocator = std.testing.allocator;
    const frame = Frame{
        .fin = true,
        .opcode = .text,
        .payload = "Hello WebSocket",
    };

    const encoded = try frame.encode(allocator);
    defer allocator.free(encoded);

    try std.testing.expectEqual(@as(u8, 0x81), encoded[0]); // Fin + Text
    try std.testing.expectEqual(@as(u8, 15), encoded[1]); // Payload length 15
    try std.testing.expectEqualStrings("Hello WebSocket", encoded[2..]);
}

test "WsHub registration and broadcast" {
    const allocator = std.testing.allocator;
    var hub = WsHub.init(allocator);
    defer hub.deinit();

    try hub.registerClient("user_alice");
    try hub.registerClient("user_bob");

    try std.testing.expectEqual(@as(usize, 2), hub.clientCount());

    hub.unregisterClient("user_alice");
    try std.testing.expectEqual(@as(usize, 1), hub.clientCount());
}
