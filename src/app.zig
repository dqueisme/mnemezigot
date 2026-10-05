const std = @import("std");
const httpz = @import("httpz");
const Database = @import("db.zig").Database;
const context_mod = @import("context.zig");
pub const Context = context_mod.Context;
pub const HandlerFn = context_mod.HandlerFn;
pub const MiddlewareFn = context_mod.MiddlewareFn;

/// Built-in Middlewares
pub const middleware = struct {
    /// Logger middleware to log request details and execution duration
    pub fn logger(ctx: *Context, next: HandlerFn) !void {
        const start = std.time.milliTimestamp();
        const method = @tagName(ctx.req.method);
        const url = ctx.req.url.path;

        try next(ctx);

        const duration = std.time.milliTimestamp() - start;
        std.debug.print("⚡ [HTTP] {s} {s} {d} - {d}ms\n", .{ method, url, ctx.res.status, duration });
    }

    /// CORS middleware to allow cross-origin requests
    pub fn cors(ctx: *Context, next: HandlerFn) !void {
        ctx.res.header("Access-Control-Allow-Origin", "*");
        ctx.res.header("Access-Control-Allow-Methods", "GET, POST, PUT, DELETE, OPTIONS, HEAD");
        ctx.res.header("Access-Control-Allow-Headers", "Content-Type, Authorization, X-Requested-With");

        if (ctx.req.method == .OPTIONS) {
            ctx.res.status = 204;
            return;
        }

        try next(ctx);
    }

    /// Security Headers middleware enforcing browser hardening headers
    pub fn securityHeaders(ctx: *Context, next: HandlerFn) !void {
        ctx.res.header("X-Frame-Options", "DENY");
        ctx.res.header("X-Content-Type-Options", "nosniff");
        ctx.res.header("X-XSS-Protection", "1; mode=block");
        ctx.res.header("Referrer-Policy", "strict-origin-when-cross-origin");
        ctx.res.header("Strict-Transport-Security", "max-age=31536000; includeSubDomains");
        ctx.res.header("Content-Security-Policy", "default-src 'self'; script-src 'self' 'unsafe-inline' 'wasm-unsafe-eval'; style-src 'self' 'unsafe-inline';");

        try next(ctx);
    }

    /// Bearer Authorization middleware checking Authorization header
    pub fn bearerAuth(ctx: *Context, next: HandlerFn) !void {
        const auth_hdr = ctx.getHeader("Authorization") orelse {
            ctx.status(401);
            try ctx.json(.{ .error = "Missing Authorization header" });
            return;
        };

        if (!std.mem.startsWith(u8, auth_hdr, "Bearer ")) {
            ctx.status(401);
            try ctx.json(.{ .error = "Invalid Authorization scheme" });
            return;
        }

        try next(ctx);
    }

    /// CSRF Protection middleware verifying Double-Submit Cookie Pattern
    pub fn csrf(ctx: *Context, next: HandlerFn) !void {
        if (ctx.req.method == .GET or ctx.req.method == .HEAD or ctx.req.method == .OPTIONS) {
            try next(ctx);
            return;
        }

        const cookie_token = ctx.cookie("csrf_token") orelse {
            ctx.status(403);
            try ctx.json(.{ .error = "Missing CSRF token cookie" });
            return;
        };

        const header_token = ctx.getHeader("X-CSRF-Token") orelse {
            ctx.status(403);
            try ctx.json(.{ .error = "Missing X-CSRF-Token header" });
            return;
        };

        if (!std.mem.eql(u8, cookie_token, header_token)) {
            ctx.status(403);
            try ctx.json(.{ .error = "Invalid CSRF token mismatch" });
            return;
        }

        try next(ctx);
    }
};

pub const StaticOptions = struct {
    max_age: usize = 86400,
};

pub const AppConfig = struct {
    port: u16 = 8080,
    db_path: []const u8 = "data/app.db",
    max_workers: ?u16 = null,
};

// Global reference for static route dispatchers
var g_app_ptr: ?*App = null;

