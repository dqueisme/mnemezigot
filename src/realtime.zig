const std = @import("std");
const ws = @import("ws.zig");

pub const ClientSession = struct {
    id: []const u8,
    channel: []const u8,
};

/// High-Level Realtime Broadcast Hub for Mnemezigot
pub const RealtimeHub = struct {
    mutex: std.atomic.Mutex = .unlocked,
    sessions: std.ArrayList(ClientSession),
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) RealtimeHub {
        return .{
            .sessions = std.ArrayList(ClientSession).empty,
            .allocator = allocator,
        };
    }

    pub fn subscribe(self: *RealtimeHub, client_id: []const u8, channel: []const u8) !void {
        while (!self.mutex.tryLock()) {
            std.atomic.spinLoopHint();
        }
        defer self.mutex.unlock();

        const id_copy = try self.allocator.dupe(u8, client_id);
        const chan_copy = try self.allocator.dupe(u8, channel);

        try self.sessions.append(self.allocator, .{
            .id = id_copy,
            .channel = chan_copy,
        });
    }

    pub fn unsubscribe(self: *RealtimeHub, client_id: []const u8) void {
        while (!self.mutex.tryLock()) {
            std.atomic.spinLoopHint();
        }
        defer self.mutex.unlock();

        var i: usize = 0;
        while (i < self.sessions.items.len) {
            if (std.mem.eql(u8, self.sessions.items[i].id, client_id)) {
                self.allocator.free(self.sessions.items[i].id);
                self.allocator.free(self.sessions.items[i].channel);
                _ = self.sessions.swapRemove(i);
            } else {
                i += 1;
            }
        }
    }

    pub fn countSubscribers(self: *RealtimeHub, channel: []const u8) usize {
        while (!self.mutex.tryLock()) {
            std.atomic.spinLoopHint();
        }
        defer self.mutex.unlock();

        var count: usize = 0;
        for (self.sessions.items) |sess| {
            if (std.mem.eql(u8, sess.channel, channel)) {
                count += 1;
            }
        }
        return count;
    }

    pub fn broadcast(self: *RealtimeHub, channel: []const u8, message: []const u8) !usize {
        while (!self.mutex.tryLock()) {
            std.atomic.spinLoopHint();
        }
        defer self.mutex.unlock();

        var sent_count: usize = 0;
        for (self.sessions.items) |sess| {
            if (std.mem.eql(u8, sess.channel, channel)) {
                const frame = ws.Frame{
                    .fin = true,
                    .opcode = .text,
                    .payload = message,
                };
                const encoded = try frame.encode(self.allocator);
                self.allocator.free(encoded);
                sent_count += 1;
            }
        }
        return sent_count;
    }

    pub fn deinit(self: *RealtimeHub) void {
        for (self.sessions.items) |sess| {
            self.allocator.free(sess.id);
            self.allocator.free(sess.channel);
        }
        self.sessions.deinit(self.allocator);
    }
};

test "RealtimeHub channel subscribe and broadcast" {
    const allocator = std.testing.allocator;

    var hub = RealtimeHub.init(allocator);
    defer hub.deinit();

    try hub.subscribe("client1", "chat_room_1");
    try hub.subscribe("client2", "chat_room_1");
    try hub.subscribe("client3", "notifications");

    try std.testing.expectEqual(@as(usize, 2), hub.countSubscribers("chat_room_1"));
    try std.testing.expectEqual(@as(usize, 1), hub.countSubscribers("notifications"));

    const broadcast_sent = try hub.broadcast("chat_room_1", "{\"type\":\"msg\",\"text\":\"Hello World\"}");
    try std.testing.expectEqual(@as(usize, 2), broadcast_sent);

    hub.unsubscribe("client1");
    try std.testing.expectEqual(@as(usize, 1), hub.countSubscribers("chat_room_1"));
}
