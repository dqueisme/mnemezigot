const std = @import("std");
const httpz = @import("httpz");
const Database = @import("db.zig").Database;
const grpc = @import("grpc.zig");

pub const HandlerFn = *const fn (*Context) anyerror!void;

/// Request / Response Context for Mnemezigot Handlers
pub const Context = struct {
    req: *httpz.Request,
    res: *httpz.Response,
    db: *Database,
    arena: std.mem.Allocator,

    // =========================================================================
    // OUTPUT 1: Web UI (HTML / CSS / WASM)
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
    // Request Utilities
    // =========================================================================

    /// Get raw request body
    pub fn body(self: *Context) []const u8 {
        return self.req.body() orelse "";
    }

    /// Get URL path parameter (e.g. /users/:id)
    pub fn param(self: *Context, name: []const u8) ?[]const u8 {
        return self.req.param(name);
    }

    /// Set HTTP status code
    pub fn status(self: *Context, code: u16) void {
        self.res.status = code;
    }

    /// Set custom response header
    pub fn header(self: *Context, key: []const u8, value: []const u8) void {
        self.res.header(key, value);
    }
};
