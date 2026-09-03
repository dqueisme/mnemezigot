const std = @import("std");
const httpz = @import("httpz");

const c = @cImport({
    @cInclude("sqlite3.h");
});

// In-Memory Static Assets Cache
var g_index_html: []const u8 = "";
var g_bridge_js: []const u8 = "";
var g_style_css: []const u8 = "";
var g_app_wasm: []const u8 = "";

// SQLite Database state
var g_db: ?*c.sqlite3 = null;
var g_stmt_get_user: ?*c.sqlite3_stmt = null;
var g_total_users: i64 = 0;
var g_prng: std.Random.DefaultPrng = undefined;
var g_mutex: std.atomic.Mutex = .unlocked;

fn acquireLock() void {
    while (!g_mutex.tryLock()) {
        std.atomic.spinLoopHint();
    }
}

fn releaseLock() void {
    g_mutex.unlock();
}

// Protobuf helper functions
fn writeVarint(buf: []u8, offset: *usize, val: u64) void {
    var v = val;
    while (v >= 0x80) {
        buf[offset.*] = @intCast((v & 0x7F) | 0x80);
        offset.* += 1;
        v >>= 7;
    }
    buf[offset.*] = @intCast(v & 0x7F);
    offset.* += 1;
}

fn writeStringField(buf: []u8, offset: *usize, field_num: u32, str: []const u8) void {
    const tag = (field_num << 3) | 2;
    writeVarint(buf, offset, tag);
    writeVarint(buf, offset, str.len);
    @memcpy(buf[offset.* .. offset.* + str.len], str);
    offset.* += str.len;
}

fn writeIntField(buf: []u8, offset: *usize, field_num: u32, val: u64) void {
    const tag = (field_num << 3) | 0;
    writeVarint(buf, offset, tag);
    writeVarint(buf, offset, val);
}

fn writeDoubleField(buf: []u8, offset: *usize, field_num: u32, val: f64) void {
    const tag = (field_num << 3) | 1;
    writeVarint(buf, offset, tag);
    const bits = @as(u64, @bitCast(val));
    std.mem.writeInt(u64, buf[offset.*..][0..8], bits, .little);
    offset.* += 8;
}

