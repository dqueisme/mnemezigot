const std = @import("std");
const db_mod = @import("db.zig");
const Database = db_mod.Database;
const c = db_mod.c;

/// Bind a single value to a prepared SQLite statement placeholder
fn bindValue(stmt: ?*c.sqlite3_stmt, idx: c_int, val: anytype) !void {
    const ValType = @TypeOf(val);
    const info = @typeInfo(ValType);

    switch (info) {
        .pointer => {
            const slice: []const u8 = val;
            if (c.sqlite3_bind_text(stmt, idx, slice.ptr, @intCast(slice.len), c.SQLITE_STATIC) != c.SQLITE_OK) {
                return error.BindFailed;
            }
        },
        .int, .comptime_int => {
            if (c.sqlite3_bind_int64(stmt, idx, @intCast(val)) != c.SQLITE_OK) {
                return error.BindFailed;
            }
        },
        .float, .comptime_float => {
            if (c.sqlite3_bind_double(stmt, idx, @floatCast(val)) != c.SQLITE_OK) {
                return error.BindFailed;
            }
        },
        .bool => {
            if (c.sqlite3_bind_int(stmt, idx, if (val) 1 else 0) != c.SQLITE_OK) {
                return error.BindFailed;
            }
        },
        .optional => {
            if (val) |unwrapped| {
                try bindValue(stmt, idx, unwrapped);
            } else {
                if (c.sqlite3_bind_null(stmt, idx) != c.SQLITE_OK) {
                    return error.BindFailed;
                }
            }
        },
        else => @compileError("Unsupported value type for SQLite bind: " ++ @typeName(ValType)),
    }
}

/// Read a column from a prepared SQLite row into the target Zig type
fn readColumn(stmt: ?*c.sqlite3_stmt, col_idx: c_int, comptime FieldType: type, allocator: std.mem.Allocator) !FieldType {
    const col_type = c.sqlite3_column_type(stmt, col_idx);
    const info = @typeInfo(FieldType);

    switch (info) {
        .optional => |opt| {
            if (col_type == c.SQLITE_NULL) {
                return null;
            }
            return try readColumn(stmt, col_idx, opt.child, allocator);
        },
        .pointer => |p| {
            if (p.size == .slice and p.child == u8) {
                if (col_type == c.SQLITE_NULL) return "";
                const ptr = c.sqlite3_column_text(stmt, col_idx);
                const bytes = c.sqlite3_column_bytes(stmt, col_idx);
                if (ptr == null or bytes == 0) return "";
                return try allocator.dupe(u8, ptr[0..@intCast(bytes)]);
            }
            @compileError("Unsupported pointer type in model: " ++ @typeName(FieldType));
        },
        .int => {
            return @intCast(c.sqlite3_column_int64(stmt, col_idx));
        },
        .float => {
            return @floatCast(c.sqlite3_column_double(stmt, col_idx));
        },
        .bool => {
            return c.sqlite3_column_int(stmt, col_idx) != 0;
        },
        else => @compileError("Unsupported field type in model: " ++ @typeName(FieldType)),
    }
}

