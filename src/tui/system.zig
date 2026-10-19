const std = @import("std");
const builtin = @import("builtin");
const style = @import("style.zig");
const box = @import("box.zig");

// =============================================================================
// 1. MEMORY MONITORING
// =============================================================================

pub const SystemMemory = struct {
    app_rss_bytes: u64 = 0,
    sys_total_bytes: u64 = 0,
    sys_free_bytes: u64 = 0,
    sys_available_bytes: u64 = 0,
    sys_used_bytes: u64 = 0,
    swap_total_bytes: u64 = 0,
    swap_free_bytes: u64 = 0,
    swap_used_bytes: u64 = 0,

    /// Format bytes into compact string: e.g. "2.57M", "7.67G", "512K", "120B"
    pub fn formatCompact(bytes: u64, buf: []u8) []const u8 {
        if (bytes >= 1024 * 1024 * 1024) {
            const gb = @as(f64, @floatFromInt(bytes)) / (1024.0 * 1024.0 * 1024.0);
            return std.fmt.bufPrint(buf, "{d:.2}G", .{gb}) catch "0G";
        } else if (bytes >= 1024 * 1024) {
            const mb = @as(f64, @floatFromInt(bytes)) / (1024.0 * 1024.0);
            return std.fmt.bufPrint(buf, "{d:.2}M", .{mb}) catch "0M";
        } else if (bytes >= 1024) {
            const kb = @as(f64, @floatFromInt(bytes)) / 1024.0;
            return std.fmt.bufPrint(buf, "{d:.1}K", .{kb}) catch "0K";
        } else {
            return std.fmt.bufPrint(buf, "{d}B", .{bytes}) catch "0B";
        }
    }
};

fn parseKbLine(line: []const u8) u64 {
    const colon_idx = std.mem.indexOfScalar(u8, line, ':') orelse return 0;
    const rest = std.mem.trim(u8, line[colon_idx + 1 ..], " \t");
    var it = std.mem.splitScalar(u8, rest, ' ');
    const num_str = it.next() orelse return 0;
    const kb = std.fmt.parseInt(u64, num_str, 10) catch return 0;
    return kb * 1024;
}

/// Retrieve current Linux / WSL system memory and current process RSS
pub fn getSystemMemory() SystemMemory {
    var mem: SystemMemory = .{};
    if (builtin.os.tag != .linux) return mem;

    // 1. Process RSS from /proc/self/statm
    {
        const fd_res = std.os.linux.open("/proc/self/statm", std.os.linux.O{}, 0);
        const err = std.posix.errno(fd_res);
        if (err == .SUCCESS) {
            const raw_fd: std.os.linux.fd_t = @intCast(fd_res);
            defer _ = std.os.linux.close(raw_fd);
            var buf: [128]u8 = undefined;
            const read_res = std.os.linux.read(raw_fd, &buf, buf.len);
            if (std.posix.errno(read_res) == .SUCCESS) {
                const bytes_read: usize = @intCast(read_res);
                var it = std.mem.splitScalar(u8, buf[0..bytes_read], ' ');
                _ = it.next(); // skip total pages
                if (it.next()) |rss_str| {
                    if (std.fmt.parseInt(u64, rss_str, 10)) |pages| {
                        mem.app_rss_bytes = pages * 4096;
                    } else |_| {}
                }
            }
        }
    }

    // 2. System Memory from /proc/meminfo
    {
        const fd_res = std.os.linux.open("/proc/meminfo", std.os.linux.O{}, 0);
        const err = std.posix.errno(fd_res);
        if (err == .SUCCESS) {
            const raw_fd: std.os.linux.fd_t = @intCast(fd_res);
            defer _ = std.os.linux.close(raw_fd);
            var buf: [4096]u8 = undefined;
            const read_res = std.os.linux.read(raw_fd, &buf, buf.len);
            if (std.posix.errno(read_res) == .SUCCESS) {
                const bytes_read: usize = @intCast(read_res);
                var it = std.mem.splitScalar(u8, buf[0..bytes_read], '\n');
                while (it.next()) |line| {
                    if (std.mem.startsWith(u8, line, "MemTotal:")) {
                        mem.sys_total_bytes = parseKbLine(line);
                    } else if (std.mem.startsWith(u8, line, "MemFree:")) {
                        mem.sys_free_bytes = parseKbLine(line);
                    } else if (std.mem.startsWith(u8, line, "MemAvailable:")) {
                        mem.sys_available_bytes = parseKbLine(line);
                    } else if (std.mem.startsWith(u8, line, "SwapTotal:")) {
                        mem.swap_total_bytes = parseKbLine(line);
                    } else if (std.mem.startsWith(u8, line, "SwapFree:")) {
                        mem.swap_free_bytes = parseKbLine(line);
                    }
                }
            }
        }
    }

    if (mem.sys_total_bytes > mem.sys_available_bytes) {
        mem.sys_used_bytes = mem.sys_total_bytes - mem.sys_available_bytes;
    } else {
        mem.sys_used_bytes = 0;
    }

    if (mem.swap_total_bytes > mem.swap_free_bytes) {
        mem.swap_used_bytes = mem.swap_total_bytes - mem.swap_free_bytes;
    } else {
        mem.swap_used_bytes = 0;
    }

    return mem;
}

