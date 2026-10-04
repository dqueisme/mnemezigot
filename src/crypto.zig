const std = @import("std");

/// Password Hashing, Token Signing (JWT / HMAC) & Crypto Helper Module using std.crypto
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

    /// Sign a payload string with a secret key using HMAC-SHA256 ("payload.hex_signature")
    pub fn signToken(allocator: std.mem.Allocator, payload: []const u8, secret: []const u8) ![]const u8 {
        var mac: [32]u8 = undefined;
        std.crypto.auth.hmac.sha2.HmacSha256.create(&mac, payload, secret);

        var hex_sig_buf: [64]u8 = undefined;
        const hex_sig = std.fmt.bufPrint(&hex_sig_buf, "{s}", .{std.fmt.fmtSliceHexLower(&mac)}) catch unreachable;

        return try std.fmt.allocPrint(allocator, "{s}.{s}", .{ payload, hex_sig });
    }

    /// Verify a signed token ("payload.hex_signature") and return the payload if valid
    pub fn verifyToken(token: []const u8, secret: []const u8) ?[]const u8 {
        const dot_idx = std.mem.lastIndexOfScalar(u8, token, '.') orelse return null;
        const payload = token[0..dot_idx];
        const hex_sig = token[dot_idx + 1 ..];

        if (hex_sig.len != 64) return null;

        var expected_mac: [32]u8 = undefined;
        _ = std.fmt.hexToBytes(&expected_mac, hex_sig) catch return null;

        var actual_mac: [32]u8 = undefined;
        std.crypto.auth.hmac.sha2.HmacSha256.create(&actual_mac, payload, secret);

        if (std.crypto.utils.timingSafeEql([32]u8, expected_mac, actual_mac)) {
            return payload;
        }

        return null;
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

test "Token signing and verification" {
    const allocator = std.testing.allocator;
    const secret = "my-jwt-secret-key";
    const payload = "user_id=1001;role=admin";

    const token = try crypto.signToken(allocator, payload, secret);
    defer allocator.free(token);

    const verified = crypto.verifyToken(token, secret);
    try std.testing.expect(verified != null);
    try std.testing.expectEqualStrings(payload, verified.?);

    try std.testing.expect(crypto.verifyToken(token, "wrong-secret") == null);
}