/// Compile-time SQL generator and model executor for struct T
pub fn ModelQuery(comptime T: type) type {
    return struct {
        const Self = @This();

        pub const table_name: []const u8 = if (@hasDecl(T, "table_name"))
            @field(T, "table_name")
        else
            @typeName(T);

        pub const column_list: []const u8 = blk: {
            var str: []const u8 = "";
            const fields = @typeInfo(T).@"struct".fields;
            for (fields, 0..) |f, i| {
                if (i > 0) {
                    str = str ++ ", " ++ f.name;
                } else {
                    str = str ++ f.name;
                }
            }
            break :blk str;
        };

        pub const create_table_sql: []const u8 = blk: {
            var ddl: []const u8 = "CREATE TABLE IF NOT EXISTS " ++ table_name ++ " (";
            const fields = @typeInfo(T).@"struct".fields;
            for (fields, 0..) |f, i| {
                if (i > 0) ddl = ddl ++ ", ";
                ddl = ddl ++ f.name ++ " ";
                if (std.mem.eql(u8, f.name, "id")) {
                    ddl = ddl ++ "INTEGER PRIMARY KEY AUTOINCREMENT";
                } else if (std.mem.eql(u8, f.name, "created_at")) {
                    ddl = ddl ++ "TIMESTAMP DEFAULT CURRENT_TIMESTAMP";
                } else {
                    const info = @typeInfo(f.type);
                    switch (info) {
                        .pointer => |p| if (p.size == .slice and p.child == u8) {
                            ddl = ddl ++ "TEXT NOT NULL";
                        },
                        .optional => |opt| {
                            const child_info = @typeInfo(opt.child);
                            switch (child_info) {
                                .pointer => |p| if (p.size == .slice and p.child == u8) {
                                    ddl = ddl ++ "TEXT";
                                },
                                .int => ddl = ddl ++ "INTEGER",
                                .float => ddl = ddl ++ "REAL",
                                .bool => ddl = ddl ++ "INTEGER",
                                else => ddl = ddl ++ "TEXT",
                            }
                        },
                        .int => ddl = ddl ++ "INTEGER NOT NULL",
                        .float => ddl = ddl ++ "REAL NOT NULL",
                        .bool => ddl = ddl ++ "INTEGER NOT NULL",
                        else => ddl = ddl ++ "TEXT NOT NULL",
                    }
                }
            }
            ddl = ddl ++ ");";
            break :blk ddl;
        };

        pub fn insertSql(comptime DataType: type) []const u8 {
            comptime var cols: []const u8 = "";
            comptime var vals: []const u8 = "";
            const fields = @typeInfo(DataType).@"struct".fields;
            inline for (fields, 0..) |f, i| {
                if (i > 0) {
                    cols = cols ++ ", " ++ f.name;
                    vals = vals ++ ", ?";
                } else {
                    cols = cols ++ f.name;
                    vals = vals ++ "?";
                }
            }
            return "INSERT INTO " ++ table_name ++ " (" ++ cols ++ ") VALUES (" ++ vals ++ ");";
        }

        db: *Database,

        pub fn init(db: *Database) Self {
            return .{ .db = db };
        }

        /// Automatically create table if not already existing based on struct fields
        pub fn createTableIfNotExists(self: Self) !void {
            try self.db.exec(create_table_sql);
        }

        /// Count total rows in table: SELECT COUNT(*) FROM table;
        pub fn count(self: Self) !i64 {
            const sql = "SELECT COUNT(*) FROM " ++ table_name ++ ";";
            return self.db.queryScalarInt(sql);
        }

        /// Insert record into table from an anonymous struct or model instance
        pub fn insert(self: Self, data: anytype) !i64 {
            const sql = comptime insertSql(@TypeOf(data));

            self.db.acquireLock();
            defer self.db.releaseLock();

            var stmt: ?*c.sqlite3_stmt = null;
            if (c.sqlite3_prepare_v2(self.db.handle, sql.ptr, @intCast(sql.len), &stmt, null) != c.SQLITE_OK) {
                return error.PrepareFailed;
            }
            defer _ = c.sqlite3_finalize(stmt);

            inline for (@typeInfo(@TypeOf(data)).@"struct".fields, 1..) |field, idx| {
                const val = @field(data, field.name);
                try bindValue(stmt, @intCast(idx), val);
            }

            if (c.sqlite3_step(stmt) != c.SQLITE_DONE) {
                return error.StepFailed;
            }

            return c.sqlite3_last_insert_rowid(self.db.handle);
        }

        /// Fetch all records mapped to []T allocated via allocator
        pub fn all(self: Self, allocator: std.mem.Allocator) ![]T {
            const sql = "SELECT " ++ column_list ++ " FROM " ++ table_name ++ ";";

            self.db.acquireLock();
            defer self.db.releaseLock();

            var stmt: ?*c.sqlite3_stmt = null;
            if (c.sqlite3_prepare_v2(self.db.handle, sql.ptr, @intCast(sql.len), &stmt, null) != c.SQLITE_OK) {
                return error.PrepareFailed;
            }
            defer _ = c.sqlite3_finalize(stmt);

            var list: std.ArrayList(T) = .empty;
            defer list.deinit(allocator);

            while (c.sqlite3_step(stmt) == c.SQLITE_ROW) {
                var item: T = undefined;
                inline for (@typeInfo(T).@"struct".fields, 0..) |f, col_idx| {
                    @field(item, f.name) = try readColumn(stmt, @intCast(col_idx), f.type, allocator);
                }
                try list.append(allocator, item);
            }

            return list.toOwnedSlice(allocator);
        }

        /// Find a single record by primary key id
        pub fn find(self: Self, id: anytype, allocator: std.mem.Allocator) !?T {
            const sql = "SELECT " ++ column_list ++ " FROM " ++ table_name ++ " WHERE id = ? LIMIT 1;";

            self.db.acquireLock();
            defer self.db.releaseLock();

            var stmt: ?*c.sqlite3_stmt = null;
            if (c.sqlite3_prepare_v2(self.db.handle, sql.ptr, @intCast(sql.len), &stmt, null) != c.SQLITE_OK) {
                return error.PrepareFailed;
            }
            defer _ = c.sqlite3_finalize(stmt);

            try bindValue(stmt, 1, id);

            if (c.sqlite3_step(stmt) == c.SQLITE_ROW) {
                var item: T = undefined;
                inline for (@typeInfo(T).@"struct".fields, 0..) |f, col_idx| {
                    @field(item, f.name) = try readColumn(stmt, @intCast(col_idx), f.type, allocator);
                }
                return item;
            }

            return null;
        }

        /// Delete a record by primary key id
        pub fn delete(self: Self, id: anytype) !void {
            const sql = "DELETE FROM " ++ table_name ++ " WHERE id = ?;";

            self.db.acquireLock();
            defer self.db.releaseLock();

            var stmt: ?*c.sqlite3_stmt = null;
            if (c.sqlite3_prepare_v2(self.db.handle, sql.ptr, @intCast(sql.len), &stmt, null) != c.SQLITE_OK) {
                return error.PrepareFailed;
            }
            defer _ = c.sqlite3_finalize(stmt);

            try bindValue(stmt, 1, id);

            if (c.sqlite3_step(stmt) != c.SQLITE_DONE) {
                return error.StepFailed;
            }
        }

        /// Query with custom WHERE condition: .where("status = ?", .{"active"})
        pub fn where(self: Self, comptime clause: []const u8, args: anytype) FilteredQuery(T, clause, @TypeOf(args)) {
            return FilteredQuery(T, clause, @TypeOf(args)).init(self.db, args);
        }
    };
}

