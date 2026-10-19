const std = @import("std");
const style_mod = @import("style.zig");
const Color = style_mod.Color;
const Style = style_mod.Style;
const Allocator = std.mem.Allocator;

// --- Unicode Width Tables & Functions (Ported & adapted from zigtui) ---

const Range = struct { lo: u21, hi: u21 };

const zero_width = [_]Range{
    .{ .lo = 0x0300, .hi = 0x036F },
    .{ .lo = 0x0483, .hi = 0x0489 },
    .{ .lo = 0x0591, .hi = 0x05BD },
    .{ .lo = 0x05BF, .hi = 0x05BF },
    .{ .lo = 0x05C1, .hi = 0x05C2 },
    .{ .lo = 0x05C4, .hi = 0x05C5 },
    .{ .lo = 0x05C7, .hi = 0x05C7 },
    .{ .lo = 0x0610, .hi = 0x061A },
    .{ .lo = 0x064B, .hi = 0x065F },
    .{ .lo = 0x0670, .hi = 0x0670 },
    .{ .lo = 0x06D6, .hi = 0x06DC },
    .{ .lo = 0x06DF, .hi = 0x06E4 },
    .{ .lo = 0x06E7, .hi = 0x06E8 },
    .{ .lo = 0x06EA, .hi = 0x06ED },
    .{ .lo = 0x0711, .hi = 0x0711 },
    .{ .lo = 0x0730, .hi = 0x074A },
    .{ .lo = 0x07A6, .hi = 0x07B0 },
    .{ .lo = 0x07EB, .hi = 0x07F3 },
    .{ .lo = 0x0816, .hi = 0x0819 },
    .{ .lo = 0x081B, .hi = 0x0823 },
    .{ .lo = 0x0825, .hi = 0x0827 },
    .{ .lo = 0x0829, .hi = 0x082D },
    .{ .lo = 0x0900, .hi = 0x0902 },
    .{ .lo = 0x093A, .hi = 0x093A },
    .{ .lo = 0x093C, .hi = 0x093C },
    .{ .lo = 0x0941, .hi = 0x0948 },
    .{ .lo = 0x094D, .hi = 0x094D },
    .{ .lo = 0x0951, .hi = 0x0957 },
    .{ .lo = 0x0962, .hi = 0x0963 },
    .{ .lo = 0x0981, .hi = 0x0981 },
    .{ .lo = 0x09BC, .hi = 0x09BC },
    .{ .lo = 0x09C1, .hi = 0x09C4 },
    .{ .lo = 0x09CD, .hi = 0x09CD },
    .{ .lo = 0x0A01, .hi = 0x0A02 },
    .{ .lo = 0x0A3C, .hi = 0x0A3C },
    .{ .lo = 0x0A41, .hi = 0x0A42 },
    .{ .lo = 0x0A47, .hi = 0x0A48 },
    .{ .lo = 0x0A4B, .hi = 0x0A4D },
    .{ .lo = 0x0A81, .hi = 0x0A82 },
    .{ .lo = 0x0ABC, .hi = 0x0ABC },
    .{ .lo = 0x0AC1, .hi = 0x0AC5 },
    .{ .lo = 0x0AC7, .hi = 0x0AC8 },
    .{ .lo = 0x0ACD, .hi = 0x0ACD },
    .{ .lo = 0x0B01, .hi = 0x0B01 },
    .{ .lo = 0x0B3C, .hi = 0x0B3C },
    .{ .lo = 0x0B3F, .hi = 0x0B3F },
    .{ .lo = 0x0B41, .hi = 0x0B44 },
    .{ .lo = 0x0B4D, .hi = 0x0B4D },
    .{ .lo = 0x0BC0, .hi = 0x0BC0 },
    .{ .lo = 0x0BCD, .hi = 0x0BCD },
    .{ .lo = 0x0C3E, .hi = 0x0C40 },
    .{ .lo = 0x0C46, .hi = 0x0C48 },
    .{ .lo = 0x0C4A, .hi = 0x0C4D },
    .{ .lo = 0x0CBC, .hi = 0x0CBC },
    .{ .lo = 0x0CCC, .hi = 0x0CCD },
    .{ .lo = 0x0D41, .hi = 0x0D44 },
    .{ .lo = 0x0D4D, .hi = 0x0D4D },
    .{ .lo = 0x0DCA, .hi = 0x0DCA },
    .{ .lo = 0x0E31, .hi = 0x0E31 },
    .{ .lo = 0x0E34, .hi = 0x0E3A },
    .{ .lo = 0x0E47, .hi = 0x0E4E },
    .{ .lo = 0x0EB1, .hi = 0x0EB1 },
    .{ .lo = 0x0EB4, .hi = 0x0EBC },
    .{ .lo = 0x0EC8, .hi = 0x0ECD },
    .{ .lo = 0x0F35, .hi = 0x0F35 },
    .{ .lo = 0x0F37, .hi = 0x0F37 },
    .{ .lo = 0x0F39, .hi = 0x0F39 },
    .{ .lo = 0x0F71, .hi = 0x0F7E },
    .{ .lo = 0x0F80, .hi = 0x0F84 },
    .{ .lo = 0x0F86, .hi = 0x0F87 },
    .{ .lo = 0x0FC6, .hi = 0x0FC6 },
    .{ .lo = 0x102D, .hi = 0x1030 },
    .{ .lo = 0x1032, .hi = 0x1037 },
    .{ .lo = 0x1039, .hi = 0x103A },
    .{ .lo = 0x1058, .hi = 0x1059 },
    .{ .lo = 0x135F, .hi = 0x135F },
    .{ .lo = 0x1712, .hi = 0x1714 },
    .{ .lo = 0x1732, .hi = 0x1734 },
    .{ .lo = 0x1752, .hi = 0x1753 },
    .{ .lo = 0x1772, .hi = 0x1773 },
    .{ .lo = 0x17B4, .hi = 0x17B5 },
    .{ .lo = 0x17B7, .hi = 0x17BD },
    .{ .lo = 0x17C6, .hi = 0x17C6 },
    .{ .lo = 0x17C9, .hi = 0x17D3 },
    .{ .lo = 0x17DD, .hi = 0x17DD },
    .{ .lo = 0x180B, .hi = 0x180E },
    .{ .lo = 0x18A9, .hi = 0x18A9 },
    .{ .lo = 0x1920, .hi = 0x1922 },
    .{ .lo = 0x1927, .hi = 0x1928 },
    .{ .lo = 0x1932, .hi = 0x1932 },
    .{ .lo = 0x1939, .hi = 0x193B },
    .{ .lo = 0x1A17, .hi = 0x1A18 },
    .{ .lo = 0x1AB0, .hi = 0x1AFF },
    .{ .lo = 0x1B00, .hi = 0x1B03 },
    .{ .lo = 0x1B34, .hi = 0x1B34 },
    .{ .lo = 0x1B36, .hi = 0x1B3A },
    .{ .lo = 0x1B3C, .hi = 0x1B3C },
    .{ .lo = 0x1B42, .hi = 0x1B42 },
    .{ .lo = 0x1B6B, .hi = 0x1B73 },
    .{ .lo = 0x1DC0, .hi = 0x1DFF },
    .{ .lo = 0x200B, .hi = 0x200F },
    .{ .lo = 0x202A, .hi = 0x202E },
    .{ .lo = 0x2060, .hi = 0x2064 },
    .{ .lo = 0x206A, .hi = 0x206F },
    .{ .lo = 0x20D0, .hi = 0x20F0 },
    .{ .lo = 0x2CEF, .hi = 0x2CF1 },
    .{ .lo = 0x302A, .hi = 0x302F },
    .{ .lo = 0x3099, .hi = 0x309A },
    .{ .lo = 0xA806, .hi = 0xA806 },
    .{ .lo = 0xA80B, .hi = 0xA80B },
    .{ .lo = 0xA825, .hi = 0xA826 },
    .{ .lo = 0xFB1E, .hi = 0xFB1E },
    .{ .lo = 0xFE00, .hi = 0xFE0F },
    .{ .lo = 0xFE20, .hi = 0xFE2F },
    .{ .lo = 0xFEFF, .hi = 0xFEFF },
    .{ .lo = 0xFFF9, .hi = 0xFFFB },
    .{ .lo = 0x101FD, .hi = 0x101FD },
    .{ .lo = 0x10A01, .hi = 0x10A03 },
    .{ .lo = 0x10A0F, .hi = 0x10A0F },
    .{ .lo = 0x10A38, .hi = 0x10A3A },
    .{ .lo = 0x10A3F, .hi = 0x10A3F },
    .{ .lo = 0x11080, .hi = 0x11081 },
    .{ .lo = 0x110B3, .hi = 0x110B6 },
    .{ .lo = 0x110B9, .hi = 0x110BA },
    .{ .lo = 0x1D167, .hi = 0x1D169 },
    .{ .lo = 0x1D17B, .hi = 0x1D182 },
    .{ .lo = 0x1D185, .hi = 0x1D18B },
    .{ .lo = 0x1D1AA, .hi = 0x1D1AD },
    .{ .lo = 0x1D242, .hi = 0x1D244 },
    .{ .lo = 0xE0001, .hi = 0xE0001 },
    .{ .lo = 0xE0020, .hi = 0xE007F },
    .{ .lo = 0xE0100, .hi = 0xE01EF },
};

