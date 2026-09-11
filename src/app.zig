const std = @import("std");
const httpz = @import("httpz");
const Database = @import("db.zig").Database;
const context_mod = @import("context.zig");
pub const Context = context_mod.Context;
pub const HandlerFn = context_mod.HandlerFn;

pub const AppConfig = struct {
    port: u16 = 8080,
    db_path: []const u8 = "data/app.db",
    max_workers: ?u16 = null,
};

// Global reference for static route dispatchers
var g_app_ptr: ?*App = null;

pub const App = struct {
    db: Database,
    server: httpz.Server(void),
    config: AppConfig,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, config: AppConfig) !App {
        // 1. Initialize SQLite Database with MANDATORY WAL Mode (Zero-Config)
        const db = try Database.init(config.db_path);

        // 2. Worker pool configuration
        const cpu_count = std.Thread.getCpuCount() catch 4;
        const worker_count: u16 = if (config.max_workers) |mw| mw else @intCast(@min(cpu_count, 16));

        const io = std.Io.Threaded.global_single_threaded.io();

        // 3. Initialize httpz server
        const server = try httpz.Server(void).init(io, allocator, .{
            .address = .localhost(config.port),
            .workers = .{
                .count = worker_count,
                .max_conn = 8192,
                .large_buffer_count = 1024,
                .large_buffer_size = 4096,
                .retain_allocated_bytes = 4096,
            },
            .request = .{
                .buffer_size = 8192, // 8 KB header buffer (supports all desktop browsers)
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

        var app = App{
            .db = db,
            .server = server,
            .config = config,
            .allocator = allocator,
        };

        return app;
    }

    /// Compile-time handler wrapper
    pub fn wrap(comptime handler: HandlerFn) fn (*httpz.Request, *httpz.Response) anyerror!void {
        const Wrapper = struct {
            fn handle(req: *httpz.Request, res: *httpz.Response) anyerror!void {
                if (g_app_ptr) |app| {
                    var ctx = Context{
                        .req = req,
                        .res = res,
                        .db = &app.db,
                        .arena = res.arena,
                    };
                    try handler(&ctx);
                }
            }
        };
        return Wrapper.handle;
    }

    /// Register a GET route
    pub fn get(self: *App, path: []const u8, comptime handler: HandlerFn) !void {
        var r = try self.server.router(.{});
        r.get(path, wrap(handler), .{});
        r.head(path, wrap(handler), .{});
    }

    /// Register a POST route
    pub fn post(self: *App, path: []const u8, comptime handler: HandlerFn) !void {
        var r = try self.server.router(.{});
        r.post(path, wrap(handler), .{});
    }

    /// Register a PUT route
    pub fn put(self: *App, path: []const u8, comptime handler: HandlerFn) !void {
        var r = try self.server.router(.{});
        r.put(path, wrap(handler), .{});
    }

    /// Register a DELETE route
    pub fn delete(self: *App, path: []const u8, comptime handler: HandlerFn) !void {
        var r = try self.server.router(.{});
        r.delete(path, wrap(handler), .{});
    }

    /// Start listening and serving requests
    pub fn listen(self: *App) !void {
        g_app_ptr = self;

        std.debug.print("\n======================================================\n", .{});
        std.debug.print("🚀 Mnemezigot Web Framework (Zig 0.16 + httpz + SQLite WAL)\n", .{});
        std.debug.print("📊 Database: {s} (WAL Mode Active)\n", .{self.config.db_path});
        std.debug.print("🌐 Listening at: http://127.0.0.1:{d}\n", .{self.config.port});
        std.debug.print("⚡ Outputs: [1] WASM (UI) | [2] JSON (REST) | [3] gRPC-Web\n", .{});
        std.debug.print("======================================================\n\n", .{});

        try self.server.listen();
    }

    pub fn deinit(self: *App) void {
        self.server.stop();
        self.server.deinit();
        self.db.deinit();
        g_app_ptr = null;
    }
};