/// Sub-query builder with WHERE clause
pub fn FilteredQuery(comptime T: type, comptime clause: []const u8, comptime ArgsType: type) type {
    return struct {
        const Self = @This();

        db: *Database,
        args: ArgsType,

        pub fn init(db: *Database, args: ArgsType) Self {
            return .{ .db = db, .args = args };
        }

        fn bindArgs(stmt: ?*c.sqlite3_stmt, args: ArgsType) !void {
            const args_info = @typeInfo(ArgsType);
            switch (args_info) {
                .@"struct" => |s| {
                    inline for (s.fields, 1..) |field, idx| {
                        const val = @field(args, field.name);
                        try bindValue(stmt, @intCast(idx), val);
                    }
                },
                else => {
                    try bindValue(stmt, 1, args);
                },
            }
        }

        pub fn count(self: Self) !i64 {
            const sql = "SELECT COUNT(*) FROM " ++ ModelQuery(T).table_name ++ " WHERE " ++ clause ++ ";";

            self.db.acquireLock();
            defer self.db.releaseLock();

            var stmt: ?*c.sqlite3_stmt = null;
            if (c.sqlite3_prepare_v2(self.db.handle, sql.ptr, @intCast(sql.len), &stmt, null) != c.SQLITE_OK) {
                return error.PrepareFailed;
            }
            defer _ = c.sqlite3_finalize(stmt);

            try bindArgs(stmt, self.args);

            if (c.sqlite3_step(stmt) == c.SQLITE_ROW) {
                return c.sqlite3_column_int64(stmt, 0);
            }
            return 0;
        }

        pub fn all(self: Self, allocator: std.mem.Allocator) ![]T {
            const sql = "SELECT " ++ ModelQuery(T).column_list ++ " FROM " ++ ModelQuery(T).table_name ++ " WHERE " ++ clause ++ ";";

            self.db.acquireLock();
            defer self.db.releaseLock();

            var stmt: ?*c.sqlite3_stmt = null;
            if (c.sqlite3_prepare_v2(self.db.handle, sql.ptr, @intCast(sql.len), &stmt, null) != c.SQLITE_OK) {
                return error.PrepareFailed;
            }
            defer _ = c.sqlite3_finalize(stmt);

            try bindArgs(stmt, self.args);

            var list: std.ArrayList(T) = .empty;
            defer list.deinit(allocator);

            while (c.sqlite3_step(stmt) == c.SQLITE_ROW) {
                var item: T = undefined;
                inline for (@typeInfo(T).@"struct".fields, 0..) |f, col_idx| {
                    @field(item, f.name) = try readColumn(stmt, @intCast(col_idx), f.type, allocator);
                }
                try list.append(allocator, item);
            }

            return list.toOwnedSlice(allocator);
        }

        pub fn first(self: Self, allocator: std.mem.Allocator) !?T {
            const sql = "SELECT " ++ ModelQuery(T).column_list ++ " FROM " ++ ModelQuery(T).table_name ++ " WHERE " ++ clause ++ " LIMIT 1;";

            self.db.acquireLock();
            defer self.db.releaseLock();

            var stmt: ?*c.sqlite3_stmt = null;
            if (c.sqlite3_prepare_v2(self.db.handle, sql.ptr, @intCast(sql.len), &stmt, null) != c.SQLITE_OK) {
                return error.PrepareFailed;
            }
            defer _ = c.sqlite3_finalize(stmt);

            try bindArgs(stmt, self.args);

            if (c.sqlite3_step(stmt) == c.SQLITE_ROW) {
                var item: T = undefined;
                inline for (@typeInfo(T).@"struct".fields, 0..) |f, col_idx| {
                    @field(item, f.name) = try readColumn(stmt, @intCast(col_idx), f.type, allocator);
                }
                return item;
            }

            return null;
        }
    };
}