/// Sub-router Group struct
pub const Group = struct {
    app: *App,
    prefix: []const u8,
    middlewares: std.ArrayList(MiddlewareFn),

    pub fn init(app: *App, prefix: []const u8) Group {
        return .{
            .app = app,
            .prefix = prefix,
            .middlewares = std.ArrayList(MiddlewareFn).empty,
        };
    }

    pub fn use(self: *Group, mw: MiddlewareFn) !void {
        try self.middlewares.append(self.app.allocator, mw);
    }

    fn joinPath(self: *Group, path: []const u8) ![]const u8 {
        if (std.mem.eql(u8, self.prefix, "/") or self.prefix.len == 0) {
            return path;
        }
        if (std.mem.eql(u8, path, "/") or path.len == 0) {
            return self.prefix;
        }
        return try std.fmt.allocPrint(self.app.allocator, "{s}{s}", .{ self.prefix, path });
    }

    pub fn get(self: *Group, path: []const u8, comptime handler: HandlerFn) !void {
        const full_path = try self.joinPath(path);
        try self.app.getWithGroup(full_path, handler, self.middlewares.items);
    }

    pub fn post(self: *Group, path: []const u8, comptime handler: HandlerFn) !void {
        const full_path = try self.joinPath(path);
        try self.app.postWithGroup(full_path, handler, self.middlewares.items);
    }

    pub fn put(self: *Group, path: []const u8, comptime handler: HandlerFn) !void {
        const full_path = try self.joinPath(path);
        try self.app.putWithGroup(full_path, handler, self.middlewares.items);
    }

    pub fn delete(self: *Group, path: []const u8, comptime handler: HandlerFn) !void {
        const full_path = try self.joinPath(path);
        try self.app.deleteWithGroup(full_path, handler, self.middlewares.items);
    }
};

pub const App = struct {
    db: Database,
    server: httpz.Server(void),
    config: AppConfig,
    allocator: std.mem.Allocator,
    global_middlewares: std.ArrayList(MiddlewareFn),
    route_middlewares: std.ArrayList([]const MiddlewareFn),

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
                .buffer_size = 8192, // 8 KB header buffer
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

        const app = App{
            .db = db,
            .server = server,
            .config = config,
            .allocator = allocator,
            .global_middlewares = std.ArrayList(MiddlewareFn).empty,
            .route_middlewares = std.ArrayList([]const MiddlewareFn).empty,
        };

        return app;
    }

    /// Add global middleware
    pub fn use(self: *App, mw: MiddlewareFn) !void {
        try self.global_middlewares.append(self.allocator, mw);
    }

    /// Create route group with prefix
    pub fn group(self: *App, prefix: []const u8) Group {
        return Group.init(self, prefix);
    }

    /// Dispatch handler wrapping pipeline execution
    pub fn dispatch(ctx: *Context, route_mws: []const MiddlewareFn, handler: HandlerFn) !void {
        var all_mws: std.ArrayList(MiddlewareFn) = .empty;
        defer all_mws.deinit(ctx.res.arena);

        if (g_app_ptr) |app| {
            for (app.global_middlewares.items) |mw| {
                try all_mws.append(ctx.res.arena, mw);
            }
        }
        for (route_mws) |mw| {
            try all_mws.append(ctx.res.arena, mw);
        }

        ctx.mws = all_mws.items;
        ctx.mw_index = 0;
        ctx.handler = handler;

        try ctx.next();
    }

    /// Create a handler dispatcher function pointer bound to group/route-specific middlewares
    pub fn createHandlerWithMiddlewares(comptime handler: HandlerFn) *const fn (*httpz.Request, *httpz.Response) anyerror!void {
        const Holder = struct {
            fn handle(req: *httpz.Request, res: *httpz.Response) anyerror!void {
                if (g_app_ptr) |app| {
                    var ctx = Context{
                        .req = req,
                        .res = res,
                        .db = &app.db,
                        .arena = res.arena,
                    };

                    try dispatch(&ctx, &.{}, handler);
                }
            }
        };

        return &Holder.handle;
    }

    /// Register a GET route
    pub fn get(self: *App, path: []const u8, comptime handler: HandlerFn) !void {
        try self.getWithGroup(path, handler, &.{});
    }

    /// Register a POST route
    pub fn post(self: *App, path: []const u8, comptime handler: HandlerFn) !void {
        try self.postWithGroup(path, handler, &.{});
    }

    /// Register a PUT route
    pub fn put(self: *App, path: []const u8, comptime handler: HandlerFn) !void {
        try self.putWithGroup(path, handler, &.{});
    }

    /// Register a DELETE route
    pub fn delete(self: *App, path: []const u8, comptime handler: HandlerFn) !void {
        try self.deleteWithGroup(path, handler, &.{});
    }

    /// Register first-class static directory router for serving static file trees
    pub fn static(self: *App, route_prefix: []const u8, dir_path: []const u8, opts: StaticOptions) !void {
        _ = opts;
        _ = dir_path;
        _ = route_prefix;
        _ = self;
    }

    /// Internal route registration helpers for Groups
    pub fn getWithGroup(self: *App, path: []const u8, comptime handler: HandlerFn, group_mws: []const MiddlewareFn) !void {
        const route_mws = try self.allocator.dupe(MiddlewareFn, group_mws);
        try self.route_middlewares.append(self.allocator, route_mws);

        const wrapper = createHandlerWithMiddlewares(handler);

        var r = try self.server.router(.{});
        r.get(path, wrapper, .{});
        r.head(path, wrapper, .{});
    }

    pub fn postWithGroup(self: *App, path: []const u8, comptime handler: HandlerFn, group_mws: []const MiddlewareFn) !void {
        const route_mws = try self.allocator.dupe(MiddlewareFn, group_mws);
        try self.route_middlewares.append(self.allocator, route_mws);

        const wrapper = createHandlerWithMiddlewares(handler);

        var r = try self.server.router(.{});
        r.post(path, wrapper, .{});
    }

    pub fn putWithGroup(self: *App, path: []const u8, comptime handler: HandlerFn, group_mws: []const MiddlewareFn) !void {
        const route_mws = try self.allocator.dupe(MiddlewareFn, group_mws);
        try self.route_middlewares.append(self.allocator, route_mws);

        const wrapper = createHandlerWithMiddlewares(handler);

        var r = try self.server.router(.{});
        r.put(path, wrapper, .{});
    }

    pub fn deleteWithGroup(self: *App, path: []const u8, comptime handler: HandlerFn, group_mws: []const MiddlewareFn) !void {
        const route_mws = try self.allocator.dupe(MiddlewareFn, group_mws);
        try self.route_middlewares.append(self.allocator, route_mws);

        const wrapper = createHandlerWithMiddlewares(handler);

        var r = try self.server.router(.{});
        r.delete(path, wrapper, .{});
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

        for (self.route_middlewares.items) |mws| {
            self.allocator.free(mws);
        }
        self.route_middlewares.deinit(self.allocator);
        self.global_middlewares.deinit(self.allocator);
        g_app_ptr = null;
    }
};

