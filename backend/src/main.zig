const std = @import("std");
const httpz = @import("httpz");

// 5 Pre-defined names
const NAMES = [_][]const u8{
    "Andi",
    "Budi",
    "Citra",
    "Dewi",
    "Eko",
};

// In-Memory Static Assets Cache (Zero Disk I/O during requests)
var g_index_html: []const u8 = "";
var g_bridge_js: []const u8 = "";
var g_style_css: []const u8 = "";
var g_app_wasm: []const u8 = "";

// Pre-computed gRPC-Web Frames (Zero Heap Allocation during requests)
var g_grpc_responses: [5][]const u8 = undefined;

// Fast Atomic Counter for Round-Robin / Random distribution (Thread-Safe & Lock-Free)
var g_counter = std.atomic.Value(usize).init(0);

fn buildGrpcFrame(allocator: std.mem.Allocator, name: []const u8) ![]const u8 {
    const proto_len: u32 = @intCast(2 + name.len);
    const data_frame_len = 5 + proto_len;

    const trailer_text = "grpc-status: 0\r\ngrpc-message: OK\r\n";
    const trailer_text_len: u32 = @intCast(trailer_text.len);
    const trailer_frame_len = 5 + trailer_text_len;

    const total_len = data_frame_len + trailer_frame_len;
    const buf = try allocator.alloc(u8, total_len);

    // Data frame header
    buf[0] = 0x00; // uncompressed flag
    buf[1] = @intCast((proto_len >> 24) & 0xFF);
    buf[2] = @intCast((proto_len >> 16) & 0xFF);
    buf[3] = @intCast((proto_len >> 8) & 0xFF);
    buf[4] = @intCast(proto_len & 0xFF);

    // Protobuf payload
    buf[5] = 0x0A;
    buf[6] = @intCast(name.len);
    @memcpy(buf[7 .. 7 + name.len], name);

    // Trailer frame header
    const t_offset = data_frame_len;
    buf[t_offset + 0] = 0x80; // trailer flag for grpc-web
    buf[t_offset + 1] = @intCast((trailer_text_len >> 24) & 0xFF);
    buf[t_offset + 2] = @intCast((trailer_text_len >> 16) & 0xFF);
    buf[t_offset + 3] = @intCast((trailer_text_len >> 8) & 0xFF);
    buf[t_offset + 4] = @intCast(trailer_text_len & 0xFF);
    @memcpy(buf[t_offset + 5 .. t_offset + 5 + trailer_text_len], trailer_text);

    return buf;
}

fn readFileFromDisk(allocator: std.mem.Allocator, filename: []const u8) ![]u8 {
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

// Handlers (All pure in-memory zero-copy responses)
fn handleIndex(_: *httpz.Request, res: *httpz.Response) !void {
    res.header("Content-Type", "text/html; charset=utf-8");
    res.header("Access-Control-Allow-Origin", "*");
    res.body = g_index_html;
}

fn handleBridgeJs(_: *httpz.Request, res: *httpz.Response) !void {
    res.header("Content-Type", "application/javascript");
    res.header("Access-Control-Allow-Origin", "*");
    res.body = g_bridge_js;
}

fn handleStyleCss(_: *httpz.Request, res: *httpz.Response) !void {
    res.header("Content-Type", "text/css");
    res.header("Access-Control-Allow-Origin", "*");
    res.body = g_style_css;
}

fn handleAppWasm(_: *httpz.Request, res: *httpz.Response) !void {
    res.header("Content-Type", "application/wasm");
    res.header("Access-Control-Allow-Origin", "*");
    res.body = g_app_wasm;
}

fn handleGrpcGetRandomName(_: *httpz.Request, res: *httpz.Response) !void {
    const idx = g_counter.fetchAdd(1, .monotonic) % g_grpc_responses.len;
    const precomputed_frame = g_grpc_responses[idx];

    res.header("Content-Type", "application/grpc-web+proto");
    res.header("Access-Control-Allow-Origin", "*");
    res.header("Access-Control-Expose-Headers", "grpc-status, grpc-message");
    res.header("Cache-Control", "no-cache");
    res.body = precomputed_frame;
}

pub fn main() !void {
    const io = std.Io.Threaded.global_single_threaded.io();
    const allocator = std.heap.smp_allocator;

    // 1. Pre-load static assets into memory
    g_index_html = readFileFromDisk(allocator, "index.html") catch "";
    g_bridge_js = readFileFromDisk(allocator, "bridge.js") catch "";
    g_style_css = readFileFromDisk(allocator, "style.css") catch "";
    g_app_wasm = readFileFromDisk(allocator, "app.wasm") catch "";

    // 2. Pre-compute all 5 gRPC response frames in memory
    inline for (NAMES, 0..) |name, i| {
        g_grpc_responses[i] = try buildGrpcFrame(allocator, name);
    }

    // 3. Detect CPU Cores & configure maximum parallel workers
    const cpu_count = std.Thread.getCpuCount() catch 4;

    var server = try httpz.Server(void).init(io, allocator, .{
        .address = .localhost(8080),
        .workers = .{
            .count = @intCast(@min(cpu_count, 16)),
            .max_conn = 8192,
        },
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
    std.debug.print("🚀 Zig 0.16 + httpz High-Performance Server ({d} Workers)\n", .{cpu_count});
    std.debug.print("🌐 In-Memory Zero-Copy Routing at http://127.0.0.1:8080\n", .{});
    std.debug.print("📡 gRPC-Web Service: /hello.NameService/GetRandomName\n", .{});
    std.debug.print("======================================================\n\n", .{});

    try server.listen();
}
