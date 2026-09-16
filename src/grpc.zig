const std = @import("std");

/// Helper to wrap protobuf bytes into a standard gRPC-Web HTTP response frame
/// Header [1 byte flag] + [4 bytes length] + Payload + Trailer [1 byte flag 0x80] + [4 bytes length] + "grpc-status: 0\r\ngrpc-message: OK\r\n"
pub fn wrapFrame(allocator: std.mem.Allocator, proto_payload: []const u8) ![]u8 {
    const proto_len: u32 = @intCast(proto_payload.len);
    const data_frame_len = 5 + proto_len;

    const trailer_text = "grpc-status: 0\r\ngrpc-message: OK\r\n";
    const trailer_text_len: u32 = @intCast(trailer_text.len);
    const trailer_frame_len = 5 + trailer_text_len;

    const total_len = data_frame_len + trailer_frame_len;
    const buf = try allocator.alloc(u8, total_len);

    // Data frame header (0x00 = uncompressed data)
    buf[0] = 0x00;
    buf[1] = @intCast((proto_len >> 24) & 0xFF);
    buf[2] = @intCast((proto_len >> 16) & 0xFF);
    buf[3] = @intCast((proto_len >> 8) & 0xFF);
    buf[4] = @intCast(proto_len & 0xFF);
    @memcpy(buf[5 .. 5 + proto_len], proto_payload);

    // Trailer frame header (0x80 = trailers)
    const t_offset = data_frame_len;
    buf[t_offset + 0] = 0x80;
    buf[t_offset + 1] = @intCast((trailer_text_len >> 24) & 0xFF);
    buf[t_offset + 2] = @intCast((trailer_text_len >> 16) & 0xFF);
    buf[t_offset + 3] = @intCast((trailer_text_len >> 8) & 0xFF);
    buf[t_offset + 4] = @intCast(trailer_text_len & 0xFF);
    @memcpy(buf[t_offset + 5 .. t_offset + 5 + trailer_text_len], trailer_text);

    return buf;
}

// Protobuf wire encoding utilities
pub fn writeVarint(buf: []u8, offset: *usize, val: u64) void {
    var v = val;
    while (v >= 0x80) {
        buf[offset.*] = @intCast((v & 0x7F) | 0x80);
        offset.* += 1;
        v >>= 7;
    }
    buf[offset.*] = @intCast(v & 0x7F);
    offset.* += 1;
}

pub fn writeStringField(buf: []u8, offset: *usize, field_num: u32, str: []const u8) void {
    const tag = (field_num << 3) | 2;
    writeVarint(buf, offset, tag);
    writeVarint(buf, offset, str.len);
    @memcpy(buf[offset.* .. offset.* + str.len], str);
    offset.* += str.len;
}

pub fn writeIntField(buf: []u8, offset: *usize, field_num: u32, val: u64) void {
    const tag = (field_num << 3) | 0;
    writeVarint(buf, offset, tag);
    writeVarint(buf, offset, val);
}

pub fn writeDoubleField(buf: []u8, offset: *usize, field_num: u32, val: f64) void {
    const tag = (field_num << 3) | 1;
    writeVarint(buf, offset, tag);
    const bits = @as(u64, @bitCast(val));
    std.mem.writeInt(u64, buf[offset.*..][0..8], bits, .little);
    offset.* += 8;
}

test "wrapFrame and decode" {
    const allocator = std.testing.allocator;
    const payload = "hello protobuf";
    const frame = try wrapFrame(allocator, payload);
    defer allocator.free(frame);

    try std.testing.expect(frame.len >= 5 + payload.len);
    try std.testing.expectEqual(@as(u8, 0x00), frame[0]);
}

test "writeStringField and writeIntField" {
    var buf: [64]u8 = undefined;
    var offset: usize = 0;
    writeStringField(&buf, &offset, 1, "test");
    writeIntField(&buf, &offset, 2, 42);
    try std.testing.expect(offset > 0);
}
