const std = @import("std");
const render_mod = @import("render.zig");
pub const Rect = render_mod.Rect;
const Allocator = std.mem.Allocator;

/// Upper bound on constraints per layout, so `splitInto` can solve on the stack.
pub const max_constraints = 64;

pub const Constraint = union(enum) {
    /// Exactly n cells.
    fixed: u16,
    /// Exactly n cells. Alias of `fixed`.
    length: u16,
    /// A share of the full extent, not of what is left over.
    percentage: u8,
    /// A share of the full extent expressed as numerator/denominator.
    ratio: struct { numerator: u32, denominator: u32 },
    /// At least n cells; absorbs leftover space when no `fill` is present.
    min: u16,
    /// At most n cells; gives space back before any other kind.
    max: u16,
    /// Takes no space of its own, then splits whatever is left over in
    /// proportion to its weight against the other `fill` constraints.
    fill: u16,

    pub fn apply(self: Constraint, available: u16) u16 {
        return switch (self) {
            .fixed, .length, .min, .max => |n| @min(n, available),
            .percentage => |p| @intCast((@as(u32, available) * @min(p, 100)) / 100),
            .ratio => |r| if (r.denominator == 0)
                0
            else
                @intCast(@min(@as(u32, available), (@as(u32, available) * r.numerator) / r.denominator)),
            .fill => 0,
        };
    }

    fn tier(self: Constraint) Tier {
        return switch (self) {
            .fill => .fill,
            .max => .max,
            .ratio => .ratio,
            .percentage => .percentage,
            .fixed, .length => .length,
            .min => .min,
        };
    }
};

/// Order in which constraint kinds give space back when the requested total
/// exceeds the available extent. Earlier tiers are drained first.
const Tier = enum { fill, max, ratio, percentage, length, min };

pub const Direction = enum {
    horizontal,
    vertical,
};

pub const Margin = struct {
    left: u16 = 0,
    right: u16 = 0,
    top: u16 = 0,
    bottom: u16 = 0,

    pub const NONE = Margin{};
    pub const ALL_1 = Margin{ .left = 1, .right = 1, .top = 1, .bottom = 1 };
    pub const ALL_2 = Margin{ .left = 2, .right = 2, .top = 2, .bottom = 2 };

    pub fn apply(self: Margin, rect: Rect) Rect {
        const horizontal = self.left + self.right;
        const vertical = self.top + self.bottom;

        if (horizontal > rect.width or vertical > rect.height) {
            return .{ .x = rect.x, .y = rect.y, .width = 0, .height = 0 };
        }

        return .{
            .x = rect.x + self.left,
            .y = rect.y + self.top,
            .width = rect.width - horizontal,
            .height = rect.height - vertical,
        };
    }
};

pub const Alignment = enum {
    left,
    center,
    right,
};

pub const LayoutBuilder = struct {
    _direction: Direction = .vertical,
    _constraints: []const Constraint = &[_]Constraint{},
    _margin: Margin = .{},

    pub fn direction(self: LayoutBuilder, dir: Direction) LayoutBuilder {
        var copy = self;
        copy._direction = dir;
        return copy;
    }

    pub fn constraints(self: LayoutBuilder, cons: []const Constraint) LayoutBuilder {
        var copy = self;
        copy._constraints = cons;
        return copy;
    }

    pub fn margin(self: LayoutBuilder, m: u16) LayoutBuilder {
        var copy = self;
        copy._margin = Margin{ .left = m, .right = m, .top = m, .bottom = m };
        return copy;
    }

    pub fn split(self: LayoutBuilder, allocator: Allocator, area: Rect) ![]Rect {
        const layout = Layout{
            .direction = self._direction,
            .constraints = self._constraints,
            .margin = self._margin,
        };
        return layout.split(area, allocator);
    }
};

