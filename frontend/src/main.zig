const std = @import("std");

// Imports from JS bridge
extern fn js_update_user_card(
    name_ptr: [*]const u8,
    name_len: usize,
    job_ptr: [*]const u8,
    job_len: usize,
    city_ptr: [*]const u8,
    city_len: usize,
    email_ptr: [*]const u8,
    email_len: usize,
    phone_ptr: [*]const u8,
    phone_len: usize,
    addr_ptr: [*]const u8,
    addr_len: usize,
    user_id: i64,
    total_users: i64,
    query_time_ms: f64,
) void;

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
    log("WASM Frontend initialized!");
}

// Called when the button is clicked in the UI
export fn on_button_click() void {
    log("Button clicked! Mengirim request gRPC-Web ke server SQLite...");

    const endpoint = "/hello.NameService/GetRandomUser";
    const grpc_frame = [_]u8{ 0x00, 0x00, 0x00, 0x00, 0x00 };

    js_send_grpc(endpoint.ptr, endpoint.len, &grpc_frame, grpc_frame.len);
}

// Helper to read Varint from protobuf
fn readVarint(data: []const u8, offset: *usize) u64 {
    var result: u64 = 0;
    var shift: u6 = 0;
    while (offset.* < data.len) {
        const byte = data[offset.*];
        offset.* += 1;
        result |= (@as(u64, byte & 0x7F) << shift);
        if ((byte & 0x80) == 0) break;
        shift += 7;
    }
    return result;
}

// Called by JS bridge when gRPC-Web response bytes arrive
export fn on_grpc_response(ptr: [*]const u8, len: usize) void {
    if (len < 5) {
        log("Invalid gRPC response: frame too short");
        return;
    }

    const data = ptr[0..len];
    const flag = data[0];
    const msg_len = (@as(u32, data[1]) << 24) |
        (@as(u32, data[2]) << 16) |
        (@as(u32, data[3]) << 8) |
        @as(u32, data[4]);

    if (flag != 0x00 or (5 + msg_len > len)) {
        log("Invalid gRPC frame structure");
        return;
    }

    const payload = data[5 .. 5 + msg_len];

    // Decode Protobuf fields
    var user_id: i64 = 0;
    var name_str: []const u8 = "Budi Santoso";
    var email_str: []const u8 = "";
    var phone_str: []const u8 = "";
    var addr_str: []const u8 = "";
    var city_str: []const u8 = "";
    var job_str: []const u8 = "";
    var total_users: i64 = 0;
    var query_time_ms: f64 = 0.0;

    var offset: usize = 0;
    while (offset < payload.len) {
        const tag = readVarint(payload, &offset);
        const field_num = tag >> 3;
        const wire_type = tag & 0x07;

        switch (wire_type) {
            0 => { // Varint
                const val = readVarint(payload, &offset);
                if (field_num == 1) user_id = @intCast(val);
                if (field_num == 8) total_users = @intCast(val);
            },
            1 => { // 64-bit float
                if (offset + 8 <= payload.len) {
                    const bits = std.mem.readInt(u64, payload[offset..][0..8], .little);
                    offset += 8;
                    if (field_num == 9) query_time_ms = @bitCast(bits);
                }
            },
            2 => { // Length-delimited string
                const str_len: usize = @intCast(readVarint(payload, &offset));
                if (offset + str_len <= payload.len) {
                    const str_bytes = payload[offset .. offset + str_len];
                    offset += str_len;

                    switch (field_num) {
                        2 => name_str = str_bytes,
                        3 => email_str = str_bytes,
                        4 => phone_str = str_bytes,
                        5 => addr_str = str_bytes,
                        6 => city_str = str_bytes,
                        7 => job_str = str_bytes,
                        else => {},
                    }
                }
            },
            else => break,
        }
    }

    // Pass decoded data to JS bridge to update the User Card DOM
    js_update_user_card(
        name_str.ptr,
        name_str.len,
        job_str.ptr,
        job_str.len,
        city_str.ptr,
        city_str.len,
        email_str.ptr,
        email_str.len,
        phone_str.ptr,
        phone_str.len,
        addr_str.ptr,
        addr_str.len,
        user_id,
        total_users,
        query_time_ms,
    );

    log("User Card updated with SQLite data!");
}
