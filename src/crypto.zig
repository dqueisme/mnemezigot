const std = @import("std");

/// Password Hashing & Crypto Helper Module using std.crypto
pub const crypto = struct {
    /// Hash raw password using PBKDF2 HMAC-SHA256 with 64,000 iterations
    pub fn hashPassword(allocator: std.mem.Allocator, password: []const u8) ![]const u8 {
        var salt: [16]u8 = undefined;
        std.crypto.random.bytes(&salt);

        var out: [32]u8 = undefined;
        try std.crypto.pwhash.pbkdf2(&out, password, &salt, 64000, std.crypto.auth.hmac.sha2.HmacSha256);

        var hex_salt_buf: [32]u8 = undefined;
        const hex_salt = std.fmt.bufPrint(&hex_salt_buf, "{s}", .{std.fmt.fmtSliceHexLower(&salt)}) catch unreachable;

        var hex_hash_buf: [64]u8 = undefined;
        const hex_hash = std.fmt.bufPrint(&hex_hash_buf, "{s}", .{std.fmt.fmtSliceHexLower(&out)}) catch unreachable;

        return try std.fmt.allocPrint(allocator, "{s}${s}", .{ hex_salt, hex_hash });
    }

    /// Verify raw password against stored hash string ("salt_hex$hash_hex")
    pub fn verifyPassword(password: []const u8, stored_hash: []const u8) bool {
        const dollar_idx = std.mem.indexOfScalar(u8, stored_hash, '$') orelse return false;
        const salt_hex = stored_hash[0..dollar_idx];
        const hash_hex = stored_hash[dollar_idx + 1 ..];

        if (salt_hex.len != 32 or hash_hex.len != 64) return false;

        var salt: [16]u8 = undefined;
        _ = std.fmt.hexToBytes(&salt, salt_hex) catch return false;

        var expected_hash: [32]u8 = undefined;
        _ = std.fmt.hexToBytes(&expected_hash, hash_hex) catch return false;

        var actual_hash: [32]u8 = undefined;
        std.crypto.pwhash.pbkdf2(&actual_hash, password, &salt, 64000, std.crypto.auth.hmac.sha2.HmacSha256) catch return false;

        return std.crypto.utils.timingSafeEql([32]u8, expected_hash, actual_hash);
    }
};

test "Password hashing and verification" {
    const allocator = std.testing.allocator;
    const password = "SuperSecretPassword123!";

    const hashed = try crypto.hashPassword(allocator, password);
    defer allocator.free(hashed);

    try std.testing.expect(crypto.verifyPassword(password, hashed));
    try std.testing.expect(!crypto.verifyPassword("WrongPassword", hashed));
}