fn initDatabase(allocator: std.mem.Allocator) !void {
    const cwd = std.Io.Dir.cwd();
    const io = std.Io.Threaded.global_single_threaded.io();
    cwd.createDir(io, "data", .default_dir) catch {};
    const db_path = "data/users.db";

    if (c.sqlite3_open_v2(db_path, &g_db, c.SQLITE_OPEN_READWRITE | c.SQLITE_OPEN_CREATE, null) != c.SQLITE_OK) {
        std.debug.print("❌ Failed to open SQLite database: {s}\n", .{c.sqlite3_errmsg(g_db)});
        return error.SqliteOpenFailed;
    }

    // High performance PRAGMA tuning
    _ = c.sqlite3_exec(g_db, "PRAGMA journal_mode = WAL;", null, null, null);
    _ = c.sqlite3_exec(g_db, "PRAGMA synchronous = NORMAL;", null, null, null);
    _ = c.sqlite3_exec(g_db, "PRAGMA mmap_size = 30000000000;", null, null, null);
    _ = c.sqlite3_exec(g_db, "PRAGMA cache_size = -64000;", null, null, null);
    _ = c.sqlite3_exec(g_db, "PRAGMA busy_timeout = 5000;", null, null, null);

    // Create table if not exists
    const create_sql =
        \\CREATE TABLE IF NOT EXISTS users (
        \\    id INTEGER PRIMARY KEY AUTOINCREMENT,
        \\    name TEXT NOT NULL,
        \\    email TEXT NOT NULL,
        \\    phone TEXT NOT NULL,
        \\    address TEXT NOT NULL,
        \\    city TEXT NOT NULL,
        \\    job_title TEXT NOT NULL
        \\);
    ;
    _ = c.sqlite3_exec(g_db, create_sql, null, null, null);

    // Get row count
    var count_stmt: ?*c.sqlite3_stmt = null;
    if (c.sqlite3_prepare_v2(g_db, "SELECT COUNT(*) FROM users;", -1, &count_stmt, null) == c.SQLITE_OK) {
        if (c.sqlite3_step(count_stmt) == c.SQLITE_ROW) {
            g_total_users = c.sqlite3_column_int64(count_stmt, 0);
        }
        _ = c.sqlite3_finalize(count_stmt);
    }

    std.debug.print("📦 [SQLite] Database loaded. Total users: {d}\n", .{g_total_users});

    if (g_total_users == 0) {
        std.debug.print("⚠️ Database kosong. Silakan jalankan seeding data.\n", .{});
        g_total_users = 1; // safety fallback
    }

    // Prepare fast lookup statement: SELECT by primary key
    const lookup_sql = "SELECT id, name, email, phone, address, city, job_title FROM users WHERE id = ? LIMIT 1;";
    if (c.sqlite3_prepare_v2(g_db, lookup_sql, -1, &g_stmt_get_user, null) != c.SQLITE_OK) {
        std.debug.print("❌ Failed to prepare lookup query: {s}\n", .{c.sqlite3_errmsg(g_db)});
        return error.SqlitePrepareFailed;
    }

    _ = allocator;
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

// Handlers for Static Assets
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

fn getNowNs() u64 {
    var ts: std.posix.timespec = undefined;
    _ = std.posix.system.clock_gettime(.MONOTONIC, &ts);
    return @as(u64, @intCast(ts.sec)) * 1_000_000_000 + @as(u64, @intCast(ts.nsec));
}

// Handler for gRPC-Web: /hello.NameService/GetRandomUser
fn handleGrpcGetRandomUser(_: *httpz.Request, res: *httpz.Response) !void {
    var user_id: i64 = 1;
    var name_str: []const u8 = "Budi Santoso";
    var email_str: []const u8 = "budi.santoso@example.com";
    var phone_str: []const u8 = "+62 812-1234-5678";
    var addr_str: []const u8 = "Jl. Sudirman No. 1";
    var city_str: []const u8 = "Jakarta";
    var job_str: []const u8 = "Software Engineer";
    var query_duration_ms: f64 = 0.0;

    if (g_total_users > 0 and g_stmt_get_user != null) {
        acquireLock();
        defer releaseLock();

        const rand_target: u64 = if (g_total_users > 1)
            (g_prng.random().uintLessThan(u64, @intCast(g_total_users))) + 1
        else
            1;

        const start_ns = getNowNs();

        _ = c.sqlite3_reset(g_stmt_get_user);
        _ = c.sqlite3_bind_int64(g_stmt_get_user, 1, @intCast(rand_target));

        if (c.sqlite3_step(g_stmt_get_user) == c.SQLITE_ROW) {
            user_id = c.sqlite3_column_int64(g_stmt_get_user, 0);

            if (c.sqlite3_column_text(g_stmt_get_user, 1)) |p| {
                name_str = std.mem.span(@as([*:0]const u8, @ptrCast(p)));
            }
            if (c.sqlite3_column_text(g_stmt_get_user, 2)) |p| {
                email_str = std.mem.span(@as([*:0]const u8, @ptrCast(p)));
            }
            if (c.sqlite3_column_text(g_stmt_get_user, 3)) |p| {
                phone_str = std.mem.span(@as([*:0]const u8, @ptrCast(p)));
            }
            if (c.sqlite3_column_text(g_stmt_get_user, 4)) |p| {
                addr_str = std.mem.span(@as([*:0]const u8, @ptrCast(p)));
            }
            if (c.sqlite3_column_text(g_stmt_get_user, 5)) |p| {
                city_str = std.mem.span(@as([*:0]const u8, @ptrCast(p)));
            }
            if (c.sqlite3_column_text(g_stmt_get_user, 6)) |p| {
                job_str = std.mem.span(@as([*:0]const u8, @ptrCast(p)));
            }
        }

        const end_ns = getNowNs();
        query_duration_ms = @as(f64, @floatFromInt(end_ns - start_ns)) / 1_000_000.0;
    }

    // Encode Protobuf RandomUserResponse:
    // field 1: int64 id
    // field 2: string name
    // field 3: string email
    // field 4: string phone
    // field 5: string address
    // field 6: string city
    // field 7: string job_title
    // field 8: int64 total_users_in_db
    // field 9: double query_time_ms
    var proto_buf: [1024]u8 = undefined;
    var p_offset: usize = 0;

    writeIntField(&proto_buf, &p_offset, 1, @intCast(user_id));
    writeStringField(&proto_buf, &p_offset, 2, name_str);
    writeStringField(&proto_buf, &p_offset, 3, email_str);
    writeStringField(&proto_buf, &p_offset, 4, phone_str);
    writeStringField(&proto_buf, &p_offset, 5, addr_str);
    writeStringField(&proto_buf, &p_offset, 6, city_str);
    writeStringField(&proto_buf, &p_offset, 7, job_str);
    writeIntField(&proto_buf, &p_offset, 8, @intCast(g_total_users));
    writeDoubleField(&proto_buf, &p_offset, 9, query_duration_ms);

    const proto_len: u32 = @intCast(p_offset);

    // Frame headers for gRPC-Web
    const data_frame_len = 5 + proto_len;
    const trailer_text = "grpc-status: 0\r\ngrpc-message: OK\r\n";
    const trailer_text_len: u32 = @intCast(trailer_text.len);
    const trailer_frame_len = 5 + trailer_text_len;

    const total_body_len = data_frame_len + trailer_frame_len;
    const body_buf = try res.arena.alloc(u8, total_body_len);

    // Data frame header
    body_buf[0] = 0x00; // uncompressed
    body_buf[1] = @intCast((proto_len >> 24) & 0xFF);
    body_buf[2] = @intCast((proto_len >> 16) & 0xFF);
    body_buf[3] = @intCast((proto_len >> 8) & 0xFF);
    body_buf[4] = @intCast(proto_len & 0xFF);
    @memcpy(body_buf[5 .. 5 + proto_len], proto_buf[0..p_offset]);

    // Trailer frame header
    const t_offset = data_frame_len;
    body_buf[t_offset + 0] = 0x80; // trailer flag
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
}

pub fn main() !void {
    const io = std.Io.Threaded.global_single_threaded.io();
    const allocator = std.heap.smp_allocator;

    g_prng = std.Random.DefaultPrng.init(@truncate(getNowNs()));

    // 1. Initialize embedded SQLite
    try initDatabase(allocator);

    // 2. Pre-load static assets into memory
    g_index_html = readFileFromDisk(allocator, "index.html") catch "";
    g_bridge_js = readFileFromDisk(allocator, "bridge.js") catch "";
    g_style_css = readFileFromDisk(allocator, "style.css") catch "";
    g_app_wasm = readFileFromDisk(allocator, "app.wasm") catch "";

    // 3. Worker Pool Architecture
    const cpu_count = std.Thread.getCpuCount() catch 4;

    var server = try httpz.Server(void).init(io, allocator, .{
        .address = .localhost(8080),
        .workers = .{
            .count = @intCast(@min(cpu_count, 16)),
            .max_conn = 8192,
            .large_buffer_count = 1024,
            .large_buffer_size = 4096,
            .retain_allocated_bytes = 4096,
        },
        .request = .{
            .buffer_size = 8192,
            .max_header_count = 64,
            .max_form_count = 0,
            .max_multiform_count = 0,
        },
        .response = .{
            .max_header_count = 32,
        },
        .timeout = .{
            .request = 5,
            .keepalive = 10,
        },
    }, {});
    defer server.deinit();
    defer server.stop();

    var router = try server.router(.{});

    // Static Assets
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

    // gRPC-Web Service RPC routes
    router.post("/hello.NameService/GetRandomUser", handleGrpcGetRandomUser, .{});
    router.post("/hello.NameService/GetRandomName", handleGrpcGetRandomUser, .{});

    std.debug.print("\n======================================================\n", .{});
    std.debug.print("🚀 Zig 0.16 + httpz + Embedded SQLite 3.46\n", .{});
    std.debug.print("📊 Database: data/users.db ({d} baris data)\n", .{g_total_users});
    std.debug.print("🌐 Running at: http://127.0.0.1:8080\n", .{});
    std.debug.print("📡 gRPC-Web Service: /hello.NameService/GetRandomUser\n", .{});
    std.debug.print("======================================================\n\n", .{});

    try server.listen();
}