pub const Layout = struct {
    direction: Direction,
    constraints: []const Constraint,
    margin: Margin = .{},

    pub fn default() LayoutBuilder {
        return LayoutBuilder{};
    }

    pub fn split(self: Layout, area: Rect, allocator: Allocator) ![]Rect {
        const results = try allocator.alloc(Rect, self.constraints.len);
        errdefer allocator.free(results);
        return self.splitInto(area, results);
    }

    /// Solve into caller-provided storage without heap allocation.
    /// `out` must hold one `Rect` per constraint, up to `max_constraints`.
    pub fn splitInto(self: Layout, area: Rect, out: []Rect) []Rect {
        std.debug.assert(out.len == self.constraints.len);
        std.debug.assert(self.constraints.len <= max_constraints);

        if (self.constraints.len == 0) return out[0..0];

        const inner = self.margin.apply(area);
        if (inner.width == 0 or inner.height == 0) {
            @memset(out, Rect{ .x = inner.x, .y = inner.y, .width = 0, .height = 0 });
            return out;
        }

        const extent = switch (self.direction) {
            .horizontal => inner.width,
            .vertical => inner.height,
        };

        var sizes: [max_constraints]u16 = undefined;
        solve(self.constraints, extent, sizes[0..self.constraints.len]);

        var offset: u16 = 0;
        for (sizes[0..self.constraints.len], out) |size, *result| {
            result.* = switch (self.direction) {
                .horizontal => .{
                    .x = inner.x + offset,
                    .y = inner.y,
                    .width = size,
                    .height = inner.height,
                },
                .vertical => .{
                    .x = inner.x,
                    .y = inner.y + offset,
                    .width = inner.width,
                    .height = size,
                },
            };
            offset += size;
        }

        return out;
    }
};

const scale = 1_000_000;

/// Assign each constraint a size in cells such that sizes never exceed `extent`
/// and cover it exactly whenever constraints can stretch.
pub fn solve(constraints: []const Constraint, extent: u16, sizes: []u16) void {
    std.debug.assert(constraints.len == sizes.len);
    if (constraints.len == 0) return;

    var remainders: [max_constraints]u32 = undefined;
    var exact_total: u64 = 0;
    var floor_total: u32 = 0;

    for (constraints, 0..) |constraint, i| {
        const exact = exactSize(constraint, extent);
        exact_total += exact;
        sizes[i] = @intCast(@min(@as(u64, extent), exact / scale));
        remainders[i] = @intCast(exact % scale);
        floor_total += sizes[i];
    }

    const rounded_total: u32 = @intCast(@min(@as(u64, extent), (exact_total + scale / 2) / scale));
    if (rounded_total > floor_total) {
        handOut(rounded_total - floor_total, remainders[0..constraints.len], sizes, extent);
        floor_total = rounded_total;
    }

    if (floor_total > extent) {
        shrink(constraints, sizes, floor_total - extent);
    } else if (floor_total < extent) {
        grow(constraints, sizes, extent - floor_total);
    }
}

fn exactSize(constraint: Constraint, extent: u16) u64 {
    return switch (constraint) {
        .fixed, .length, .min, .max => |n| @as(u64, @min(n, extent)) * scale,
        .percentage => |p| @as(u64, extent) * @min(p, 100) * scale / 100,
        .ratio => |r| blk: {
            if (r.denominator == 0) break :blk 0;
            const num = @as(u64, extent) * r.numerator;
            const whole = num / r.denominator;
            if (whole >= extent) break :blk @as(u64, extent) * scale;
            break :blk whole * scale + (num % r.denominator) * scale / r.denominator;
        },
        .fill => 0,
    };
}

fn handOut(count: u32, remainders: []u32, sizes: []u16, cap: u16) void {
    var given: u32 = 0;
    while (given < count) : (given += 1) {
        var best: ?usize = null;
        for (remainders, 0..) |rem, i| {
            if (sizes[i] >= cap) continue;
            if (best == null or rem > remainders[best.?]) best = i;
        }
        const winner = best orelse return;
        if (remainders[winner] == 0) return;
        sizes[winner] += 1;
        remainders[winner] = 0;
    }
}

fn shrink(constraints: []const Constraint, sizes: []u16, amount: u32) void {
    var debt = amount;
    for (std.enums.values(Tier)) |tier| {
        if (debt == 0) return;
        var tier_total: u32 = 0;
        for (constraints, sizes) |constraint, size| {
            if (constraint.tier() == tier) tier_total += size;
        }
        if (tier_total == 0) continue;

        const take = @min(tier_total, debt);
        var taken: u32 = 0;
        for (constraints, sizes) |constraint, *size| {
            if (constraint.tier() != tier) continue;
            const share: u32 = @intCast(@as(u64, take) * size.* / tier_total);
            size.* -= @intCast(share);
            taken += share;
        }
        while (taken < take) {
            var best: ?usize = null;
            for (constraints, 0..) |constraint, i| {
                if (constraint.tier() != tier or sizes[i] == 0) continue;
                if (best == null or sizes[i] > sizes[best.?]) best = i;
            }
            const winner = best orelse break;
            sizes[winner] -= 1;
            taken += 1;
        }
        debt -= taken;
    }
}