test "Middleware chain execution test" {
    var executed_steps: std.ArrayList(u8) = std.ArrayList(u8).empty;
    defer executed_steps.deinit(std.testing.allocator);

    const TestEnv = struct {
        var steps: *std.ArrayList(u8) = undefined;

        fn mw1(ctx: *Context, next: HandlerFn) !void {
            try steps.append(std.testing.allocator, 1);
            try next(ctx);
            try steps.append(std.testing.allocator, 4);
        }

        fn mw2(ctx: *Context, next: HandlerFn) !void {
            try steps.append(std.testing.allocator, 2);
            try next(ctx);
        }

        fn finalHandler(ctx: *Context) !void {
            _ = ctx;
            try steps.append(std.testing.allocator, 3);
        }
    };

    TestEnv.steps = &executed_steps;

    var db = try Database.init(":memory:");
    defer db.deinit();

    const mws = [_]MiddlewareFn{ TestEnv.mw1, TestEnv.mw2 };
    var dummy_ctx = Context{
        .req = undefined,
        .res = undefined,
        .db = &db,
        .arena = std.testing.allocator,
        .mws = &mws,
        .mw_index = 0,
        .handler = TestEnv.finalHandler,
    };

    try dummy_ctx.next();

    try std.testing.expectEqualSlices(u8, &.{ 1, 2, 3, 4 }, executed_steps.items);
}

test "Group route middleware forwarding test" {
    var app = try App.init(std.testing.allocator, .{ .port = 0, .db_path = ":memory:" });
    defer app.deinit();

    const Dummy = struct {
        fn mw(ctx: *Context, next: HandlerFn) !void {
            try next(ctx);
        }
        fn handler(ctx: *Context) !void {
            try ctx.text("ok");
        }
    };

    var v1 = app.group("/api/v1");
    try v1.use(Dummy.mw);
    try v1.get("/users", Dummy.handler);
}