// =============================================================================
// 2. CPU SAMPLING & LOAD
// =============================================================================

pub const CpuSample = struct {
    user: u64 = 0,
    nice: u64 = 0,
    system: u64 = 0,
    idle: u64 = 0,
    iowait: u64 = 0,
    irq: u64 = 0,
    softirq: u64 = 0,
    steal: u64 = 0,

    pub fn total(self: CpuSample) u64 {
        return self.user + self.nice + self.system + self.idle + self.iowait + self.irq + self.softirq + self.steal;
    }

    pub fn idleTotal(self: CpuSample) u64 {
        return self.idle + self.iowait;
    }
};

pub const CpuUsage = struct {
    app_cpu_pct: f32 = 0.0,
    sys_cpu_pct: f32 = 0.0,
    num_cores: usize = 0,
    core_pcts: [64]f32 = [_]f32{0.0} ** 64,
};

fn readProcTicks() u64 {
    if (builtin.os.tag != .linux) return 0;
    const fd_res = std.os.linux.open("/proc/self/stat", std.os.linux.O{}, 0);
    const err = std.posix.errno(fd_res);
    if (err != .SUCCESS) return 0;
    const raw_fd: std.os.linux.fd_t = @intCast(fd_res);
    defer _ = std.os.linux.close(raw_fd);

    var buf: [1024]u8 = undefined;
    const read_res = std.os.linux.read(raw_fd, &buf, buf.len);
    if (std.posix.errno(read_res) != .SUCCESS) return 0;
    const bytes_read: usize = @intCast(read_res);
    const content = buf[0..bytes_read];

    const rparen = std.mem.lastIndexOfScalar(u8, content, ')') orelse return 0;
    if (rparen + 2 >= content.len) return 0;
    const rest = content[rparen + 2 ..];

    var it = std.mem.splitScalar(u8, rest, ' ');
    var idx: usize = 0;
    var utime: u64 = 0;
    var stime: u64 = 0;
    while (it.next()) |token| {
        if (token.len == 0) continue;
        if (idx == 11) { // 14th field in full stat
            utime = std.fmt.parseInt(u64, token, 10) catch 0;
        } else if (idx == 12) { // 15th field in full stat
            stime = std.fmt.parseInt(u64, token, 10) catch 0;
            break;
        }
        idx += 1;
    }
    return utime + stime;
}

fn parseCpuLine(line: []const u8) CpuSample {
    var sample: CpuSample = .{};
    var it = std.mem.splitScalar(u8, line, ' ');
    _ = it.next(); // skip 'cpu' or 'cpuX'

    var idx: usize = 0;
    while (it.next()) |tok| {
        if (tok.len == 0) continue;
        const val = std.fmt.parseInt(u64, tok, 10) catch 0;
        switch (idx) {
            0 => sample.user = val,
            1 => sample.nice = val,
            2 => sample.system = val,
            3 => sample.idle = val,
            4 => sample.iowait = val,
            5 => sample.irq = val,
            6 => sample.softirq = val,
            7 => sample.steal = val,
            else => {},
        }
        idx += 1;
        if (idx >= 8) break;
    }
    return sample;
}