test "ModelQuery compile-time DDL and SQL generation" {
    const User = struct {
        id: ?i64 = null,
        username: []const u8,
        email: ?[]const u8 = null,
        is_active: bool = true,
        created_at: ?[]const u8 = null,

        pub const table_name = "users";
    };

    const ddl = ModelQuery(User).create_table_sql;
    try std.testing.expect(std.mem.indexOf(u8, ddl, "CREATE TABLE IF NOT EXISTS users") != null);
    try std.testing.expect(std.mem.indexOf(u8, ddl, "id INTEGER PRIMARY KEY AUTOINCREMENT") != null);
    try std.testing.expect(std.mem.indexOf(u8, ddl, "username TEXT NOT NULL") != null);
    try std.testing.expect(std.mem.indexOf(u8, ddl, "email TEXT") != null);

    const cols = ModelQuery(User).column_list;
    try std.testing.expectEqualStrings("id, username, email, is_active, created_at", cols);

    const insert_sql = ModelQuery(User).insertSql(struct { username: []const u8, is_active: bool });
    try std.testing.expect(std.mem.indexOf(u8, insert_sql, "INSERT INTO users (username, is_active) VALUES (?, ?);") != null);
}

test "ModelQuery SQLite CRUD operations" {
    const allocator = std.testing.allocator;

    var db = try Database.init(":memory:");
    defer db.deinit();

    const Product = struct {
        id: ?i64 = null,
        name: []const u8,
        price: f64,
        is_available: bool = true,

        pub const table_name = "products";
    };

    // 1. Create Table automatically from struct
    try db.from(Product).createTableIfNotExists();

    // 2. Count should be 0 initially
    try std.testing.expectEqual(@as(i64, 0), try db.from(Product).count());

    // 3. Insert records
    const id1 = try db.from(Product).insert(.{
        .name = "Laptop",
        .price = 1250.50,
        .is_available = true,
    });
    try std.testing.expectEqual(@as(i64, 1), id1);

    const id2 = try db.from(Product).insert(.{
        .name = "Mouse",
        .price = 25.00,
        .is_available = false,
    });
    try std.testing.expectEqual(@as(i64, 2), id2);

    // 4. Count should now be 2
    try std.testing.expectEqual(@as(i64, 2), try db.from(Product).count());

    // 5. Fetch all records mapped to struct
    const all_products = try db.from(Product).all(allocator);
    defer allocator.free(all_products);
    defer for (all_products) |p| allocator.free(p.name);

    try std.testing.expectEqual(@as(usize, 2), all_products.len);
    try std.testing.expectEqualStrings("Laptop", all_products[0].name);
    try std.testing.expectEqual(@as(f64, 1250.50), all_products[0].price);
    try std.testing.expectEqual(true, all_products[0].is_available);

    // 6. Find by ID
    const found = try db.from(Product).find(2, allocator);
    try std.testing.expect(found != null);
    defer allocator.free(found.?.name);
    try std.testing.expectEqualStrings("Mouse", found.?.name);
    try std.testing.expectEqual(false, found.?.is_available);

    // 7. WHERE filter query
    const active_count = try db.from(Product).where("is_available = ?", .{1}).count();
    try std.testing.expectEqual(@as(i64, 1), active_count);

    const first_active = try db.from(Product).where("name = ?", .{"Laptop"}).first(allocator);
    try std.testing.expect(first_active != null);
    defer allocator.free(first_active.?.name);
    try std.testing.expectEqualStrings("Laptop", first_active.?.name);

    // 8. Delete by ID
    try db.from(Product).delete(1);
    try std.testing.expectEqual(@as(i64, 1), try db.from(Product).count());
}