const wide = [_]Range{
    .{ .lo = 0x1100, .hi = 0x115F },
    .{ .lo = 0x231A, .hi = 0x231B },
    .{ .lo = 0x2329, .hi = 0x232A },
    .{ .lo = 0x23E9, .hi = 0x23EC },
    .{ .lo = 0x23F0, .hi = 0x23F0 },
    .{ .lo = 0x23F3, .hi = 0x23F3 },
    .{ .lo = 0x25FD, .hi = 0x25FE },
    .{ .lo = 0x2614, .hi = 0x2615 },
    .{ .lo = 0x2648, .hi = 0x2653 },
    .{ .lo = 0x267F, .hi = 0x267F },
    .{ .lo = 0x2693, .hi = 0x2693 },
    .{ .lo = 0x26A1, .hi = 0x26A1 },
    .{ .lo = 0x26AA, .hi = 0x26AB },
    .{ .lo = 0x26BD, .hi = 0x26BE },
    .{ .lo = 0x26C4, .hi = 0x26C5 },
    .{ .lo = 0x26CE, .hi = 0x26CE },
    .{ .lo = 0x26D4, .hi = 0x26D4 },
    .{ .lo = 0x26EA, .hi = 0x26EA },
    .{ .lo = 0x26F2, .hi = 0x26F3 },
    .{ .lo = 0x26F5, .hi = 0x26F5 },
    .{ .lo = 0x26FA, .hi = 0x26FA },
    .{ .lo = 0x26FD, .hi = 0x26FD },
    .{ .lo = 0x2705, .hi = 0x2705 },
    .{ .lo = 0x270A, .hi = 0x270B },
    .{ .lo = 0x2728, .hi = 0x2728 },
    .{ .lo = 0x274C, .hi = 0x274C },
    .{ .lo = 0x274E, .hi = 0x274E },
    .{ .lo = 0x2753, .hi = 0x2755 },
    .{ .lo = 0x2757, .hi = 0x2757 },
    .{ .lo = 0x2795, .hi = 0x2797 },
    .{ .lo = 0x27B0, .hi = 0x27B0 },
    .{ .lo = 0x27BF, .hi = 0x27BF },
    .{ .lo = 0x2B1B, .hi = 0x2B1C },
    .{ .lo = 0x2B50, .hi = 0x2B50 },
    .{ .lo = 0x2B55, .hi = 0x2B55 },
    .{ .lo = 0x2E80, .hi = 0x2E99 },
    .{ .lo = 0x2E9B, .hi = 0x2EF3 },
    .{ .lo = 0x2F00, .hi = 0x2FD5 },
    .{ .lo = 0x2FF0, .hi = 0x2FFB },
    .{ .lo = 0x3000, .hi = 0x303E },
    .{ .lo = 0x3041, .hi = 0x3096 },
    .{ .lo = 0x3099, .hi = 0x30FF },
    .{ .lo = 0x3105, .hi = 0x312F },
    .{ .lo = 0x3131, .hi = 0x318E },
    .{ .lo = 0x3190, .hi = 0x31E5 },
    .{ .lo = 0x31EF, .hi = 0x321E },
    .{ .lo = 0x3220, .hi = 0x3247 },
    .{ .lo = 0x3250, .hi = 0xA48C },
    .{ .lo = 0xA490, .hi = 0xA4C6 },
    .{ .lo = 0xA960, .hi = 0xA97C },
    .{ .lo = 0xAC00, .hi = 0xD7A3 },
    .{ .lo = 0xF900, .hi = 0xFAFF },
    .{ .lo = 0xFE10, .hi = 0xFE19 },
    .{ .lo = 0xFE30, .hi = 0xFE52 },
    .{ .lo = 0xFE54, .hi = 0xFE66 },
    .{ .lo = 0xFE68, .hi = 0xFE6B },
    .{ .lo = 0xFF01, .hi = 0xFF60 },
    .{ .lo = 0xFFE0, .hi = 0xFFE6 },
    .{ .lo = 0x16FE0, .hi = 0x16FE4 },
    .{ .lo = 0x16FF0, .hi = 0x16FF1 },
    .{ .lo = 0x17000, .hi = 0x187F7 },
    .{ .lo = 0x18800, .hi = 0x18CD5 },
    .{ .lo = 0x18D00, .hi = 0x18D08 },
    .{ .lo = 0x1AFF0, .hi = 0x1AFFE },
    .{ .lo = 0x1B000, .hi = 0x1B152 },
    .{ .lo = 0x1B164, .hi = 0x1B167 },
    .{ .lo = 0x1B170, .hi = 0x1B2FB },
    .{ .lo = 0x1F004, .hi = 0x1F004 },
    .{ .lo = 0x1F0CF, .hi = 0x1F0CF },
    .{ .lo = 0x1F18E, .hi = 0x1F18E },
    .{ .lo = 0x1F191, .hi = 0x1F19A },
    .{ .lo = 0x1F200, .hi = 0x1F320 },
    .{ .lo = 0x1F32D, .hi = 0x1F335 },
    .{ .lo = 0x1F337, .hi = 0x1F37C },
    .{ .lo = 0x1F37E, .hi = 0x1F393 },
    .{ .lo = 0x1F3A0, .hi = 0x1F3CA },
    .{ .lo = 0x1F3CF, .hi = 0x1F3D3 },
    .{ .lo = 0x1F3E0, .hi = 0x1F3F0 },
    .{ .lo = 0x1F3F4, .hi = 0x1F3F4 },
    .{ .lo = 0x1F3F8, .hi = 0x1F43E },
    .{ .lo = 0x1F440, .hi = 0x1F440 },
    .{ .lo = 0x1F442, .hi = 0x1F4FC },
    .{ .lo = 0x1F4FF, .hi = 0x1F53D },
    .{ .lo = 0x1F54B, .hi = 0x1F54E },
    .{ .lo = 0x1F550, .hi = 0x1F567 },
    .{ .lo = 0x1F57A, .hi = 0x1F57A },
    .{ .lo = 0x1F595, .hi = 0x1F596 },
    .{ .lo = 0x1F5A4, .hi = 0x1F5A4 },
    .{ .lo = 0x1F5FB, .hi = 0x1F64F },
    .{ .lo = 0x1F680, .hi = 0x1F6C5 },
    .{ .lo = 0x1F6CC, .hi = 0x1F6CC },
    .{ .lo = 0x1F6D0, .hi = 0x1F6D2 },
    .{ .lo = 0x1F6D5, .hi = 0x1F6D7 },
    .{ .lo = 0x1F6EB, .hi = 0x1F6EC },
    .{ .lo = 0x1F6F4, .hi = 0x1F6FC },
    .{ .lo = 0x1F7E0, .hi = 0x1F7EB },
    .{ .lo = 0x1F90C, .hi = 0x1F93A },
    .{ .lo = 0x1F93C, .hi = 0x1F945 },
    .{ .lo = 0x1F947, .hi = 0x1F9FF },
    .{ .lo = 0x1FA70, .hi = 0x1FA74 },
    .{ .lo = 0x1FA78, .hi = 0x1FA7C },
    .{ .lo = 0x1FA80, .hi = 0x1FA86 },
    .{ .lo = 0x1FA90, .hi = 0x1FAAC },
    .{ .lo = 0x1FAB0, .hi = 0x1FABA },
    .{ .lo = 0x1FAC0, .hi = 0x1FAC5 },
    .{ .lo = 0x1FAD0, .hi = 0x1FAD9 },
    .{ .lo = 0x1FAE0, .hi = 0x1FAE7 },
    .{ .lo = 0x1FAF0, .hi = 0x1FAF6 },
    .{ .lo = 0x20000, .hi = 0x2FFFD },
    .{ .lo = 0x30000, .hi = 0x3FFFD },
};