fn readSysSample() CpuSample {
    if (builtin.os.tag != .linux) return .{};
    const fd_res = std.os.linux.open("/proc/stat", std.os.linux.O{}, 0);
    const err = std.posix.errno(fd_res);
    if (err != .SUCCESS) return .{};
    const raw_fd: std.os.linux.fd_t = @intCast(fd_res);
    defer _ = std.os.linux.close(raw_fd);

    var buf: [2048]u8 = undefined;
    const read_res = std.os.linux.read(raw_fd, &buf, buf.len);
    if (std.posix.errno(read_res) != .SUCCESS) return .{};
    const bytes_read: usize = @intCast(read_res);

    var it = std.mem.splitScalar(u8, buf[0..bytes_read], '\n');
    while (it.next()) |line| {
        if (std.mem.startsWith(u8, line, "cpu ")) {
            return parseCpuLine(line);
        }
    }
    return .{};
}

fn readAllCores(cores: *[64]CpuSample) usize {
    if (builtin.os.tag != .linux) return 0;
    const fd_res = std.os.linux.open("/proc/stat", std.os.linux.O{}, 0);
    const err = std.posix.errno(fd_res);
    if (err != .SUCCESS) return 0;
    const raw_fd: std.os.linux.fd_t = @intCast(fd_res);
    defer _ = std.os.linux.close(raw_fd);

    var buf: [8192]u8 = undefined;
    const read_res = std.os.linux.read(raw_fd, &buf, buf.len);
    if (std.posix.errno(read_res) != .SUCCESS) return 0;
    const bytes_read: usize = @intCast(read_res);

    var it = std.mem.splitScalar(u8, buf[0..bytes_read], '\n');
    var count: usize = 0;
    while (it.next()) |line| {
        if (std.mem.startsWith(u8, line, "cpu") and line.len > 3 and line[3] >= '0' and line[3] <= '9') {
            const space_idx = std.mem.indexOfScalar(u8, line, ' ') orelse continue;
            const core_idx_str = line[3..space_idx];
            const core_idx = std.fmt.parseInt(usize, core_idx_str, 10) catch continue;
            if (core_idx < 64) {
                cores[core_idx] = parseCpuLine(line);
                if (core_idx + 1 > count) count = core_idx + 1;
            }
        }
    }
    return count;
}

pub fn getMilliTimestamp() i64 {
    var ts: std.posix.timespec = undefined;
    if (std.posix.errno(std.posix.system.clock_gettime(.MONOTONIC, &ts)) != .SUCCESS) {
        return 0;
    }
    return @as(i64, ts.sec) * 1000 + @divTrunc(@as(i64, ts.nsec), 1_000_000);
}

pub const CpuSampler = struct {
    prev_time_ms: i64 = 0,
    prev_proc_ticks: u64 = 0,
    prev_sys_sample: CpuSample = .{},
    prev_cores: [64]CpuSample = [_]CpuSample{.{}} ** 64,
    num_cores: usize = 0,

    pub fn init() CpuSampler {
        var sampler = CpuSampler{
            .prev_time_ms = getMilliTimestamp(),
            .prev_proc_ticks = readProcTicks(),
            .prev_sys_sample = readSysSample(),
        };
        sampler.num_cores = readAllCores(&sampler.prev_cores);
        return sampler;
    }

    pub fn sample(self: *CpuSampler) CpuUsage {
        const cur_time_ms = getMilliTimestamp();
        const cur_proc_ticks = readProcTicks();
        const cur_sys_sample = readSysSample();

        var cur_cores: [64]CpuSample = [_]CpuSample{.{}} ** 64;
        const cores_count = readAllCores(&cur_cores);
        if (self.num_cores == 0) self.num_cores = cores_count;

        var usage = CpuUsage{
            .num_cores = self.num_cores,
        };

        const cur_tot = cur_sys_sample.total();
        const prev_tot = self.prev_sys_sample.total();
        const cur_idle = cur_sys_sample.idleTotal();
        const prev_idle = self.prev_sys_sample.idleTotal();

        if (cur_tot > prev_tot) {
            const d_tot = @as(f32, @floatFromInt(cur_tot - prev_tot));
            const d_idle = @as(f32, @floatFromInt(if (cur_idle >= prev_idle) cur_idle - prev_idle else 0));
            usage.sys_cpu_pct = std.math.clamp(((d_tot - d_idle) / d_tot) * 100.0, 0.0, 100.0);

            if (cur_proc_ticks >= self.prev_proc_ticks) {
                const d_proc = @as(f32, @floatFromInt(cur_proc_ticks - self.prev_proc_ticks));
                const cores_mult = if (self.num_cores > 0) @as(f32, @floatFromInt(self.num_cores)) else 1.0;
                usage.app_cpu_pct = std.math.clamp((d_proc / d_tot) * 100.0 * cores_mult, 0.0, 100.0 * cores_mult);
            }
        }

        for (0..self.num_cores) |i| {
            const c_tot = cur_cores[i].total();
            const p_tot = self.prev_cores[i].total();
            const c_idle = cur_cores[i].idleTotal();
            const p_idle = self.prev_cores[i].idleTotal();
            if (c_tot > p_tot) {
                const dt = @as(f32, @floatFromInt(c_tot - p_tot));
                const di = @as(f32, @floatFromInt(if (c_idle >= p_idle) c_idle - p_idle else 0));
                usage.core_pcts[i] = std.math.clamp(((dt - di) / dt) * 100.0, 0.0, 100.0);
            } else {
                usage.core_pcts[i] = 0.0;
            }
        }

        self.prev_time_ms = cur_time_ms;
        self.prev_proc_ticks = cur_proc_ticks;
        self.prev_sys_sample = cur_sys_sample;
        @memcpy(&self.prev_cores, &cur_cores);

        return usage;
    }
};

