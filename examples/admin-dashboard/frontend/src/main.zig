const std = @import("std");

// Imports from JS bridge
extern fn js_update_text(ptr: [*]const u8, len: usize) void;
extern fn js_send_grpc(endpoint_ptr: [*]const u8, endpoint_len: usize, body_ptr: [*]const u8, body_len: usize) void;
extern fn js_log(ptr: [*]const u8, len: usize) void;

fn log(msg: []const u8) void {
    js_log(msg.ptr, msg.len);
}

// Memory allocator exports for WASM <-> JS memory transfer
export fn alloc(len: usize) ?[*]u8 {
    const slice = std.heap.wasm_allocator.alloc(u8, len) catch return null;
    return slice.ptr;
}

export fn free(ptr: [*]u8, len: usize) void {
    std.heap.wasm_allocator.free(ptr[0..len]);
}

// Called on web page load
export fn init() void {
    const initial_text = "Hello World";
    js_update_text(initial_text.ptr, initial_text.len);
    log("WASM Frontend initialized!");
}

// Called when the button is clicked in the UI
export fn on_button_click() void {
    log("Button clicked in WASM! Preparing gRPC-Web request...");

    const endpoint = "/hello.NameService/GetRandomName";

    // gRPC-Web frame header:
    // [0x00] = compression flag (0 = uncompressed)
    // [0x00, 0x00, 0x00, 0x00] = big-endian payload length (0 bytes for empty RandomNameRequest)
    const grpc_frame = [_]u8{ 0x00, 0x00, 0x00, 0x00, 0x00 };

    js_send_grpc(endpoint.ptr, endpoint.len, &grpc_frame, grpc_frame.len);
}

// Called by JS bridge when gRPC-Web response bytes arrive
export fn on_grpc_response(ptr: [*]const u8, len: usize) void {
    if (len < 5) {
        log("Invalid gRPC response: frame too short");
        return;
    }

    const data = ptr[0..len];

    // Parse gRPC frame header
    const flag = data[0];
    const msg_len = (@as(u32, data[1]) << 24) |
        (@as(u32, data[2]) << 16) |
        (@as(u32, data[3]) << 8) |
        @as(u32, data[4]);

    if (flag != 0x00) {
        log("Unexpected gRPC frame flag");
        return;
    }

    if (5 + msg_len > len) {
        log("Incomplete gRPC frame received");
        return;
    }

    const payload = data[5 .. 5 + msg_len];

    // Decode Protobuf payload for RandomNameResponse:
    // message RandomNameResponse { string name = 1; }
    // Field 1, wire type 2 (length-delimited): tag = (1 << 3) | 2 = 0x0A (10)
    var name_slice: []const u8 = "Unknown";

    if (payload.len >= 2 and payload[0] == 0x0a) {
        const str_len: usize = payload[1];
        if (2 + str_len <= payload.len) {
            name_slice = payload[2 .. 2 + str_len];
        }
    }

    // Format greeting: "Hello <Name>"
    var buffer: [128]u8 = undefined;
    const formatted = std.fmt.bufPrint(&buffer, "Hello {s}", .{name_slice}) catch "Hello World";

    // Update DOM via JS bridge
    js_update_text(formatted.ptr, formatted.len);
    log("DOM updated with gRPC response!");
}