fn inRanges(ranges: []const Range, cp: u21) bool {
    var lo: usize = 0;
    var hi: usize = ranges.len;
    while (lo < hi) {
        const mid = lo + (hi - lo) / 2;
        const r = ranges[mid];
        if (cp < r.lo) {
            hi = mid;
        } else if (cp > r.hi) {
            lo = mid + 1;
        } else {
            return true;
        }
    }
    return false;
}

pub fn codepointWidth(cp: u21) u2 {
    if (cp < 0x20 or (cp >= 0x7F and cp < 0xA0)) return 0;
    if (cp < 0x300) return 1;
    if (inRanges(&zero_width, cp)) return 0;
    if (inRanges(&wide, cp)) return 2;
    return 1;
}

pub const DecodedChar = struct { cp: u21, len: usize };

pub fn decodeCharAt(bytes: []const u8, index: usize) DecodedChar {
    const len = std.unicode.utf8ByteSequenceLength(bytes[index]) catch return .{ .cp = 0xFFFD, .len = 1 };
    if (index + len > bytes.len) return .{ .cp = 0xFFFD, .len = 1 };
    const cp = std.unicode.utf8Decode(bytes[index .. index + len]) catch return .{ .cp = 0xFFFD, .len = 1 };
    return .{ .cp = cp, .len = len };
}