// =============================================================================
// 3. SYSTEM INFO (LOAD AVG, UPTIME, TASKS)
// =============================================================================

pub const SystemInfo = struct {
    load_1m: f32 = 0.0,
    load_5m: f32 = 0.0,
    load_15m: f32 = 0.0,
    running_tasks: u32 = 0,
    total_tasks: u32 = 0,
    uptime_seconds: u64 = 0,

    pub fn formatUptime(self: SystemInfo, buf: []u8) []const u8 {
        const days = self.uptime_seconds / 86400;
        const hours = (self.uptime_seconds % 86400) / 3600;
        const mins = (self.uptime_seconds % 3600) / 60;
        const secs = self.uptime_seconds % 60;
        if (days > 0) {
            return std.fmt.bufPrint(buf, "{d}d {d:0>2}:{d:0>2}:{d:0>2}", .{ days, hours, mins, secs }) catch "0:00";
        } else {
            return std.fmt.bufPrint(buf, "{d:0>2}:{d:0>2}:{d:0>2}", .{ hours, mins, secs }) catch "0:00";
        }
    }
};

pub fn getSystemInfo() SystemInfo {
    var info: SystemInfo = .{};
    if (builtin.os.tag != .linux) return info;

    // 1. /proc/loadavg
    {
        const fd_res = std.os.linux.open("/proc/loadavg", std.os.linux.O{}, 0);
        const err = std.posix.errno(fd_res);
        if (err == .SUCCESS) {
            const raw_fd: std.os.linux.fd_t = @intCast(fd_res);
            defer _ = std.os.linux.close(raw_fd);
            var buf: [128]u8 = undefined;
            const read_res = std.os.linux.read(raw_fd, &buf, buf.len);
            if (std.posix.errno(read_res) == .SUCCESS) {
                const bytes_read: usize = @intCast(read_res);
                var it = std.mem.splitScalar(u8, buf[0..bytes_read], ' ');
                if (it.next()) |s1| info.load_1m = std.fmt.parseFloat(f32, s1) catch 0.0;
                if (it.next()) |s5| info.load_5m = std.fmt.parseFloat(f32, s5) catch 0.0;
                if (it.next()) |s15| info.load_15m = std.fmt.parseFloat(f32, s15) catch 0.0;
                if (it.next()) |tasks_str| {
                    if (std.mem.indexOfScalar(u8, tasks_str, '/')) |slash_idx| {
                        info.running_tasks = std.fmt.parseInt(u32, tasks_str[0..slash_idx], 10) catch 0;
                        info.total_tasks = std.fmt.parseInt(u32, tasks_str[slash_idx + 1 ..], 10) catch 0;
                    }
                }
            }
        }
    }

    // 2. /proc/uptime
    {
        const fd_res = std.os.linux.open("/proc/uptime", std.os.linux.O{}, 0);
        const err = std.posix.errno(fd_res);
        if (err == .SUCCESS) {
            const raw_fd: std.os.linux.fd_t = @intCast(fd_res);
            defer _ = std.os.linux.close(raw_fd);
            var buf: [64]u8 = undefined;
            const read_res = std.os.linux.read(raw_fd, &buf, buf.len);
            if (std.posix.errno(read_res) == .SUCCESS) {
                const bytes_read: usize = @intCast(read_res);
                var it = std.mem.splitScalar(u8, buf[0..bytes_read], ' ');
                if (it.next()) |s| {
                    if (std.mem.indexOfScalar(u8, s, '.')) |dot_idx| {
                        info.uptime_seconds = std.fmt.parseInt(u64, s[0..dot_idx], 10) catch 0;
                    } else {
                        info.uptime_seconds = std.fmt.parseInt(u64, s, 10) catch 0;
                    }
                }
            }
        }
    }

    return info;
}

