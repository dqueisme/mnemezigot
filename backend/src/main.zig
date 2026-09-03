const std = @import("std");
const linux = std.os.linux;

const NAMES = [_][]const u8{
    "Andi",
    "Budi",
    "Citra",
    "Dewi",
    "Eko",
};

var prng = std.Random.DefaultPrng.init(0xCAFEBABE);

fn getRandomName() []const u8 {
    const rand = prng.random();
    const idx = rand.uintLessThan(usize, NAMES.len);
    return NAMES[idx];
}

fn readFile(allocator: std.mem.Allocator, rel_path: []const u8) ![]u8 {
    const cwd = std.Io.Dir.cwd();
    const io = std.Io.Threaded.global_single_threaded.io();
    const file = try cwd.openFile(io, rel_path, .{});
    defer file.close(io);

    const size = try file.length(io);
    const buf = try allocator.alloc(u8, @intCast(size));
    errdefer allocator.free(buf);

    _ = try file.readPositionalAll(io, buf, 0);
    return buf;
}

pub fn main() !void {
    const allocator = std.heap.smp_allocator;

    const server_fd_rc = linux.socket(linux.AF.INET, linux.SOCK.STREAM | linux.SOCK.CLOEXEC, 0);
    if (@as(isize, @bitCast(server_fd_rc)) < 0) {
        std.debug.print("Failed to create socket\n", .{});
        return;
    }
    const server_fd: i32 = @intCast(server_fd_rc);
    defer _ = linux.close(server_fd);

    const reuse: i32 = 1;
    _ = linux.setsockopt(server_fd, linux.SOL.SOCKET, linux.SO.REUSEADDR, @ptrCast(&reuse), @sizeOf(i32));

    var addr = linux.sockaddr.in{
        .port = std.mem.nativeToBig(u16, 8080),
        .addr = 0, // 0.0.0.0 (INADDR_ANY)
    };

    const bind_rc = linux.bind(server_fd, @ptrCast(&addr), @sizeOf(linux.sockaddr.in));
    if (@as(isize, @bitCast(bind_rc)) < 0) {
        std.debug.print("Failed to bind to port 8080\n", .{});
        return;
    }

    const listen_rc = linux.listen(server_fd, 128);
    if (@as(isize, @bitCast(listen_rc)) < 0) {
        std.debug.print("Failed to listen on socket\n", .{});
        return;
    }

    std.debug.print("\n======================================================\n", .{});
    std.debug.print("🚀 Zig 0.16 Backend Server running at http://127.0.0.1:8080\n", .{});
    std.debug.print("📡 gRPC-Web Service: /hello.NameService/GetRandomName\n", .{});
    std.debug.print("======================================================\n\n", .{});

    while (true) {
        const client_fd_rc = linux.accept4(server_fd, null, null, linux.SOCK.CLOEXEC);
        if (@as(isize, @bitCast(client_fd_rc)) < 0) continue;
        const client_fd: i32 = @intCast(client_fd_rc);

        handleConnection(allocator, client_fd) catch |err| {
            std.debug.print("Error handling connection: {s}\n", .{@errorName(err)});
        };
    }
}

fn writeAll(fd: i32, data: []const u8) !void {
    var total_written: usize = 0;
    while (total_written < data.len) {
        const rc = linux.sendto(fd, data.ptr + total_written, data.len - total_written, linux.MSG.NOSIGNAL, null, 0);
        const signed_rc: isize = @bitCast(rc);
        if (signed_rc <= 0) return error.WriteFailed;
        total_written += @intCast(signed_rc);
    }
}

fn handleConnection(allocator: std.mem.Allocator, client_fd: i32) !void {
    defer _ = linux.close(client_fd);

    var buffer: [4096]u8 = undefined;
    const rc = linux.read(client_fd, &buffer, buffer.len);
    const signed_rc: isize = @bitCast(rc);
    if (signed_rc <= 0) return;

    const bytes_read: usize = @intCast(signed_rc);
    const request = buffer[0..bytes_read];

    // Find request line
    var line_iter = std.mem.splitSequence(u8, request, "\r\n");
    const req_line = line_iter.next() orelse return;

    var part_iter = std.mem.splitScalar(u8, req_line, ' ');
    const method = part_iter.next() orelse return;
    const raw_path = part_iter.next() orelse return;

    // Strip query string if any
    var path_split = std.mem.splitScalar(u8, raw_path, '?');
    const path = path_split.next() orelse "/";

    std.debug.print("[HTTP] {s} {s}\n", .{ method, path });

    // Handle CORS Preflight
    if (std.mem.eql(u8, method, "OPTIONS")) {
        const cors_response =
            "HTTP/1.1 204 No Content\r\n" ++
            "Access-Control-Allow-Origin: *\r\n" ++
            "Access-Control-Allow-Methods: POST, GET, OPTIONS\r\n" ++
            "Access-Control-Allow-Headers: *\r\n" ++
            "Access-Control-Expose-Headers: grpc-status, grpc-message\r\n" ++
            "Content-Length: 0\r\n" ++
            "\r\n";
        try writeAll(client_fd, cors_response);
        return;
    }

    // Handle gRPC-Web Endpoint
    if (std.mem.eql(u8, path, "/hello.NameService/GetRandomName")) {
        try handleGrpcGetRandomName(client_fd);
        return;
    }

    const is_head = std.mem.eql(u8, method, "HEAD");

    // Handle Static File Serving
    if (std.mem.eql(u8, path, "/") or std.mem.eql(u8, path, "/index.html")) {
        try serveStaticFile(allocator, client_fd, "frontend/static/index.html", "text/html; charset=utf-8", is_head);
    } else if (std.mem.eql(u8, path, "/bridge.js")) {
        try serveStaticFile(allocator, client_fd, "frontend/static/bridge.js", "application/javascript", is_head);
    } else if (std.mem.eql(u8, path, "/style.css")) {
        try serveStaticFile(allocator, client_fd, "frontend/static/style.css", "text/css", is_head);
    } else if (std.mem.eql(u8, path, "/app.wasm")) {
        try serveStaticFile(allocator, client_fd, "frontend/static/app.wasm", "application/wasm", is_head);
    } else {
        const not_found =
            "HTTP/1.1 404 Not Found\r\n" ++
            "Content-Length: 9\r\n" ++
            "Content-Type: text/plain\r\n" ++
            "\r\n" ++
            "Not Found";
        try writeAll(client_fd, not_found);
    }
}

