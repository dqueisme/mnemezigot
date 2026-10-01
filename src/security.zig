const std = @import("std");

const base32_chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567";

/// RFC 6238 TOTP 2FA Module (Google Authenticator / Authy compatible)
pub const totp = struct {
    /// Generate a random 16-character Base32 secret key
    pub fn generateSecret(allocator: std.mem.Allocator) ![]const u8 {
        var bytes: [10]u8 = undefined;
        std.crypto.random.bytes(&bytes);

        var buf: std.ArrayList(u8) = .empty;
        defer buf.deinit(allocator);

        var bit_buf: u32 = 0;
        var bit_count: usize = 0;

        for (bytes) |b| {
            bit_buf = (bit_buf << 8) | b;
            bit_count += 8;
            while (bit_count >= 5) {
                bit_count -= 5;
                const idx = (bit_buf >> @intCast(bit_count)) & 0x1F;
                try buf.append(allocator, base32_chars[idx]);
            }
        }
        if (bit_count > 0) {
            const idx = (bit_buf << @intCast(5 - bit_count)) & 0x1F;
            try buf.append(allocator, base32_chars[idx]);
        }

        return buf.toOwnedSlice(allocator);
    }

    /// Construct otpauth:// URI for QR code generation
    pub fn getOtpAuthUri(allocator: std.mem.Allocator, issuer: []const u8, account_name: []const u8, secret: []const u8) ![]const u8 {
        return try std.fmt.allocPrint(allocator, "otpauth://totp/{s}:{s}?secret={s}&issuer={s}&digits=6&period=30", .{
            issuer,
            account_name,
            secret,
            issuer,
        });
    }

    /// Decode Base32 string to bytes
    fn decodeBase32(secret: []const u8, out_buf: []u8) !usize {
        var bit_buf: u32 = 0;
        var bit_count: usize = 0;
        var out_idx: usize = 0;

        for (secret) |ch| {
            const char_upper = std.ascii.toUpper(ch);
            if (char_upper == '=') continue;
            const val: u32 = blk: {
                for (base32_chars, 0..) |c, i| {
                    if (c == char_upper) break :blk @intCast(i);
                }
                return error.InvalidBase32Char;
            };

            bit_buf = (bit_buf << 5) | val;
            bit_count += 5;

            if (bit_count >= 8) {
                bit_count -= 8;
                if (out_idx < out_buf.len) {
                    out_buf[out_idx] = @intCast((bit_buf >> @intCast(bit_count)) & 0xFF);
                    out_idx += 1;
                }
            }
        }

        return out_idx;
    }

    /// Compute 6-digit TOTP code for a given timestamp
    pub fn generateCode(secret: []const u8, timestamp: i64) !u32 {
        var key_buf: [32]u8 = undefined;
        const key_len = try decodeBase32(secret, &key_buf);
        const key = key_buf[0..key_len];

        const counter: u64 = @intCast(@divTrunc(timestamp, 30));
        var msg: [8]u8 = undefined;
        std.mem.writeInt(u64, &msg, counter, .big);

        var mac: [20]u8 = undefined;
        std.crypto.auth.hmac.sha1.HmacSha1.create(&mac, &msg, key);

        const offset: usize = mac[19] & 0x0F;
        const truncated: u32 = ((@as(u32, mac[offset] & 0x7F) << 24) |
            (@as(u32, mac[offset + 1]) << 16) |
            (@as(u32, mac[offset + 2]) << 8) |
            @as(u32, mac[offset + 3]));

        return truncated % 1000000;
    }

    /// Verify 6-digit TOTP code with +/- 1 period (30s) drift tolerance
    pub fn verifyCode(secret: []const u8, user_code: u32, timestamp: i64) bool {
        const intervals = [_]i64{ 0, -30, 30 };
        for (intervals) |delta| {
            const code = generateCode(secret, timestamp + delta) catch continue;
            if (code == user_code) return true;
        }
        return false;
    }
};

test "TOTP Secret Generation, URI, and Code Verification" {
    const allocator = std.testing.allocator;

    const secret = try totp.generateSecret(allocator);
    defer allocator.free(secret);

    try std.testing.expect(secret.len > 0);

    const uri = try totp.getOtpAuthUri(allocator, "MnemezigotApp", "user@test.com", secret);
    defer allocator.free(uri);

    try std.testing.expect(std.mem.indexOf(u8, uri, "otpauth://totp/") != null);

    const now = std.time.timestamp();
    const current_code = try totp.generateCode(secret, now);

    try std.testing.expect(totp.verifyCode(secret, current_code, now));
    try std.testing.expect(!totp.verifyCode(secret, 999999, now));
}