// =============================================================================
// 4. PROCESS LISTING
// =============================================================================

pub const ProcessItem = struct {
    pid: []const u8,
    user: []const u8,
    pri: []const u8,
    ni: []const u8,
    vsz: []const u8,
    rss: []const u8,
    stat: []const u8,
    cpu_pct: []const u8,
    mem_pct: []const u8,
    time: []const u8,
    comm: []const u8,
};

extern fn popen(command: [*:0]const u8, modes: [*:0]const u8) ?*anyopaque;
extern fn pclose(stream: *anyopaque) c_int;
extern fn fread(ptr: [*]u8, size: usize, nmemb: usize, stream: *anyopaque) usize;

pub fn fetchTopProcesses(allocator: std.mem.Allocator, max_count: usize) ![]ProcessItem {
    if (builtin.os.tag != .linux) return &.{};
    const pipe = popen("ps -eo pid,user,pri,ni,vsz,rss,stat,%cpu,%mem,time,comm --sort=-%cpu,-%mem", "r");
    if (pipe == null) return &.{};
    defer _ = pclose(pipe.?);

    var buf_list = std.ArrayList(u8).empty;
    defer buf_list.deinit(allocator);

    var chunk: [4096]u8 = undefined;
    while (true) {
        const n = fread(&chunk, 1, chunk.len, pipe.?);
        if (n == 0) break;
        try buf_list.appendSlice(allocator, chunk[0..n]);
        if (buf_list.items.len >= 256 * 1024) break;
    }

    var list = std.ArrayList(ProcessItem).empty;
    var it = std.mem.splitScalar(u8, buf_list.items, '\n');

    // Skip header line
    _ = it.next();

    while (it.next()) |line| {
        if (list.items.len >= max_count) break;
        const trimmed = std.mem.trim(u8, line, " \t\r");
        if (trimmed.len == 0) continue;

        var tok_it = std.mem.splitScalar(u8, trimmed, ' ');
        var tokens: [11][]const u8 = undefined;
        var tok_idx: usize = 0;

        while (tok_it.next()) |tok| {
            if (tok.len == 0) continue;
            if (tok_idx < 10) {
                tokens[tok_idx] = try allocator.dupe(u8, tok);
                tok_idx += 1;
            } else if (tok_idx == 10) {
                const rest_start = @intFromPtr(tok.ptr) - @intFromPtr(trimmed.ptr);
                tokens[10] = try allocator.dupe(u8, trimmed[rest_start..]);
                tok_idx = 11;
                break;
            }
        }

        if (tok_idx >= 11) {
            try list.append(allocator, .{
                .pid = tokens[0],
                .user = tokens[1],
                .pri = tokens[2],
                .ni = tokens[3],
                .vsz = tokens[4],
                .rss = tokens[5],
                .stat = tokens[6],
                .cpu_pct = tokens[7],
                .mem_pct = tokens[8],
                .time = tokens[9],
                .comm = tokens[10],
            });
        }
    }

    return list.toOwnedSlice(allocator);
}

// =============================================================================
// 5. HTOP GAUGE BAR RENDERER
// =============================================================================