fn grow(constraints: []const Constraint, sizes: []u16, amount: u32) void {
    var weight_total: u32 = 0;
    for (constraints) |constraint| {
        if (constraint == .fill) weight_total += @max(constraint.fill, 1);
    }

    if (weight_total == 0) {
        for (constraints) |constraint| {
            if (constraint == .min) weight_total += 1;
        }
        if (weight_total == 0) return;
    }

    const use_fill = for (constraints) |constraint| {
        if (constraint == .fill) break true;
    } else false;

    var given: u32 = 0;
    var remainders: [max_constraints]u32 = @splat(0);
    for (constraints, 0..) |constraint, i| {
        const weight: u32 = if (use_fill)
            (if (constraint == .fill) @max(constraint.fill, 1) else 0)
        else
            (if (constraint == .min) 1 else 0);
        if (weight == 0) continue;

        const numerator = @as(u64, amount) * weight;
        const share: u32 = @intCast(numerator / weight_total);
        sizes[i] += @intCast(share);
        remainders[i] = @intCast(numerator % weight_total);
        given += share;
    }

    handOut(amount - given, remainders[0..constraints.len], sizes, std.math.maxInt(u16));
}

// --- Centered Modal & Popup Utilities ---

/// Calculate a `Rect` centered within `area` with `percent_x` and `percent_y` of dimensions (clamped to 100)
pub fn centeredRectPct(area: Rect, percent_x: u8, percent_y: u8) Rect {
    const px = @min(percent_x, 100);
    const py = @min(percent_y, 100);
    const w: u16 = @intCast(@as(u32, area.width) * px / 100);
    const h: u16 = @intCast(@as(u32, area.height) * py / 100);
    return centeredRectFixed(area, w, h);
}

/// Calculate a `Rect` centered within `area` with exact `width` and `height` (clamped to area limits)
pub fn centeredRectFixed(area: Rect, width: u16, height: u16) Rect {
    const w = @min(width, area.width);
    const h = @min(height, area.height);
    return .{
        .x = area.x + (area.width - w) / 2,
        .y = area.y + (area.height - h) / 2,
        .width = w,
        .height = h,
    };
}

// --- Unit Tests ---

fn expectSizes(expected: []const u16, constraints: []const Constraint, extent: u16) !void {
    var sizes: [max_constraints]u16 = undefined;
    solve(constraints, extent, sizes[0..constraints.len]);
    try std.testing.expectEqualSlices(u16, expected, sizes[0..constraints.len]);
}

test "percentages are shares of full extent" {
    try expectSizes(&.{ 10, 50 }, &.{ .{ .fixed = 10 }, .{ .percentage = 50 } }, 100);
    try expectSizes(&.{ 25, 25, 50 }, &.{ .{ .percentage = 25 }, .{ .percentage = 25 }, .{ .percentage = 50 } }, 100);
}

test "fill splits leftover by weight" {
    try expectSizes(&.{ 10, 90 }, &.{ .{ .fixed = 10 }, .{ .fill = 1 } }, 100);
    try expectSizes(&.{ 10, 30, 60 }, &.{ .{ .fixed = 10 }, .{ .fill = 1 }, .{ .fill = 2 } }, 100);
    try expectSizes(&.{ 34, 33, 33 }, &.{ .{ .fill = 1 }, .{ .fill = 1 }, .{ .fill = 1 } }, 100);
}

test "splitInto stack-based without allocator" {
    const layout = Layout{
        .direction = .vertical,
        .constraints = &.{ .{ .fixed = 3 }, .{ .fill = 1 }, .{ .fixed = 1 } },
    };

    var storage: [3]Rect = undefined;
    const rows = layout.splitInto(.{ .x = 0, .y = 0, .width = 40, .height = 24 }, &storage);

    try std.testing.expectEqual(@as(u16, 3), rows[0].height);
    try std.testing.expectEqual(@as(u16, 20), rows[1].height);
    try std.testing.expectEqual(@as(u16, 1), rows[2].height);
    try std.testing.expectEqual(@as(u16, 24), rows[2].y + rows[2].height);
}

test "centeredRectPct calculation" {
    const area = Rect{ .x = 0, .y = 0, .width = 100, .height = 40 };
    const r = centeredRectPct(area, 60, 50);
    try std.testing.expectEqual(@as(u16, 60), r.width);
    try std.testing.expectEqual(@as(u16, 20), r.height);
    try std.testing.expectEqual(@as(u16, 20), r.x);
    try std.testing.expectEqual(@as(u16, 10), r.y);
}
