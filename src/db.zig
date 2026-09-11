const std = @import("std");

pub const c = @cImport({
    @cInclude("sqlite3.h");
});

/// Embedded SQLite 3.46 Database Engine
/// MANDATORY ZERO-CONFIG: Write-Ahead Logging (WAL) Mode Active by Default
pub const Database = struct {
    handle: ?*c.sqlite3 = null,
    mutex: std.atomic.Mutex = .unlocked,
    path: []const u8 = "data/app.db",

    pub fn acquireLock(self: *Database) void {
        while (!self.mutex.tryLock()) {
            std.atomic.spinLoopHint();
        }
    }

    pub fn releaseLock(self: *Database) void {
        self.mutex.unlock();
    }

    pub fn init(db_path: []const u8) !Database {
        var db = Database{ .path = db_path };

        // Ensure parent directory exists
        const cwd = std.Io.Dir.cwd();
        const io = std.Io.Threaded.global_single_threaded.io();
        if (std.fs.path.dirname(db_path)) |parent_dir| {
            if (parent_dir.len > 0) {
                cwd.createDir(io, parent_dir, .default_dir) catch {};
            }
        }

        var path_z: [256:0]u8 = undefined;
        if (db_path.len >= path_z.len) return error.PathTooLong;
        @memcpy(path_z[0..db_path.len], db_path);
        path_z[db_path.len] = 0;

        if (c.sqlite3_open_v2(&path_z, &db.handle, c.SQLITE_OPEN_READWRITE | c.SQLITE_OPEN_CREATE, null) != c.SQLITE_OK) {
            std.debug.print("❌ [Mnemezigot DB] Failed to open SQLite: {s}\n", .{c.sqlite3_errmsg(db.handle)});
            return error.SqliteOpenFailed;
        }

        // ============================================================
        // MANDATORY WAL MODE CONFIGURATION (Zero-Config High Concurrency)
        // ============================================================
        _ = c.sqlite3_exec(db.handle, "PRAGMA journal_mode = WAL;", null, null, null);
        _ = c.sqlite3_exec(db.handle, "PRAGMA synchronous = NORMAL;", null, null, null);
        _ = c.sqlite3_exec(db.handle, "PRAGMA mmap_size = 30000000000;", null, null, null);
        _ = c.sqlite3_exec(db.handle, "PRAGMA cache_size = -64000;", null, null, null);
        _ = c.sqlite3_exec(db.handle, "PRAGMA busy_timeout = 5000;", null, null, null);

        std.debug.print("📦 [Mnemezigot DB] SQLite WAL Mode Active -> {s}\n", .{db_path});

        return db;
    }

    /// Execute a non-query SQL command (e.g. CREATE TABLE, INSERT, UPDATE, DELETE)
    pub fn exec(self: *Database, sql: []const u8) !void {
        self.acquireLock();
        defer self.releaseLock();

        var z_buf: [2048:0]u8 = undefined;
        if (sql.len >= z_buf.len) return error.SqlTooLong;
        @memcpy(z_buf[0..sql.len], sql);
        z_buf[sql.len] = 0;

        var errmsg: [*c]u8 = null;
        if (c.sqlite3_exec(self.handle, &z_buf, null, null, &errmsg) != c.SQLITE_OK) {
            if (errmsg != null) {
                std.debug.print("❌ [Mnemezigot DB] SQL Error: {s}\n", .{errmsg});
                c.sqlite3_free(errmsg);
            }
            return error.SqliteExecFailed;
        }
    }

    /// Execute an INSERT with a single text parameter (Convenience helper)
    pub fn insertText(self: *Database, sql: []const u8, text: []const u8) !void {
        self.acquireLock();
        defer self.releaseLock();

        var z_sql: [1024:0]u8 = undefined;
        @memcpy(z_sql[0..sql.len], sql);
        z_sql[sql.len] = 0;

        var stmt: ?*c.sqlite3_stmt = null;
        if (c.sqlite3_prepare_v2(self.handle, &z_sql, -1, &stmt, null) != c.SQLITE_OK) {
            return error.PrepareFailed;
        }
        defer _ = c.sqlite3_finalize(stmt);

        _ = c.sqlite3_bind_text(stmt, 1, text.ptr, @intCast(text.len), c.SQLITE_STATIC);

        if (c.sqlite3_step(stmt) != c.SQLITE_DONE) {
            return error.StepFailed;
        }
    }

    /// Query a scalar integer (e.g. SELECT COUNT(*) FROM table)
    pub fn queryScalarInt(self: *Database, sql: []const u8) !i64 {
        self.acquireLock();
        defer self.releaseLock();

        var z_sql: [1024:0]u8 = undefined;
        @memcpy(z_sql[0..sql.len], sql);
        z_sql[sql.len] = 0;

        var stmt: ?*c.sqlite3_stmt = null;
        if (c.sqlite3_prepare_v2(self.handle, &z_sql, -1, &stmt, null) != c.SQLITE_OK) {
            return error.PrepareFailed;
        }
        defer _ = c.sqlite3_finalize(stmt);

        if (c.sqlite3_step(stmt) == c.SQLITE_ROW) {
            return c.sqlite3_column_int64(stmt, 0);
        }
        return 0;
    }

    pub fn deinit(self: *Database) void {
        if (self.handle) |h| {
            _ = c.sqlite3_close(h);
            self.handle = null;
        }
    }
};