pub fn stringWidth(bytes: []const u8) usize {
    var total: usize = 0;
    var i: usize = 0;
    while (i < bytes.len) {
        // Skip ANSI escape codes if present
        if (bytes[i] == 0x1b and i + 1 < bytes.len and bytes[i + 1] == '[') {
            i += 2;
            while (i < bytes.len and bytes[i] != 'm') : (i += 1) {}
            if (i < bytes.len and bytes[i] == 'm') i += 1;
            continue;
        }
        const d = decodeCharAt(bytes, i);
        total += codepointWidth(d.cp);
        i += d.len;
    }
    return total;
}

pub fn truncateToWidth(bytes: []const u8, max_columns: usize) []const u8 {
    var used: usize = 0;
    var end: usize = 0;
    var i: usize = 0;
    while (i < bytes.len) {
        const d = decodeCharAt(bytes, i);
        const w = codepointWidth(d.cp);
        if (used + w > max_columns) break;
        used += w;
        i += d.len;
        end = i;
    }
    return bytes[0..end];
}

// --- Rect Definition ---

pub const Rect = struct {
    x: u16 = 0,
    y: u16 = 0,
    width: u16 = 0,
    height: u16 = 0,

    pub fn area(self: Rect) u32 {
        return @as(u32, self.width) * @as(u32, self.height);
    }

    pub fn contains(self: Rect, px: u16, py: u16) bool {
        return px >= self.x and px < self.x + self.width and
            py >= self.y and py < self.y + self.height;
    }

    pub fn inner(self: Rect, margin: u16) Rect {
        const doubled = margin * 2;
        if (doubled > self.width or doubled > self.height) {
            return .{ .x = self.x, .y = self.y, .width = 0, .height = 0 };
        }
        return .{
            .x = self.x + margin,
            .y = self.y + margin,
            .width = self.width - doubled,
            .height = self.height - doubled,
        };
    }

    pub fn splitHorizontal(self: Rect, at: u16) struct { left: Rect, right: Rect } {
        const split_at = @min(at, self.width);
        return .{
            .left = .{ .x = self.x, .y = self.y, .width = split_at, .height = self.height },
            .right = .{
                .x = self.x + split_at,
                .y = self.y,
                .width = self.width - split_at,
                .height = self.height,
            },
        };
    }

    pub fn splitVertical(self: Rect, at: u16) struct { top: Rect, bottom: Rect } {
        const split_at = @min(at, self.height);
        return .{
            .top = .{ .x = self.x, .y = self.y, .width = self.width, .height = split_at },
            .bottom = .{
                .x = self.x,
                .y = self.y + split_at,
                .width = self.width,
                .height = self.height - split_at,
            },
        };
    }
};