fn serveStaticFile(
    allocator: std.mem.Allocator,
    client_fd: i32,
    file_path: []const u8,
    content_type: []const u8,
    is_head: bool,
) !void {
    const content = readFile(allocator, file_path) catch {
        const not_found =
            "HTTP/1.1 404 Not Found\r\n" ++
            "Content-Length: 9\r\n" ++
            "Content-Type: text/plain\r\n" ++
            "\r\n" ++
            "Not Found";
        try writeAll(client_fd, not_found);
        return;
    };
    defer allocator.free(content);

    var header_buf: [512]u8 = undefined;
    const header = try std.fmt.bufPrint(
        &header_buf,
        "HTTP/1.1 200 OK\r\n" ++
            "Content-Type: {s}\r\n" ++
            "Content-Length: {d}\r\n" ++
            "Access-Control-Allow-Origin: *\r\n" ++
            "Cache-Control: no-cache\r\n" ++
            "\r\n",
        .{ content_type, content.len },
    );
    try writeAll(client_fd, header);
    if (!is_head) {
        try writeAll(client_fd, content);
    }
}

fn handleGrpcGetRandomName(client_fd: i32) !void {
    const selected_name = getRandomName();
    std.debug.print("🎲 Picked random name: '{s}'\n", .{selected_name});

    // 1. Encode Protobuf payload:
    // message RandomNameResponse { string name = 1; }
    // Tag: (1 << 3) | 2 = 0x0A
    // Length: selected_name.len
    // Value: selected_name bytes
    var proto_buf: [64]u8 = undefined;
    proto_buf[0] = 0x0A; // tag: field 1, wire_type 2
    proto_buf[1] = @intCast(selected_name.len);
    @memcpy(proto_buf[2 .. 2 + selected_name.len], selected_name);
    const proto_len: u32 = @intCast(2 + selected_name.len);

    // 2. Encode gRPC-Web data frame (5 bytes header + proto_buf)
    var grpc_data_frame: [128]u8 = undefined;
    grpc_data_frame[0] = 0x00; // uncompressed flag
    grpc_data_frame[1] = @intCast((proto_len >> 24) & 0xFF);
    grpc_data_frame[2] = @intCast((proto_len >> 16) & 0xFF);
    grpc_data_frame[3] = @intCast((proto_len >> 8) & 0xFF);
    grpc_data_frame[4] = @intCast(proto_len & 0xFF);
    @memcpy(grpc_data_frame[5 .. 5 + proto_len], proto_buf[0..proto_len]);
    const data_frame_total_len: usize = 5 + proto_len;

    // 3. Encode gRPC-Web trailer frame
    // In gRPC-Web, trailers are sent as a final frame with flag 0x80 (128)
    const trailer_text = "grpc-status: 0\r\ngrpc-message: OK\r\n";
    const trailer_text_len: u32 = @intCast(trailer_text.len);

    var grpc_trailer_frame: [128]u8 = undefined;
    grpc_trailer_frame[0] = 0x80; // trailer flag for grpc-web
    grpc_trailer_frame[1] = @intCast((trailer_text_len >> 24) & 0xFF);
    grpc_trailer_frame[2] = @intCast((trailer_text_len >> 16) & 0xFF);
    grpc_trailer_frame[3] = @intCast((trailer_text_len >> 8) & 0xFF);
    grpc_trailer_frame[4] = @intCast(trailer_text_len & 0xFF);
    @memcpy(grpc_trailer_frame[5 .. 5 + trailer_text_len], trailer_text);
    const trailer_frame_total_len: usize = 5 + trailer_text_len;

    const total_body_len = data_frame_total_len + trailer_frame_total_len;

    // 4. Send HTTP Response Header
    var header_buf: [512]u8 = undefined;
    const header = try std.fmt.bufPrint(
        &header_buf,
        "HTTP/1.1 200 OK\r\n" ++
            "Content-Type: application/grpc-web+proto\r\n" ++
            "Content-Length: {d}\r\n" ++
            "Access-Control-Allow-Origin: *\r\n" ++
            "Access-Control-Expose-Headers: grpc-status, grpc-message\r\n" ++
            "\r\n",
        .{total_body_len},
    );

    try writeAll(client_fd, header);
    try writeAll(client_fd, grpc_data_frame[0..data_frame_total_len]);
    try writeAll(client_fd, grpc_trailer_frame[0..trailer_frame_total_len]);

    std.debug.print("✅ Sent gRPC-Web response ({d} bytes)\n", .{total_body_len});
}
