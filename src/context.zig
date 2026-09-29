const std = @import("std");
const httpz = @import("httpz");
const Database = @import("db.zig").Database;
const grpc = @import("grpc.zig");

pub const HandlerFn = *const fn (*Context) anyerror!void;

/// Helper function to detect MIME type from file extension
pub fn getMimeType(filepath: []const u8) []const u8 {
    const ext = std.fs.path.extension(filepath);
    if (std.mem.eql(u8, ext, ".html") or std.mem.eql(u8, ext, ".htm")) return "text/html; charset=utf-8";
    if (std.mem.eql(u8, ext, ".css")) return "text/css; charset=utf-8";
    if (std.mem.eql(u8, ext, ".js") or std.mem.eql(u8, ext, ".mjs")) return "application/javascript; charset=utf-8";
    if (std.mem.eql(u8, ext, ".json")) return "application/json; charset=utf-8";
    if (std.mem.eql(u8, ext, ".wasm")) return "application/wasm";
    if (std.mem.eql(u8, ext, ".png")) return "image/png";
    if (std.mem.eql(u8, ext, ".jpg") or std.mem.eql(u8, ext, ".jpeg")) return "image/jpeg";
    if (std.mem.eql(u8, ext, ".gif")) return "image/gif";
    if (std.mem.eql(u8, ext, ".svg")) return "image/svg+xml";
    if (std.mem.eql(u8, ext, ".ico")) return "image/x-icon";
    if (std.mem.eql(u8, ext, ".txt")) return "text/plain; charset=utf-8";
    return "application/octet-stream";
}

/// Cookie options when setting Set-Cookie header
pub const CookieOptions = struct {
    path: []const u8 = "/",
    max_age: ?i64 = null,
    domain: ?[]const u8 = null,
    secure: bool = false,
    http_only: bool = true,
    same_site: []const u8 = "Lax",
};

/// Middleware function type
pub const MiddlewareFn = *const fn (ctx: *Context, next: HandlerFn) anyerror!void;

/// Helper wrapper function passed to middleware `next` argument
fn nextFnWrapper(ctx: *Context) anyerror!void {
    try ctx.next();
}