// --- Cell Definition ---

pub const Cell = struct {
    char: u21 = ' ',
    fg: Color = .none,
    bg: Color = .none,
    modifier: Style = .{},
    /// Terminal columns this cell occupies. Zero marks the continuation column of a double-width cell.
    width: u2 = 1,

    pub fn eql(self: Cell, other: Cell) bool {
        return self.char == other.char and
            self.width == other.width and
            self.fg.eql(other.fg) and
            self.bg.eql(other.bg) and
            self.modifier.eql(other.modifier);
    }

    pub fn isContinuation(self: Cell) bool {
        return self.width == 0;
    }

    pub fn reset(self: *Cell) void {
        self.* = .{};
    }

    pub fn setChar(self: *Cell, char: u21) void {
        self.char = char;
        self.width = @max(codepointWidth(char), 1);
    }

    pub fn setStyle(self: *Cell, fg: Color, bg: Color, s: Style) void {
        self.fg = fg;
        self.bg = bg;
        self.modifier = s;
    }
};

// --- Buffer Definition ---

pub const Buffer = struct {
    width: u16,
    height: u16,
    cells: []Cell,
    allocator: Allocator,

    pub fn init(allocator: Allocator, width: u16, height: u16) !Buffer {
        const size = @as(usize, width) * @as(usize, height);
        const cells = try allocator.alloc(Cell, size);
        @memset(cells, Cell{});

        return Buffer{
            .width = width,
            .height = height,
            .cells = cells,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Buffer) void {
        self.allocator.free(self.cells);
    }

    pub fn getArea(self: Buffer) Rect {
        return .{ .x = 0, .y = 0, .width = self.width, .height = self.height };
    }

    pub fn clear(self: *Buffer) void {
        for (self.cells) |*cell| {
            cell.reset();
        }
    }

    pub fn resize(self: *Buffer, width: u16, height: u16) !void {
        if (width == self.width and height == self.height) return;

        const new_size = @as(usize, width) * @as(usize, height);
        const new_cells = try self.allocator.alloc(Cell, new_size);
        @memset(new_cells, Cell{});

        const min_width = @min(self.width, width);
        const min_height = @min(self.height, height);

        var y: u16 = 0;
        while (y < min_height) : (y += 1) {
            const old_offset = @as(usize, y) * @as(usize, self.width);
            const new_offset = @as(usize, y) * @as(usize, width);
            @memcpy(
                new_cells[new_offset .. new_offset + min_width],
                self.cells[old_offset .. old_offset + min_width],
            );
        }

        self.allocator.free(self.cells);
        self.cells = new_cells;
        self.width = width;
        self.height = height;
    }

    pub fn get(self: *Buffer, x: u16, y: u16) ?*Cell {
        if (x >= self.width or y >= self.height) return null;
        return self.at(x, y);
    }

    pub fn at(self: *Buffer, x: u16, y: u16) *Cell {
        return &self.cells[@as(usize, y) * @as(usize, self.width) + @as(usize, x)];
    }

    pub fn set(self: *Buffer, x: u16, y: u16, cell: Cell) void {
        if (self.get(x, y)) |c| {
            c.* = cell;
        }
    }

    /// Overwrite handling: blank double-width pair if partially overwritten
    pub fn breakPairAt(self: *Buffer, x: u16, y: u16) void {
        const cell = self.at(x, y);
        if (cell.isContinuation()) {
            if (x > 0) {
                const lead = self.at(x - 1, y);
                if (lead.width == 2) {
                    lead.char = ' ';
                    lead.width = 1;
                }
            }
            cell.char = ' ';
            cell.width = 1;
        } else if (cell.width == 2 and x + 1 < self.width) {
            const cont = self.at(x + 1, y);
            if (cont.isContinuation()) {
                cont.char = ' ';
                cont.width = 1;
            }
        }
    }

    pub fn setChar(self: *Buffer, x: u16, y: u16, char: u21, fg: Color, bg: Color, s: Style) void {
        if (x >= self.width or y >= self.height) return;

        const w = codepointWidth(char);
        if (w == 0) return;

        self.breakPairAt(x, y);

        if (w == 2 and x + 1 >= self.width) {
            const cell = self.at(x, y);
            cell.char = ' ';
            cell.width = 1;
            cell.setStyle(fg, bg, s);
            return;
        }
        if (w == 2) self.breakPairAt(x + 1, y);

        const lead = self.at(x, y);
        lead.char = char;
        lead.width = w;
        lead.setStyle(fg, bg, s);

        if (w == 2) {
            const cont = self.at(x + 1, y);
            cont.* = lead.*;
            cont.char = ' ';
            cont.width = 0;
        }
    }

    pub fn putString(self: *Buffer, x: u16, y: u16, str: []const u8, max_width: u16, fg: Color, bg: Color, s: Style) u16 {
        if (y >= self.height or x >= self.width) return 0;

        var col: u16 = 0;
        var i: usize = 0;
        while (i < str.len) {
            const d = decodeCharAt(str, i);
            i += d.len;
            const w = codepointWidth(d.cp);
            if (w == 0) continue;
            if (col + w > max_width) break;
            if (x + col + w > self.width) break;
            self.setChar(x + col, y, d.cp, fg, bg, s);
            col += w;
        }
        return col;
    }

    pub fn setString(self: *Buffer, x: u16, y: u16, str: []const u8, fg: Color, bg: Color, s: Style) void {
        _ = self.putString(x, y, str, self.width -| x, fg, bg, s);
    }

    pub fn setStringTruncated(self: *Buffer, x: u16, y: u16, str: []const u8, max_width: u16, fg: Color, bg: Color, s: Style) void {
        const room = @min(max_width, self.width -| x);
        if (room == 0) return;

        if (stringWidth(str) <= room) {
            _ = self.putString(x, y, str, room, fg, bg, s);
            return;
        }

        const kept = truncateToWidth(str, room - 1);
        const written = self.putString(x, y, kept, room - 1, fg, bg, s);
        self.setChar(x + written, y, '…', fg, bg, s);
    }

    pub fn fillArea(self: *Buffer, area_rect: Rect, char: u21, fg: Color, bg: Color, s: Style) void {
        var y = area_rect.y;
        while (y < area_rect.y + area_rect.height and y < self.height) : (y += 1) {
            var x = area_rect.x;
            while (x < area_rect.x + area_rect.width and x < self.width) : (x += 1) {
                self.setChar(x, y, char, fg, bg, s);
            }
        }
    }
};

// --- DoubleBuffer: Differential Terminal Renderer ---

pub const DoubleBuffer = struct {
    current: Buffer,
    next: Buffer,
    output: std.ArrayListUnmanaged(u8) = .empty,
    allocator: Allocator,

    pub fn init(allocator: Allocator, width: u16, height: u16) !DoubleBuffer {
        var current = try Buffer.init(allocator, width, height);
        errdefer current.deinit();

        var next = try Buffer.init(allocator, width, height);
        errdefer next.deinit();

        return DoubleBuffer{
            .current = current,
            .next = next,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *DoubleBuffer) void {
        self.output.deinit(self.allocator);
        self.current.deinit();
        self.next.deinit();
    }

    pub fn resize(self: *DoubleBuffer, width: u16, height: u16) !void {
        try self.current.resize(width, height);
        try self.next.resize(width, height);
    }

    pub fn getDrawBuffer(self: *DoubleBuffer) *Buffer {
        return &self.next;
    }

    const ArrayWriter = struct {
        list: *std.ArrayListUnmanaged(u8),
        alloc: Allocator,

        pub fn writeAll(self: @This(), bytes: []const u8) !void {
            try self.list.appendSlice(self.alloc, bytes);
        }

        pub fn print(self: @This(), comptime fmt: []const u8, args: anytype) !void {
            var buf: [1024]u8 = undefined;
            const s = try std.fmt.bufPrint(&buf, fmt, args);
            try self.list.appendSlice(self.alloc, s);
        }
    };

    /// Differential flush: compares `current` and `next`, emitting minimal cursor moves and ANSI styling
    pub fn flush(self: *DoubleBuffer, writer: anytype) !void {
        const full_redraw = self.current.width != self.next.width or self.current.height != self.next.height;
        if (full_redraw) {
            try self.current.resize(self.next.width, self.next.height);
        }

        self.output.clearRetainingCapacity();

        var last_fg: Color = .none;
        var last_bg: Color = .none;
        var last_mod: Style = .{};
        var style_known = false;
        var last_x: u16 = std.math.maxInt(u16);
        var last_y: u16 = std.math.maxInt(u16);

        var y: u16 = 0;
        while (y < self.next.height) : (y += 1) {
            var x: u16 = 0;
            while (x < self.next.width) {
                const cell = self.next.cells[@as(usize, y) * @as(usize, self.next.width) + @as(usize, x)];
                const advance: u16 = @max(cell.width, 1);

                if (cell.isContinuation()) {
                    x += 1;
                    continue;
                }

                if (!full_redraw and cell.eql(self.current.cells[@as(usize, y) * @as(usize, self.next.width) + @as(usize, x)])) {
                    x += advance;
                    continue;
                }

                // Move cursor if not immediately adjacent to previous cell
                if (x != last_x or y != last_y) {
                    var cursor_buf: [32]u8 = undefined;
                    const cursor_cmd = std.fmt.bufPrint(&cursor_buf, "\x1b[{d};{d}H", .{ y + 1, x + 1 }) catch unreachable;
                    try self.output.appendSlice(self.allocator, cursor_cmd);
                }

                // Emit ANSI styles if changed
                if (!style_known or !cell.fg.eql(last_fg) or !cell.bg.eql(last_bg) or !cell.modifier.eql(last_mod)) {
                    try self.output.appendSlice(self.allocator, "\x1b[0m");
                    const aw = ArrayWriter{ .list = &self.output, .alloc = self.allocator };
                    try cell.modifier.writeAnsi(aw);
                    try cell.fg.writeAnsi(aw, false);
                    try cell.bg.writeAnsi(aw, true);

                    last_fg = cell.fg;
                    last_bg = cell.bg;
                    last_mod = cell.modifier;
                    style_known = true;
                }

                // Emit character UTF-8 bytes
                var char_buf: [4]u8 = undefined;
                const char_len = std.unicode.utf8Encode(cell.char, &char_buf) catch 0;
                if (char_len > 0) {
                    try self.output.appendSlice(self.allocator, char_buf[0..char_len]);
                } else {
                    try self.output.append(self.allocator, ' ');
                }

                last_x = x + advance;
                last_y = y;
                x += advance;
            }
        }

        if (self.output.items.len == 0) return;

        // Reset styling at end of frame
        try self.output.appendSlice(self.allocator, "\x1b[0m");

        // Atomic write with terminal synchronized updates (\x1b[?2026h ... \x1b[?2026l)
        try writer.writeAll("\x1b[?2026h");
        try writer.writeAll(self.output.items);
        try writer.writeAll("\x1b[?2026l");

        // Copy new state into current state buffer
        @memcpy(self.current.cells, self.next.cells);
    }
};

test "Rect functions" {
    const r = Rect{ .x = 5, .y = 5, .width = 20, .height = 10 };
    try std.testing.expectEqual(@as(u32, 200), r.area());
    try std.testing.expect(r.contains(5, 5));
    try std.testing.expect(r.contains(24, 14));
    try std.testing.expect(!r.contains(25, 14));

    const inner_r = r.inner(2);
    try std.testing.expectEqual(@as(u16, 7), inner_r.x);
    try std.testing.expectEqual(@as(u16, 7), inner_r.y);
    try std.testing.expectEqual(@as(u16, 16), inner_r.width);
    try std.testing.expectEqual(@as(u16, 6), inner_r.height);

    const split_h = r.splitHorizontal(8);
    try std.testing.expectEqual(@as(u16, 8), split_h.left.width);
    try std.testing.expectEqual(@as(u16, 12), split_h.right.width);
    try std.testing.expectEqual(@as(u16, 13), split_h.right.x);
}

test "Buffer text and wide characters" {
    const allocator = std.testing.allocator;
    var buf = try Buffer.init(allocator, 20, 2);
    defer buf.deinit();

    buf.setString(0, 0, "Kanban 🚀", .cyan, .none, .{ .bold = true });
    try std.testing.expectEqual(@as(u21, 'K'), buf.get(0, 0).?.char);
    try std.testing.expectEqual(@as(u21, 0x1F680), buf.get(7, 0).?.char);
    try std.testing.expect(buf.get(8, 0).?.isContinuation());

    buf.setStringTruncated(0, 1, "Testing long text truncation", 10, .white, .none, .{});
    try std.testing.expectEqual(@as(u21, '…'), buf.get(9, 1).?.char);
}

test "DoubleBuffer differential flush" {
    const allocator = std.testing.allocator;
    var db = try DoubleBuffer.init(allocator, 10, 2);
    defer db.deinit();

    var draw_buf = db.getDrawBuffer();
    draw_buf.setString(0, 0, "Hello", .green, .none, .{});

    var out_list: std.ArrayList(u8) = .empty;
    defer out_list.deinit(allocator);
    const bw = style_mod.bufferWriter(allocator, &out_list);

    try db.flush(bw);
    try std.testing.expect(out_list.items.len > 0);
    try std.testing.expect(std.mem.indexOf(u8, out_list.items, "Hello") != null);

    // Second flush with no changes should produce empty output
    out_list.clearRetainingCapacity();
    try db.flush(bw);
    try std.testing.expectEqual(@as(usize, 0), out_list.items.len);
}
