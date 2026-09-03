const std = @import("std");
const httpz = @import("httpz");

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

fn readFile(allocator: std.mem.Allocator, filename: []const u8) ![]u8 {
    const cwd = std.Io.Dir.cwd();
    const io = std.Io.Threaded.global_single_threaded.io();

    const candidates = [_][]const u8{ "zig-out/public", "public", "static", "frontend/static", "." };
    var path_buf: [256]u8 = undefined;

    for (candidates) |dir_prefix| {
        const full_path = if (std.mem.eql(u8, dir_prefix, "."))
            filename
        else
            std.fmt.bufPrint(&path_buf, "{s}/{s}", .{ dir_prefix, filename }) catch continue;

        if (cwd.openFile(io, full_path, .{})) |file| {
            defer file.close(io);
            const size = try file.length(io);
            const buf = try allocator.alloc(u8, @intCast(size));
            errdefer allocator.free(buf);

            _ = try file.readPositionalAll(io, buf, 0);
            return buf;
        } else |_| {}
    }

    return error.FileNotFound;
}

fn serveStatic(res: *httpz.Response, filename: []const u8, content_type: []const u8) !void {
    const content = readFile(res.arena, filename) catch {
        res.status = 404;
        res.body = "Not Found";
        return;
    };
    res.header("Content-Type", content_type);
    res.header("Access-Control-Allow-Origin", "*");
    res.header("Cache-Control", "no-cache");
    res.body = content;
}

fn handleIndex(_: *httpz.Request, res: *httpz.Response) !void {
    try serveStatic(res, "index.html", "text/html; charset=utf-8");
}

fn handleBridgeJs(_: *httpz.Request, res: *httpz.Response) !void {
    try serveStatic(res, "bridge.js", "application/javascript");
}

fn handleStyleCss(_: *httpz.Request, res: *httpz.Response) !void {
    try serveStatic(res, "style.css", "text/css");
}

fn handleAppWasm(_: *httpz.Request, res: *httpz.Response) !void {
    try serveStatic(res, "app.wasm", "application/wasm");
}

fn handleGrpcGetRandomName(_: *httpz.Request, res: *httpz.Response) !void {
    const selected_name = getRandomName();
    std.debug.print("🎲 [httpz] Picked random name: '{s}'\n", .{selected_name});

    // 1. Encode Protobuf payload:
    // message RandomNameResponse { string name = 1; }
    // Tag: 0x0A, Len: name.len, Value: name bytes
    const proto_len: u32 = @intCast(2 + selected_name.len);

    // 2. Encode gRPC-Web data frame (5 bytes header + proto_buf)
    const data_frame_len = 5 + proto_len;

    // 3. Encode gRPC-Web trailer frame
    const trailer_text = "grpc-status: 0\r\ngrpc-message: OK\r\n";
    const trailer_text_len: u32 = @intCast(trailer_text.len);
    const trailer_frame_len = 5 + trailer_text_len;

    const total_body_len = data_frame_len + trailer_frame_len;
    const body_buf = try res.arena.alloc(u8, total_body_len);

    // Data frame header
    body_buf[0] = 0x00; // uncompressed flag
    body_buf[1] = @intCast((proto_len >> 24) & 0xFF);
    body_buf[2] = @intCast((proto_len >> 16) & 0xFF);
    body_buf[3] = @intCast((proto_len >> 8) & 0xFF);
    body_buf[4] = @intCast(proto_len & 0xFF);

    // Protobuf payload
    body_buf[5] = 0x0A;
    body_buf[6] = @intCast(selected_name.len);
    @memcpy(body_buf[7 .. 7 + selected_name.len], selected_name);

    // Trailer frame header
    const t_offset = data_frame_len;
    body_buf[t_offset + 0] = 0x80; // trailer flag for grpc-web
    body_buf[t_offset + 1] = @intCast((trailer_text_len >> 24) & 0xFF);
    body_buf[t_offset + 2] = @intCast((trailer_text_len >> 16) & 0xFF);
    body_buf[t_offset + 3] = @intCast((trailer_text_len >> 8) & 0xFF);
    body_buf[t_offset + 4] = @intCast(trailer_text_len & 0xFF);
    @memcpy(body_buf[t_offset + 5 .. t_offset + 5 + trailer_text_len], trailer_text);

    res.header("Content-Type", "application/grpc-web+proto");
    res.header("Access-Control-Allow-Origin", "*");
    res.header("Access-Control-Expose-Headers", "grpc-status, grpc-message");
    res.header("Cache-Control", "no-cache");
    res.body = body_buf;

    std.debug.print("✅ [httpz] Sent gRPC-Web response ({d} bytes)\n", .{total_body_len});
}

pub fn main() !void {
    const io = std.Io.Threaded.global_single_threaded.io();
    const allocator = std.heap.smp_allocator;

    var server = try httpz.Server(void).init(io, allocator, .{
        .address = .localhost(8080),
    }, {});
    defer server.deinit();
    defer server.stop();

    var router = try server.router(.{});

    // Static Assets (GET & HEAD)
    router.get("/", handleIndex, .{});
    router.get("/index.html", handleIndex, .{});
    router.get("/bridge.js", handleBridgeJs, .{});
    router.get("/style.css", handleStyleCss, .{});
    router.get("/app.wasm", handleAppWasm, .{});

    router.head("/", handleIndex, .{});
    router.head("/index.html", handleIndex, .{});
    router.head("/bridge.js", handleBridgeJs, .{});
    router.head("/style.css", handleStyleCss, .{});
    router.head("/app.wasm", handleAppWasm, .{});

    // gRPC-Web RPC Route
    router.post("/hello.NameService/GetRandomName", handleGrpcGetRandomName, .{});

    std.debug.print("\n======================================================\n", .{});
    std.debug.print("🚀 Zig 0.16 + httpz Production Server at http://127.0.0.1:8080\n", .{});
    std.debug.print("📡 gRPC-Web Service: /hello.NameService/GetRandomName\n", .{});
    std.debug.print("======================================================\n\n", .{});

    try server.listen();
}
