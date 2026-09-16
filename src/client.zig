const std = @import("std");

/// JS bridge imported functions for WASM runtime
pub extern fn js_update_text(ptr: [*]const u8, len: usize) void;
pub extern fn js_send_grpc(endpoint_ptr: [*]const u8, endpoint_len: usize, body_ptr: [*]const u8, body_len: usize) void;
pub extern fn js_log(ptr: [*]const u8, len: usize) void;

/// Log message to browser console via JS bridge
pub fn log(msg: []const u8) void {
    js_log(msg.ptr, msg.len);
}

/// Update text content in browser DOM
pub fn updateText(text: []const u8) void {
    js_update_text(text.ptr, text.len);
}

/// Send gRPC-Web binary request over HTTP POST
pub fn sendGrpc(endpoint: []const u8, body: []const u8) void {
    js_send_grpc(endpoint.ptr, endpoint.len, body.ptr, body.len);
}

/// Decode standard gRPC-Web response frame:
/// Header: [1 byte flag] [4 bytes big-endian length] [payload]
pub fn decodeGrpcFrame(data: []const u8) ?[]const u8 {
    if (data.len < 5) return null;
    const msg_len = (@as(u32, data[1]) << 24) |
        (@as(u32, data[2]) << 16) |
        (@as(u32, data[3]) << 8) |
        @as(u32, data[4]);
    if (5 + msg_len > data.len) return null;
    return data[5 .. 5 + msg_len];
}

/// Decode protobuf string field (field_num = 1) from payload
pub fn decodeProtobufString(payload: []const u8) ?[]const u8 {
    if (payload.len >= 2 and payload[0] == 0x0a) {
        const str_len: usize = payload[1];
        if (2 + str_len <= payload.len) {
            return payload[2 .. 2 + str_len];
        }
    }
    return null;
}

/// Standard WASM heap memory allocator for JS <-> WASM boundary
pub fn wasmAlloc(len: usize) ?[*]u8 {
    const slice = std.heap.wasm_allocator.alloc(u8, len) catch return null;
    return slice.ptr;
}

pub fn wasmFree(ptr: [*]u8, len: usize) void {
    std.heap.wasm_allocator.free(ptr[0..len]);
}

test "decodeGrpcFrame valid" {
    const frame = [_]u8{ 0x00, 0x00, 0x00, 0x00, 0x04, 't', 'e', 's', 't' };
    const payload = decodeGrpcFrame(&frame);
    try std.testing.expect(payload != null);
    try std.testing.expectEqualStrings("test", payload.?);
}

test "decodeProtobufString field 1" {
    const payload = [_]u8{ 0x0a, 0x05, 'h', 'e', 'l', 'l', 'o' };
    const str = decodeProtobufString(&payload);
    try std.testing.expect(str != null);
    try std.testing.expectEqualStrings("hello", str.?);
}