/// Request / Response Context for Mnemezigot Handlers
pub const Context = struct {
    req: *httpz.Request,
    res: *httpz.Response,
    db: *Database,
    arena: std.mem.Allocator,
    mws: []const MiddlewareFn = &.{},
    mw_index: usize = 0,
    handler: ?HandlerFn = null,

    /// Execute next middleware in pipeline or final route handler
    pub fn next(self: *Context) anyerror!void {
        if (self.mw_index < self.mws.len) {
            const idx = self.mw_index;
            self.mw_index += 1;
            const mw = self.mws[idx];
            try mw(self, nextFnWrapper);
        } else if (self.handler) |h| {
            try h(self);
        }
    }

    // =========================================================================
    // OUTPUT 1: Web UI (HTML / CSS / WASM / Static Files)
    // =========================================================================

    /// Send HTML response
    pub fn html(self: *Context, content: []const u8) !void {
        self.res.header("Content-Type", "text/html; charset=utf-8");
        self.res.header("Access-Control-Allow-Origin", "*");
        self.res.body = content;
    }

    /// Send CSS response
    pub fn css(self: *Context, content: []const u8) !void {
        self.res.header("Content-Type", "text/css");
        self.res.header("Access-Control-Allow-Origin", "*");
        self.res.body = content;
    }

    /// Send compiled WebAssembly binary
    pub fn wasm(self: *Context, wasm_bytes: []const u8) !void {
        self.res.header("Content-Type", "application/wasm");
        self.res.header("Access-Control-Allow-Origin", "*");
        self.res.body = wasm_bytes;
    }

    /// Send plain text response
    pub fn text(self: *Context, content: []const u8) !void {
        self.res.header("Content-Type", "text/plain; charset=utf-8");
        self.res.header("Access-Control-Allow-Origin", "*");
        self.res.body = content;
    }

    /// Serve embedded or raw file content with automatic MIME type detection
    pub fn file(self: *Context, filepath: []const u8, content: []const u8) !void {
        const mime = getMimeType(filepath);
        self.res.header("Content-Type", mime);
        self.res.header("Access-Control-Allow-Origin", "*");
        self.res.header("Cache-Control", "public, max-age=3600");
        self.res.body = content;
    }

    // =========================================================================
    // REAL-TIME: Server-Sent Events (SSE)
    // =========================================================================

    /// Initialize Server-Sent Events headers
    pub fn sseInit(self: *Context) void {
        self.res.header("Content-Type", "text/event-stream");
        self.res.header("Cache-Control", "no-cache");
        self.res.header("Connection", "keep-alive");
        self.res.header("Access-Control-Allow-Origin", "*");
    }

    /// Format and append an SSE event payload to response body
    pub fn sendSseEvent(self: *Context, event_name: []const u8, data: []const u8) !void {
        self.sseInit();
        const formatted = try std.fmt.allocPrint(self.res.arena, "event: {s}\ndata: {s}\n\n", .{ event_name, data });
        self.res.body = formatted;
    }

    // =========================================================================
    // HTMX INTEGRATION HELPERS
    // =========================================================================

    /// Check if request was triggered by HTMX (HX-Request header present)
    pub fn isHtmx(self: *Context) bool {
        return self.getHeader("HX-Request") != null;
    }

    /// Trigger client-side event in HTMX via HX-Trigger header
    pub fn htmxTrigger(self: *Context, event_name: []const u8) void {
        self.res.header("HX-Trigger", event_name);
    }

    /// Client-side redirect for HTMX via HX-Redirect header
    pub fn htmxRedirect(self: *Context, url: []const u8) void {
        self.res.header("HX-Redirect", url);
    }

    // =========================================================================
    // OUTPUT 2: REST API (JSON)
    // =========================================================================

    /// Serialize any Zig struct, slice, or value to JSON and return with application/json
    pub fn json(self: *Context, data: anytype) !void {
        const body_bytes = try std.fmt.allocPrint(self.res.arena, "{f}", .{std.json.fmt(data, .{})});
        self.res.header("Content-Type", "application/json");
        self.res.header("Access-Control-Allow-Origin", "*");
        self.res.body = body_bytes;
    }

    /// Parse request JSON body into a Zig struct type T
    pub fn bindJson(self: *Context, comptime T: type) !std.json.Parsed(T) {
        const raw_body = self.req.body() orelse return error.EmptyRequestBody;
        return std.json.parseFromSlice(T, self.arena, raw_body, .{
            .ignore_unknown_fields = true,
        });
    }

    // =========================================================================
    // OUTPUT 3: gRPC (gRPC-Web / Protobuf)
    // =========================================================================

    /// Send gRPC-Web response frame with protobuf payload and standard trailer
    pub fn grpcResponse(self: *Context, proto_payload: []const u8) !void {
        const frame = try grpc.wrapFrame(self.res.arena, proto_payload);
        self.res.header("Content-Type", "application/grpc-web+proto");
        self.res.header("Access-Control-Allow-Origin", "*");
        self.res.header("Access-Control-Expose-Headers", "grpc-status, grpc-message");
        self.res.header("Cache-Control", "no-cache");
        self.res.body = frame;
    }

    // =========================================================================
    // Request Utilities & Context Helpers
    // =========================================================================

    /// Get raw request body
    pub fn body(self: *Context) []const u8 {
        return self.req.body() orelse "";
    }

    /// Get URL path parameter (e.g. /users/:id)
    pub fn param(self: *Context, name: []const u8) ?[]const u8 {
        return self.req.param(name);
    }

    /// Get URL query parameter by key (e.g. /search?q=zig)
    pub fn query(self: *Context, key: []const u8) ?[]const u8 {
        const query_params = self.req.query() catch return null;
        return query_params.get(key);
    }

    /// Get URL query parameter as 64-bit integer
    pub fn queryInt(self: *Context, key: []const u8) ?i64 {
        const val_str = self.query(key) orelse return null;
        return std.fmt.parseInt(i64, val_str, 10) catch null;
    }

    /// Get request header value by key
    pub fn getHeader(self: *Context, key: []const u8) ?[]const u8 {
        return self.req.header(key);
    }

    /// Set response header value
    pub fn header(self: *Context, key: []const u8, value: []const u8) void {
        self.res.header(key, value);
    }

    /// Get request Cookie value by name
    pub fn cookie(self: *Context, name: []const u8) ?[]const u8 {
        const cookie_header = self.getHeader("Cookie") orelse return null;
        var iter = std.mem.splitSequence(u8, cookie_header, ";");
        while (iter.next()) |pair_raw| {
            const pair = std.mem.trim(u8, pair_raw, " ");
            if (std.mem.indexOfScalar(u8, pair, '=')) |eq_idx| {
                const k = std.mem.trim(u8, pair[0..eq_idx], " ");
                if (std.mem.eql(u8, k, name)) {
                    return std.mem.trim(u8, pair[eq_idx + 1 ..], " ");
                }
            }
        }
        return null;
    }

    /// Set Set-Cookie header in response
    pub fn setCookie(self: *Context, name: []const u8, value: []const u8, opts: CookieOptions) !void {
        var cookie_buf: std.ArrayList(u8) = .empty;
        // Allocated in res.arena so memory persists safely until request finish
        try std.fmt.format(cookie_buf.writer(self.res.arena), "{s}={s}; Path={s}", .{ name, value, opts.path });

        if (opts.max_age) |ma| {
            try std.fmt.format(cookie_buf.writer(self.res.arena), "; Max-Age={d}", .{ma});
        }
        if (opts.domain) |d| {
            try std.fmt.format(cookie_buf.writer(self.res.arena), "; Domain={s}", .{d});
        }
        if (opts.same_site.len > 0) {
            try std.fmt.format(cookie_buf.writer(self.res.arena), "; SameSite={s}", .{opts.same_site});
        }
        if (opts.http_only) {
            try cookie_buf.appendSlice(self.res.arena, "; HttpOnly");
        }
        if (opts.secure) {
            try cookie_buf.appendSlice(self.res.arena, "; Secure");
        }

        self.res.header("Set-Cookie", cookie_buf.items);
    }

    /// Set HTTP status code
    pub fn status(self: *Context, code: u16) void {
        self.res.status = code;
    }
};

