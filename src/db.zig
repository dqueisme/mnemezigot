const std = @import("std");

pub const c = @cImport({
    @cInclude("sqlite3.h");
});

/// Database Migration representation
pub const Migration = struct {
    version: usize,
    name: []const u8,
    sql: []const u8,
};

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

    /// Execute a function block within an atomic SQLite transaction
    pub fn transaction(self: *Database, comptime func: fn (*Database) anyerror!void) !void {
        try self.exec("BEGIN TRANSACTION;");
        func(self) catch |err| {
            try self.exec("ROLLBACK;");
            return err;
        };
        try self.exec("COMMIT;");
    }

    /// Execute database migrations automatically tracking versions in `schema_migrations`
    pub fn migrate(self: *Database, migrations: []const Migration) !void {
        try self.exec("CREATE TABLE IF NOT EXISTS schema_migrations (version INTEGER PRIMARY KEY, name TEXT NOT NULL, applied_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP);");

        for (migrations) |m| {
            var z_sql: [1024:0]u8 = undefined;
            const sql_check = "SELECT COUNT(*) FROM schema_migrations WHERE version = ?;";
            @memcpy(z_sql[0..sql_check.len], sql_check);
            z_sql[sql_check.len] = 0;

            self.acquireLock();
            var stmt: ?*c.sqlite3_stmt = null;
            if (c.sqlite3_prepare_v2(self.handle, &z_sql, -1, &stmt, null) != c.SQLITE_OK) {
                self.releaseLock();
                return error.PrepareFailed;
            }
            _ = c.sqlite3_bind_int64(stmt, 1, @intCast(m.version));
            const exists = (c.sqlite3_step(stmt) == c.SQLITE_ROW and c.sqlite3_column_int64(stmt, 0) > 0);
            _ = c.sqlite3_finalize(stmt);
            self.releaseLock();

            if (!exists) {
                std.debug.print("🔄 [Mnemezigot DB] Applying migration v{d}: {s}\n", .{ m.version, m.name });
                try self.exec(m.sql);

                var z_ins: [1024:0]u8 = undefined;
                const sql_ins = "INSERT INTO schema_migrations (version, name) VALUES (?, ?);";
                @memcpy(z_ins[0..sql_ins.len], sql_ins);
                z_ins[sql_ins.len] = 0;

                self.acquireLock();
                var stmt_ins: ?*c.sqlite3_stmt = null;
                if (c.sqlite3_prepare_v2(self.handle, &z_ins, -1, &stmt_ins, null) == c.SQLITE_OK) {
                    _ = c.sqlite3_bind_int64(stmt_ins, 1, @intCast(m.version));
                    _ = c.sqlite3_bind_text(stmt_ins, 2, m.name.ptr, @intCast(m.name.len), c.SQLITE_STATIC);
                    _ = c.sqlite3_step(stmt_ins);
                    _ = c.sqlite3_finalize(stmt_ins);
                }
                self.releaseLock();
            }
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

    /// Model Query Builder (Struct-First)
    pub fn from(self: *Database, comptime T: type) @import("model.zig").ModelQuery(T) {
        return @import("model.zig").ModelQuery(T).init(self);
    }

    pub fn model(self: *Database, comptime T: type) @import("model.zig").ModelQuery(T) {
        return self.from(T);
    }

    pub fn deinit(self: *Database) void {
        if (self.handle) |h| {
            _ = c.sqlite3_close(h);
            self.handle = null;
        }
    }
};

test "Database Migration & Transaction test" {
    var db = try Database.init(":memory:");
    defer db.deinit();

    const migrations = [_]Migration{
        .{ .version = 1, .name = "create_users", .sql = "CREATE TABLE users (id INTEGER PRIMARY KEY, name TEXT);" },
        .{ .version = 2, .name = "add_email", .sql = "ALTER TABLE users ADD COLUMN email TEXT;" },
    };

    try db.migrate(&migrations);
    try db.migrate(&migrations); // Re-run should be idempotent

    const migration_count = try db.queryScalarInt("SELECT COUNT(*) FROM schema_migrations;");
    try std.testing.expectEqual(@as(i64, 2), migration_count);

    // Test Transaction
    const Tx = struct {
        fn run(d: *Database) !void {
            try d.exec("INSERT INTO users (name, email) VALUES ('Alice', 'alice@test.com');");
            try d.exec("INSERT INTO users (name, email) VALUES ('Bob', 'bob@test.com');");
        }
    };

    try db.transaction(Tx.run);
    const user_count = try db.queryScalarInt("SELECT COUNT(*) FROM users;");
    try std.testing.expectEqual(@as(i64, 2), user_count);
}
