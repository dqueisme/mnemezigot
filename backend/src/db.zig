const std = @import("std");

const c = @cImport({
    @cInclude("sqlite3.h");
});

pub const Database = struct {
    db: ?*c.sqlite3 = null,
    stmt_get_random: ?*c.sqlite3_stmt = null,
    stmt_count: ?*c.sqlite3_stmt = null,
    total_names: i64 = 0,
    prng: std.Random.DefaultPrng = undefined,
    mutex: std.atomic.Mutex = .unlocked,

    fn acquireLock(self: *Database) void {
        while (!self.mutex.tryLock()) {
            std.atomic.spinLoopHint();
        }
    }

    fn releaseLock(self: *Database) void {
        self.mutex.unlock();
    }

    pub fn init(self: *Database, db_path: []const u8) !void {
        const cwd = std.Io.Dir.cwd();
        const io = std.Io.Threaded.global_single_threaded.io();
        cwd.createDir(io, "data", .default_dir) catch {};

        var path_z: [256:0]u8 = undefined;
        @memcpy(path_z[0..db_path.len], db_path);
        path_z[db_path.len] = 0;

        if (c.sqlite3_open_v2(&path_z, &self.db, c.SQLITE_OPEN_READWRITE | c.SQLITE_OPEN_CREATE, null) != c.SQLITE_OK) {
            std.debug.print("❌ Failed to open SQLite database: {s}\n", .{c.sqlite3_errmsg(self.db)});
            return error.SqliteOpenFailed;
        }

        // Production High-Performance PRAGMAs
        _ = c.sqlite3_exec(self.db, "PRAGMA journal_mode = WAL;", null, null, null);
        _ = c.sqlite3_exec(self.db, "PRAGMA synchronous = NORMAL;", null, null, null);
        _ = c.sqlite3_exec(self.db, "PRAGMA mmap_size = 30000000000;", null, null, null);
        _ = c.sqlite3_exec(self.db, "PRAGMA cache_size = -64000;", null, null, null);
        _ = c.sqlite3_exec(self.db, "PRAGMA busy_timeout = 5000;", null, null, null);

        // Create table
        const create_sql =
            \\CREATE TABLE IF NOT EXISTS names (
            \\    id INTEGER PRIMARY KEY AUTOINCREMENT,
            \\    name TEXT NOT NULL UNIQUE
            \\);
        ;
        _ = c.sqlite3_exec(self.db, create_sql, null, null, null);

        // Seed initial default names if table is empty
        _ = c.sqlite3_exec(self.db, "INSERT OR IGNORE INTO names (name) VALUES ('Andi'), ('Budi'), ('Citra'), ('Dewi'), ('Eko');", null, null, null);

        // Count total names
        var count_stmt: ?*c.sqlite3_stmt = null;
        if (c.sqlite3_prepare_v2(self.db, "SELECT COUNT(*) FROM names;", -1, &count_stmt, null) == c.SQLITE_OK) {
            if (c.sqlite3_step(count_stmt) == c.SQLITE_ROW) {
                self.total_names = c.sqlite3_column_int64(count_stmt, 0);
            }
            _ = c.sqlite3_finalize(count_stmt);
        }

        // Prepare query statement
        const query_sql = "SELECT name FROM names WHERE id = ? LIMIT 1;";
        if (c.sqlite3_prepare_v2(self.db, query_sql, -1, &self.stmt_get_random, null) != c.SQLITE_OK) {
            std.debug.print("❌ Failed to prepare query statement: {s}\n", .{c.sqlite3_errmsg(self.db)});
            return error.SqlitePrepareFailed;
        }

        var ts: std.posix.timespec = undefined;
        _ = std.posix.system.clock_gettime(.MONOTONIC, &ts);
        const seed = @as(u64, @intCast(ts.sec)) * 1_000_000_000 + @as(u64, @intCast(ts.nsec));
        self.prng = std.Random.DefaultPrng.init(@truncate(seed));

        std.debug.print("📦 [SQLite WAL] Initialized successfully ({d} names stored in {s})\n", .{ self.total_names, db_path });
    }

    pub fn getRandomName(self: *Database) []const u8 {
        if (self.total_names == 0 or self.stmt_get_random == null) {
            return "Mnemezigot";
        }

        self.acquireLock();
        defer self.releaseLock();

        const rand_id = (self.prng.random().uintLessThan(u64, @intCast(self.total_names))) + 1;

        _ = c.sqlite3_reset(self.stmt_get_random);
        _ = c.sqlite3_bind_int64(self.stmt_get_random, 1, @intCast(rand_id));

        if (c.sqlite3_step(self.stmt_get_random) == c.SQLITE_ROW) {
            if (c.sqlite3_column_text(self.stmt_get_random, 0)) |ptr| {
                return std.mem.span(@as([*:0]const u8, @ptrCast(ptr)));
            }
        }

        return "Mnemezigot";
    }

    pub fn deinit(self: *Database) void {
        if (self.stmt_get_random) |stmt| {
            _ = c.sqlite3_finalize(stmt);
        }
        if (self.db) |db| {
            _ = c.sqlite3_close(db);
        }
    }
};