test "MIME type detection" {
    try std.testing.expectEqualStrings("text/html; charset=utf-8", getMimeType("index.html"));
    try std.testing.expectEqualStrings("text/css; charset=utf-8", getMimeType("style.css"));
    try std.testing.expectEqualStrings("application/wasm", getMimeType("app.wasm"));
    try std.testing.expectEqualStrings("application/javascript; charset=utf-8", getMimeType("app.js"));
    try std.testing.expectEqualStrings("image/png", getMimeType("logo.png"));
    try std.testing.expectEqualStrings("application/octet-stream", getMimeType("unknown.xyz"));
}

test "cookie helper parsing" {
    const raw_cookie = "session=xyz123; user_id=42; theme=dark";
    var iter = std.mem.splitSequence(u8, raw_cookie, ";");
    var found_session: ?[]const u8 = null;
    var found_user_id: ?[]const u8 = null;

    while (iter.next()) |pair_raw| {
        const pair = std.mem.trim(u8, pair_raw, " ");
        if (std.mem.indexOfScalar(u8, pair, '=')) |eq_idx| {
            const k = std.mem.trim(u8, pair[0..eq_idx], " ");
            const v = std.mem.trim(u8, pair[eq_idx + 1 ..], " ");
            if (std.mem.eql(u8, k, "session")) found_session = v;
            if (std.mem.eql(u8, k, "user_id")) found_user_id = v;
        }
    }

    try std.testing.expectEqualStrings("xyz123", found_session.?);
    try std.testing.expectEqualStrings("42", found_user_id.?);
}