/// Renders a classic htop meter bar:
/// Label [||||||||||||||||||||                  52.4%]
pub fn renderGaugeBar(
    writer: anytype,
    label: []const u8,
    label_width: usize,
    pct: f32,
    bar_width: usize,
    val_str: ?[]const u8,
    theme: anytype,
) !void {
    // 1. Print Label
    try writer.print("{s}{s:<" ++ "}{s}", .{ theme.fg_bold, label, theme.reset });
    if (label_width > label.len) {
        for (0..(label_width - label.len)) |_| try writer.writeAll(" ");
    }

    // 2. Left Bracket
    try writer.print("{s}[{s}", .{ theme.border, theme.reset });

    // Inner bar area
    const inner_w = if (bar_width >= 2) bar_width - 2 else 10;
    const clamped_pct = std.math.clamp(pct, 0.0, 100.0);
    const filled_chars: usize = @intFromFloat((@as(f32, @floatFromInt(inner_w)) * clamped_pct) / 100.0);

    // Value text on right: e.g. "52.4%" or "6.10G/15.6G"
    var val_buf: [32]u8 = undefined;
    const text_on_bar = val_str orelse (std.fmt.bufPrint(&val_buf, "{d:>5.1}%", .{clamped_pct}) catch "");

    // Choose bar fill color gradient: green (low) -> yellow (med) -> red (high)
    const bar_color = if (clamped_pct >= 75.0)
        theme.crit
    else if (clamped_pct >= 50.0)
        theme.warn
    else
        theme.success;

    if (filled_chars >= inner_w) {
        // Fully saturated
        try writer.print("{s}", .{bar_color});
        for (0..inner_w) |_| try writer.writeAll("|");
        try writer.print("{s}", .{theme.reset});
    } else {
        // Print filled part
        try writer.print("{s}", .{bar_color});
        for (0..filled_chars) |_| try writer.writeAll("|");
        try writer.print("{s}", .{theme.reset});

        // Print unfilled area with value text right-aligned
        const empty_slots = inner_w - filled_chars;
        if (empty_slots > text_on_bar.len) {
            const pad = empty_slots - text_on_bar.len;
            for (0..pad) |_| try writer.writeAll(" ");
            try writer.print("{s}{s}{s}", .{ theme.fg_muted, text_on_bar, theme.reset });
        } else {
            for (0..empty_slots) |_| try writer.writeAll(" ");
        }
    }

    // 3. Right Bracket
    try writer.print("{s}]{s}", .{ theme.border, theme.reset });
}

// =============================================================================
// TESTS
// =============================================================================

test "SystemMemory formatCompact" {
    var buf: [32]u8 = undefined;
    try std.testing.expectEqualStrings("2.57M", SystemMemory.formatCompact(2694840, &buf));
    try std.testing.expectEqualStrings("7.67G", SystemMemory.formatCompact(8235556864, &buf));
    try std.testing.expectEqualStrings("512.0K", SystemMemory.formatCompact(524288, &buf));
}

test "getSystemMemory reads valid data on Linux" {
    if (builtin.os.tag == .linux) {
        const mem = getSystemMemory();
        try std.testing.expect(mem.sys_total_bytes > 0);
        try std.testing.expect(mem.app_rss_bytes > 0);
    }
}

test "CpuSampler initialization" {
    if (builtin.os.tag == .linux) {
        var sampler = CpuSampler.init();
        const usage = sampler.sample();
        try std.testing.expect(usage.num_cores > 0);
    }
}

test "getSystemInfo reads loadavg and uptime" {
    if (builtin.os.tag == .linux) {
        const info = getSystemInfo();
        try std.testing.expect(info.total_tasks > 0);
    }
}

test "fetchTopProcesses returns process list" {
    if (builtin.os.tag == .linux) {
        var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
        defer arena.deinit();
        const procs = try fetchTopProcesses(arena.allocator(), 5);
        try std.testing.expect(procs.len > 0);
        try std.testing.expect(procs[0].pid.len > 0);
    }
}

test "renderGaugeBar outputs formatted string" {
    var buf = std.ArrayList(u8).empty;
    defer buf.deinit(std.testing.allocator);
    const writer = style.bufferWriter(std.testing.allocator, &buf);

    try renderGaugeBar(writer, "1", 3, 50.0, 20, null, style.THEME_TOKYO_NIGHT);
    try std.testing.expect(buf.items.len > 0);
    try std.testing.expect(std.mem.indexOf(u8, buf.items, "[") != null);
    try std.testing.expect(std.mem.indexOf(u8, buf.items, "]") != null);
}
