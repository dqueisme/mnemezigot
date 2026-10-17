const std = @import("std");
const style_mod = @import("style.zig");
const box_mod = @import("box.zig");
const terminal_mod = @import("terminal.zig");

pub const Color = style_mod.Color;
pub const Style = style_mod.Style;
pub const BorderStyle = box_mod.BorderStyle;
pub const stringWidth = box_mod.stringWidth;

pub const KanbanBadge = struct {
    text: []const u8,
    color: Color = .none,
};

pub const KanbanCard = struct {
    id: []const u8,
    title: []const u8,
    subtitle: ?[]const u8 = null,
    badge: ?KanbanBadge = null,
    details: ?[]const u8 = null,
    date: ?[]const u8 = null,
    metadata: ?[]const u8 = null,
};

pub const KanbanColumn = struct {
    id: []const u8,
    title: []const u8,
    icon: ?[]const u8 = null,
    color: Color = .bright_cyan,
    cards: std.ArrayList(KanbanCard),

    pub fn init(allocator: std.mem.Allocator, id: []const u8, title: []const u8, icon: ?[]const u8, color: Color) KanbanColumn {
        _ = allocator;
        return .{
            .id = id,
            .title = title,
            .icon = icon,
            .color = color,
            .cards = std.ArrayList(KanbanCard).empty,
        };
    }

    pub fn deinit(self: *KanbanColumn, allocator: std.mem.Allocator) void {
        self.cards.deinit(allocator);
    }

    pub fn addCard(self: *KanbanColumn, allocator: std.mem.Allocator, card: KanbanCard) !void {
        try self.cards.append(allocator, card);
    }
};

pub const ViewMode = enum {
    two_pane,
    columns,
};

pub const KanbanBoard = struct {
    allocator: std.mem.Allocator,
    title: []const u8,
    subtitle: ?[]const u8 = null,
    columns: std.ArrayList(KanbanColumn),
    selected_col: usize = 0,
    selected_card: usize = 0,
    show_modal: bool = false,
    stats_summary: ?[]const u8 = null,
    view_mode: ViewMode = .two_pane,

    pub fn init(allocator: std.mem.Allocator, title: []const u8) KanbanBoard {
        return .{
            .allocator = allocator,
            .title = title,
            .columns = std.ArrayList(KanbanColumn).empty,
        };
    }

    pub fn deinit(self: *KanbanBoard) void {
        for (self.columns.items) |*col| {
            col.deinit(self.allocator);
        }
        self.columns.deinit(self.allocator);
    }

    pub fn addColumn(self: *KanbanBoard, col: KanbanColumn) !void {
        try self.columns.append(self.allocator, col);
    }

    pub fn selectColumn(self: *KanbanBoard, idx: usize) void {
        if (idx < self.columns.items.len) {
            self.selected_col = idx;
            self.clampSelectedCard();
        }
    }

    pub fn moveLeft(self: *KanbanBoard) void {
        if (self.selected_col > 0) {
            self.selected_col -= 1;
            self.clampSelectedCard();
        }
    }

    pub fn moveRight(self: *KanbanBoard) void {
        if (self.columns.items.len > 0 and self.selected_col + 1 < self.columns.items.len) {
            self.selected_col += 1;
            self.clampSelectedCard();
        }
    }

    pub fn moveUp(self: *KanbanBoard) void {
        if (self.selected_card > 0) {
            self.selected_card -= 1;
        }
    }

    pub fn moveDown(self: *KanbanBoard) void {
        if (self.columns.items.len > self.selected_col) {
            const cards_len = self.columns.items[self.selected_col].cards.items.len;
            if (cards_len > 0 and self.selected_card + 1 < cards_len) {
                self.selected_card += 1;
            }
        }
    }

    fn clampSelectedCard(self: *KanbanBoard) void {
        if (self.columns.items.len > self.selected_col) {
            const cards_len = self.columns.items[self.selected_col].cards.items.len;
            if (cards_len == 0) {
                self.selected_card = 0;
            } else if (self.selected_card >= cards_len) {
                self.selected_card = cards_len - 1;
            }
        } else {
            self.selected_card = 0;
        }
    }

    pub fn toggleModal(self: *KanbanBoard) void {
        self.show_modal = !self.show_modal;
    }

    pub fn closeModal(self: *KanbanBoard) void {
        self.show_modal = false;
    }

    pub fn getSelectedCard(self: *const KanbanBoard) ?KanbanCard {
        if (self.selected_col < self.columns.items.len) {
            const col = self.columns.items[self.selected_col];
            if (self.selected_card < col.cards.items.len) {
                return col.cards.items[self.selected_card];
            }
        }
        return null;
    }

    pub fn getSelectedColumn(self: *const KanbanBoard) ?*const KanbanColumn {
        if (self.selected_col < self.columns.items.len) {
            return &self.columns.items[self.selected_col];
        }
        return null;
    }

    /// Truncate a UTF-8 string to fit within max_width visible display columns
    fn truncateWidth(allocator: std.mem.Allocator, str: []const u8, max_width: usize) ![]const u8 {
        if (max_width == 0) return "";
        var current_w: usize = 0;
        var byte_idx: usize = 0;

        while (byte_idx < str.len) {
            if (str[byte_idx] == 0x1b and byte_idx + 1 < str.len and str[byte_idx + 1] == '[') {
                const start = byte_idx;
                byte_idx += 2;
                while (byte_idx < str.len and str[byte_idx] != 'm') : (byte_idx += 1) {}
                if (byte_idx < str.len and str[byte_idx] == 'm') byte_idx += 1;
                _ = start;
                continue;
            }

            const len = std.unicode.utf8ByteSequenceLength(str[byte_idx]) catch 1;
            var w: usize = 1;
            if (len >= 3 and byte_idx + len <= str.len) {
                const cp = std.unicode.utf8Decode(str[byte_idx .. byte_idx + len]) catch 0;
                if (box_mod.isWideChar(cp)) w = 2;
            }

            if (current_w + w > max_width) {
                if (max_width >= 2 and byte_idx > 0) {
                    return try std.fmt.allocPrint(allocator, "{s}…", .{str[0..byte_idx]});
                } else {
                    return try allocator.dupe(u8, str[0..byte_idx]);
                }
            }

            current_w += w;
            byte_idx += len;
        }

        return try allocator.dupe(u8, str);
    }

    /// Word-wrap text into lines of at most max_width display columns
    fn wrapText(arena: std.mem.Allocator, text: []const u8, max_width: usize, out_lines: *std.ArrayList([]const u8)) !void {
        if (max_width == 0) return;
        var line_iter = std.mem.splitScalar(u8, text, '\n');
        while (line_iter.next()) |raw_line| {
            if (raw_line.len == 0) {
                try out_lines.append(arena, "");
                continue;
            }

            var word_iter = std.mem.tokenizeScalar(u8, raw_line, ' ');
            var cur_buf: std.ArrayList(u8) = .empty;
            var cur_w = style_mod.bufferWriter(arena, &cur_buf);
            var cur_len: usize = 0;

            while (word_iter.next()) |word| {
                const w = stringWidth(word);
                if (cur_len == 0) {
                    try cur_w.writeAll(word);
                    cur_len = w;
                } else if (cur_len + 1 + w <= max_width) {
                    try cur_w.writeAll(" ");
                    try cur_w.writeAll(word);
                    cur_len += 1 + w;
                } else {
                    try out_lines.append(arena, cur_buf.items);
                    cur_buf = std.ArrayList(u8).empty;
                    cur_w = style_mod.bufferWriter(arena, &cur_buf);
                    try cur_w.writeAll(word);
                    cur_len = w;
                }
            }
            if (cur_buf.items.len > 0) {
                try out_lines.append(arena, cur_buf.items);
            }
        }
    }

    /// Render the Kanban board in modern, robust 2-Pane Master-Detail layout
    pub fn renderTwoPane(self: *const KanbanBoard, writer: anytype, term_width: u16, term_height: u16) !void {
        var arena_state = std.heap.ArenaAllocator.init(self.allocator);
        defer arena_state.deinit();
        const arena = arena_state.allocator();

        const num_cols = self.columns.items.len;
        if (num_cols == 0) {
            try writer.writeAll("Belum ada kolom Kanban yang tersedia.\n");
            return;
        }

        const width: usize = @max(@as(usize, term_width), 60);
        const height: usize = @max(@as(usize, term_height), 20);

        // 1. Top Header
        try style_mod.writeStyled(writer, "📋 ", .bright_cyan, .none, .{ .bold = true });
        try style_mod.writeStyled(writer, self.title, .bright_white, .none, .{ .bold = true });

        if (self.subtitle) |sub| {
            try writer.writeAll("  ");
            try style_mod.writeStyled(writer, sub, .bright_black, .none, .{});
        }
        try writer.writeAll("\n");

        if (self.stats_summary) |stats| {
            try style_mod.writeStyled(writer, stats, .bright_yellow, .none, .{});
            try writer.writeAll("\n");
        }

        // Header separator
        for (0..width) |_| {
            try style_mod.writeStyled(writer, "═", .cyan, .none, .{});
        }
        try writer.writeAll("\n");

        // 2. Render Modal Overlay if active
        if (self.show_modal) {
            try self.renderModal(arena, writer, width);
            return;
        }

        // 3. Compute Split Widths
        var left_w = (width * 38) / 100;
        if (left_w < 28) left_w = 28;
        if (left_w > 45) left_w = 45;
        const div_w: usize = 3; // " │ "
        const right_w = if (width > left_w + div_w) width - left_w - div_w else 28;

        // 4. Build Left Pane Lines (Menu Kolom + Daftar Kartu)
        var left_lines = std.ArrayList([]const u8).empty;

        try left_lines.append(arena, "\x1b[1;96m📑 MENU KOLOM KANBAN\x1b[0m");

        // List columns
        for (self.columns.items, 0..) |col, c_idx| {
            const is_col = (c_idx == self.selected_col);
            const num = c_idx + 1;
            const icon = col.icon orelse "📌";
            var line_buf: std.ArrayList(u8) = .empty;
            var lw = style_mod.bufferWriter(arena, &line_buf);

            if (is_col) {
                try lw.print("\x1b[1;93m▶ [{d}] {s} {s} ({d})\x1b[0m", .{ num, icon, col.title, col.cards.items.len });
            } else {
                try lw.print("\x1b[90m  [{d}] {s} {s} ({d})\x1b[0m", .{ num, icon, col.title, col.cards.items.len });
            }
            try left_lines.append(arena, line_buf.items);
        }

        // Divider in left pane
        var div_buf: std.ArrayList(u8) = .empty;
        var dw = style_mod.bufferWriter(arena, &div_buf);
        try dw.writeAll("\x1b[90m");
        for (0..left_w) |_| try dw.writeAll("─");
        try dw.writeAll("\x1b[0m");
        try left_lines.append(arena, div_buf.items);

        // Cards list of active column
        const active_col = &self.columns.items[self.selected_col];
        const card_header = try std.fmt.allocPrint(arena, "\x1b[1;96m📋 KARTU: {s} ({d})\x1b[0m", .{ active_col.title, active_col.cards.items.len });
        try left_lines.append(arena, card_header);

        if (active_col.cards.items.len == 0) {
            try left_lines.append(arena, "  \x1b[90m(Belum ada kartu di kolom ini)\x1b[0m");
        } else {
            const body_height = if (height > 6) height - 6 else 15;
            const menu_rows_used = self.columns.items.len + 3;
            const avail_card_rows = if (body_height > menu_rows_used + 1) body_height - menu_rows_used - 1 else 10;

            var scroll_start: usize = 0;
            if (self.selected_card >= avail_card_rows) {
                scroll_start = self.selected_card - avail_card_rows + 1;
            }
            const scroll_end = @min(active_col.cards.items.len, scroll_start + avail_card_rows);

            for (active_col.cards.items[scroll_start..scroll_end], scroll_start..) |card, k_idx| {
                const is_card = (k_idx == self.selected_card);
                const max_title_w = if (left_w >= 14) left_w - 14 else 10;
                const trunc_title = try truncateWidth(arena, card.title, max_title_w);

                var badge_symbol: []const u8 = "";
                if (card.badge) |bdg| {
                    if (std.mem.indexOf(u8, bdg.text, "Kritis") != null) {
                        badge_symbol = "🔴 ";
                    } else if (std.mem.indexOf(u8, bdg.text, "Penting") != null) {
                        badge_symbol = "🟡 ";
                    } else if (std.mem.indexOf(u8, bdg.text, "Rendah") != null) {
                        badge_symbol = "🟢 ";
                    }
                }

                var card_item_buf: std.ArrayList(u8) = .empty;
                var cw = style_mod.bufferWriter(arena, &card_item_buf);

                if (is_card) {
                    try cw.print("\x1b[1;93m► #{s} {s}{s}\x1b[0m", .{ card.id, badge_symbol, trunc_title });
                } else {
                    try cw.print("\x1b[37m  #{s} {s}{s}\x1b[0m", .{ card.id, badge_symbol, trunc_title });
                }
                try left_lines.append(arena, card_item_buf.items);
            }
        }

        // 5. Build Right Pane Lines (Card Detail Viewer)
        var right_lines = std.ArrayList([]const u8).empty;
        try right_lines.append(arena, "\x1b[1;96m🔍 RINCIAN KARTU (LIVE INSPECTOR)\x1b[0m");

        const card_opt = self.getSelectedCard();
        if (card_opt) |card| {
            // Box top
            var rtop_buf: std.ArrayList(u8) = .empty;
            var rtw = style_mod.bufferWriter(arena, &rtop_buf);
            try rtw.print("\x1b[1;93m┌─ #{s} ", .{card.id});
            const top_vis_w = stringWidth(card.id) + 4;
            if (right_w > top_vis_w + 1) {
                for (0..(right_w - top_vis_w - 1)) |_| try rtw.writeAll("─");
            }
            try rtw.writeAll("┐\x1b[0m");
            try right_lines.append(arena, rtop_buf.items);

            // Title (wrapped if needed)
            const detail_inner_w = if (right_w >= 4) right_w - 4 else 20;
            var title_lines = std.ArrayList([]const u8).empty;
            const title_wrap_w = if (detail_inner_w > 12) detail_inner_w - 12 else 10;
            try wrapText(arena, card.title, title_wrap_w, &title_lines);

            for (title_lines.items, 0..) |tline, idx| {
                if (idx == 0) {
                    try right_lines.append(arena, try std.fmt.allocPrint(arena, "│ \x1b[1;96mJudul   :\x1b[0m \x1b[1;97m{s}\x1b[0m", .{tline}));
                } else {
                    try right_lines.append(arena, try std.fmt.allocPrint(arena, "│           \x1b[1;97m{s}\x1b[0m", .{tline}));
                }
            }

            // Column & Status
            const icon = active_col.icon orelse "📌";
            try right_lines.append(arena, try std.fmt.allocPrint(arena, "│ \x1b[1;96mKolom   :\x1b[0m \x1b[36m{s} {s}\x1b[0m", .{ icon, active_col.title }));

            if (card.badge) |bdg| {
                try right_lines.append(arena, try std.fmt.allocPrint(arena, "│ \x1b[1;96mPrioritas:\x1b[0m \x1b[93m[{s}]\x1b[0m", .{bdg.text}));
            }

            if (card.date) |dt| {
                try right_lines.append(arena, try std.fmt.allocPrint(arena, "│ \x1b[1;96mTanggal :\x1b[0m \x1b[90m{s}\x1b[0m", .{dt}));
            }

            if (card.metadata) |meta| {
                try right_lines.append(arena, try std.fmt.allocPrint(arena, "│ \x1b[1;96mPapan   :\x1b[0m \x1b[36m{s}\x1b[0m", .{meta}));
            }

            // Divider inside right box
            var rdiv_buf: std.ArrayList(u8) = .empty;
            var rdw = style_mod.bufferWriter(arena, &rdiv_buf);
            try rdw.writeAll("\x1b[1;93m├");
            if (right_w >= 2) {
                for (0..(right_w - 2)) |_| try rdw.writeAll("─");
            }
            try rdw.writeAll("┤\x1b[0m");
            try right_lines.append(arena, rdiv_buf.items);

            // Description / Tech Notes Header
            try right_lines.append(arena, "│ \x1b[1;92mCatatan & Uraian Teknis:\x1b[0m");

            if (card.details) |det| {
                var wrapped_notes = std.ArrayList([]const u8).empty;
                try wrapText(arena, det, detail_inner_w, &wrapped_notes);

                const max_note_lines = if (height > 14) height - 14 else 8;
                for (wrapped_notes.items[0..@min(wrapped_notes.items.len, max_note_lines)]) |nline| {
                    try right_lines.append(arena, try std.fmt.allocPrint(arena, "│   {s}", .{nline}));
                }
                if (wrapped_notes.items.len > max_note_lines) {
                    try right_lines.append(arena, "│   \x1b[90m... (uraian dipotong untuk preview live)\x1b[0m");
                }
            } else {
                try right_lines.append(arena, "│   \x1b[90m(Tidak ada catatan tambahan untuk kartu ini)\x1b[0m");
            }

            // Box bottom
            var rbot_buf: std.ArrayList(u8) = .empty;
            var rbw = style_mod.bufferWriter(arena, &rbot_buf);
            try rbw.writeAll("\x1b[1;93m└");
            if (right_w >= 2) {
                for (0..(right_w - 2)) |_| try rbw.writeAll("─");
            }
            try rbw.writeAll("┘\x1b[0m");
            try right_lines.append(arena, rbot_buf.items);
        } else {
            try right_lines.append(arena, "  \x1b[90m(Pilih salah satu kartu pada pane kiri untuk membaca rincian)\x1b[0m");
        }

        // 6. Merge Left and Right Lines Row by Row
        const body_height = if (height > 6) height - 6 else 15;
        const total_render_rows = @min(body_height, @max(left_lines.items.len, right_lines.items.len));

        for (0..total_render_rows) |r| {
            if (r < left_lines.items.len) {
                const lstr = left_lines.items[r];
                try writer.writeAll(lstr);
                const lvis = stringWidth(lstr);
                if (left_w > lvis) {
                    for (0..(left_w - lvis)) |_| try writer.writeAll(" ");
                }
            } else {
                for (0..left_w) |_| try writer.writeAll(" ");
            }

            try writer.writeAll("\x1b[90m │ \x1b[0m");

            if (r < right_lines.items.len) {
                const rstr = right_lines.items[r];
                try writer.writeAll(rstr);
                const rvis = stringWidth(rstr);
                if (right_w > rvis) {
                    for (0..(right_w - rvis)) |_| try writer.writeAll(" ");
                }
            } else {
                for (0..right_w) |_| try writer.writeAll(" ");
            }

            try writer.writeAll("\n");
        }

        // 7. Bottom Controls Bar
        for (0..width) |_| {
            try style_mod.writeStyled(writer, "─", .bright_black, .none, .{});
        }
        try writer.writeAll("\n");

        try style_mod.writeStyled(writer, " 🎮 [1-4/h/l] ", .bright_cyan, .none, .{ .bold = true });
        try writer.writeAll("Pilih Kolom  ");
        try style_mod.writeStyled(writer, "[↑/k / ↓/j] ", .bright_cyan, .none, .{ .bold = true });
        try writer.writeAll("Pilih Kartu  ");
        try style_mod.writeStyled(writer, "[Enter/Space] ", .bright_yellow, .none, .{ .bold = true });
        try writer.writeAll("Drawer Modal  ");
        try style_mod.writeStyled(writer, "[r] ", .bright_green, .none, .{ .bold = true });
        try writer.writeAll("Refresh  ");
        try style_mod.writeStyled(writer, "[q] ", .bright_red, .none, .{ .bold = true });
        try writer.writeAll("Keluar\n");
    }

    /// Render standard multi-column view
    pub fn renderColumns(self: *const KanbanBoard, writer: anytype, term_width: u16, term_height: u16) !void {
        var arena_state = std.heap.ArenaAllocator.init(self.allocator);
        defer arena_state.deinit();
        const arena = arena_state.allocator();

        const num_cols = self.columns.items.len;
        if (num_cols == 0) {
            try writer.writeAll("Belum ada kolom Kanban yang tersedia.\n");
            return;
        }

        const width: usize = @max(@as(usize, term_width), 60);
        const height: usize = @max(@as(usize, term_height), 20);

        // 1. Render Top Header
        try style_mod.writeStyled(writer, "📋 ", .bright_cyan, .none, .{ .bold = true });
        try style_mod.writeStyled(writer, self.title, .bright_white, .none, .{ .bold = true });

        if (self.subtitle) |sub| {
            try writer.writeAll("  ");
            try style_mod.writeStyled(writer, sub, .bright_black, .none, .{});
        }
        try writer.writeAll("\n");

        if (self.stats_summary) |stats| {
            try style_mod.writeStyled(writer, stats, .bright_yellow, .none, .{});
            try writer.writeAll("\n");
        }

        for (0..width) |_| {
            try style_mod.writeStyled(writer, "═", .cyan, .none, .{});
        }
        try writer.writeAll("\n");

        if (self.show_modal) {
            try self.renderModal(arena, writer, width);
            return;
        }

        const gap: usize = 1;
        const total_gaps: usize = if (num_cols > 1) (num_cols - 1) * gap else 0;
        const avail_width: usize = if (width > total_gaps + 2) width - total_gaps else 40;
        const col_width: usize = @max(@as(usize, 18), avail_width / num_cols);

        var col_lines_list = try arena.alloc(std.ArrayList([]const u8), num_cols);
        for (0..num_cols) |i| {
            col_lines_list[i] = std.ArrayList([]const u8).empty;
        }

        for (self.columns.items, 0..) |col, c_idx| {
            var lines = &col_lines_list[c_idx];
            const is_col_focused = (c_idx == self.selected_col);

            var top_buf: std.ArrayList(u8) = .empty;
            var top_w = style_mod.bufferWriter(arena, &top_buf);
            try top_w.writeAll("╭");
            const icon_str = col.icon orelse "📌";
            const col_title_str = try std.fmt.allocPrint(arena, " {s} {s} ({d}) ", .{ icon_str, col.title, col.cards.items.len });
            const title_vis_w = stringWidth(col_title_str);

            const border_pad = if (col_width > title_vis_w + 2) col_width - title_vis_w - 2 else 0;
            const left_pad = border_pad / 2;
            const right_pad = border_pad - left_pad;

            for (0..left_pad) |_| try top_w.writeAll("─");
            try top_w.writeAll(col_title_str);
            for (0..right_pad) |_| try top_w.writeAll("─");
            try top_w.writeAll("╮");

            if (is_col_focused) {
                const styled_header = try std.fmt.allocPrint(arena, "\x1b[1;93m{s}\x1b[0m", .{top_buf.items});
                try lines.append(arena, styled_header);
            } else {
                const styled_header = try std.fmt.allocPrint(arena, "\x1b[36m{s}\x1b[0m", .{top_buf.items});
                try lines.append(arena, styled_header);
            }

            if (col.cards.items.len == 0) {
                var empty_buf: std.ArrayList(u8) = .empty;
                var ew = style_mod.bufferWriter(arena, &empty_buf);
                try ew.writeAll("│ \x1b[90m(Kosong)\x1b[0m");
                const empty_vis_w = stringWidth("│ (Kosong)");
                if (col_width > empty_vis_w + 1) {
                    for (0..(col_width - empty_vis_w - 1)) |_| try ew.writeAll(" ");
                }
                try ew.writeAll("│");
                try lines.append(arena, empty_buf.items);

                var bot_buf: std.ArrayList(u8) = .empty;
                var bw = style_mod.bufferWriter(arena, &bot_buf);
                try bw.writeAll("╰");
                if (col_width >= 2) {
                    for (0..(col_width - 2)) |_| try bw.writeAll("─");
                }
                try bw.writeAll("╯");
                try lines.append(arena, bot_buf.items);
            } else {
                for (col.cards.items, 0..) |card, k_idx| {
                    const is_card_focused = (is_col_focused and k_idx == self.selected_card);

                    var card_top: std.ArrayList(u8) = .empty;
                    var ctw = style_mod.bufferWriter(arena, &card_top);
                    const tag_indicator = if (is_card_focused) "►" else "─";
                    const id_label = try std.fmt.allocPrint(arena, "┌{s} #{s} ", .{ tag_indicator, card.id });
                    const id_vis_w = stringWidth(id_label);
                    try ctw.writeAll(id_label);
                    if (col_width > id_vis_w + 1) {
                        for (0..(col_width - id_vis_w - 1)) |_| try ctw.writeAll("─");
                    }
                    try ctw.writeAll("┐");

                    if (is_card_focused) {
                        try lines.append(arena, try std.fmt.allocPrint(arena, "\x1b[1;93m{s}\x1b[0m", .{card_top.items}));
                    } else {
                        try lines.append(arena, try std.fmt.allocPrint(arena, "\x1b[90m{s}\x1b[0m", .{card_top.items}));
                    }

                    const inner_w = if (col_width >= 4) col_width - 4 else 10;
                    const trunc_title = try truncateWidth(arena, card.title, inner_w);
                    var card_title: std.ArrayList(u8) = .empty;
                    var ttl_w = style_mod.bufferWriter(arena, &card_title);
                    try ttl_w.writeAll("│ ");
                    if (is_card_focused) {
                        try ttl_w.print("\x1b[1;97m{s}\x1b[0m", .{trunc_title});
                    } else {
                        try ttl_w.print("{s}", .{trunc_title});
                    }
                    const title_used = stringWidth(trunc_title);
                    if (inner_w > title_used) {
                        for (0..(inner_w - title_used)) |_| try ttl_w.writeAll(" ");
                    }
                    try ttl_w.writeAll(" │");
                    try lines.append(arena, card_title.items);

                    if (card.badge != null or card.date != null) {
                        var meta_buf: std.ArrayList(u8) = .empty;
                        var mw = style_mod.bufferWriter(arena, &meta_buf);
                        try mw.writeAll("│ ");

                        var meta_text_buf: std.ArrayList(u8) = .empty;
                        var mtw = style_mod.bufferWriter(arena, &meta_text_buf);
                        if (card.badge) |bdg| {
                            try mtw.print("[{s}] ", .{bdg.text});
                        }
                        if (card.date) |dt| {
                            try mtw.print("@{s}", .{dt});
                        }

                        const trunc_meta = try truncateWidth(arena, meta_text_buf.items, inner_w);
                        try mw.print("\x1b[90m{s}\x1b[0m", .{trunc_meta});
                        const meta_used = stringWidth(trunc_meta);
                        if (inner_w > meta_used) {
                            for (0..(inner_w - meta_used)) |_| try mw.writeAll(" ");
                        }
                        try mw.writeAll(" │");
                        try lines.append(arena, meta_buf.items);
                    }

                    var card_bot: std.ArrayList(u8) = .empty;
                    var cbw = style_mod.bufferWriter(arena, &card_bot);
                    try cbw.writeAll("└");
                    if (col_width >= 2) {
                        for (0..(col_width - 2)) |_| try cbw.writeAll("─");
                    }
                    try cbw.writeAll("┘");

                    if (is_card_focused) {
                        try lines.append(arena, try std.fmt.allocPrint(arena, "\x1b[1;93m{s}\x1b[0m", .{card_bot.items}));
                    } else {
                        try lines.append(arena, try std.fmt.allocPrint(arena, "\x1b[90m{s}\x1b[0m", .{card_bot.items}));
                    }
                }
            }
        }

        var max_lines: usize = 0;
        for (col_lines_list) |lines| {
            if (lines.items.len > max_lines) max_lines = lines.items.len;
        }

        const max_display_rows = if (height > 6) height - 6 else max_lines;
        const rows_to_render = @min(max_lines, max_display_rows);

        for (0..rows_to_render) |row_idx| {
            for (0..num_cols) |c_idx| {
                const lines = &col_lines_list[c_idx];
                if (row_idx < lines.items.len) {
                    const l = lines.items[row_idx];
                    try writer.writeAll(l);
                    const vis_w = stringWidth(l);
                    if (col_width > vis_w) {
                        for (0..(col_width - vis_w)) |_| try writer.writeAll(" ");
                    }
                } else {
                    for (0..col_width) |_| try writer.writeAll(" ");
                }

                if (c_idx + 1 < num_cols) {
                    try writer.writeAll(" ");
                }
            }
            try writer.writeAll("\n");
        }

        for (0..width) |_| {
            try style_mod.writeStyled(writer, "─", .bright_black, .none, .{});
        }
        try writer.writeAll("\n");

        try style_mod.writeStyled(writer, " 🎮 [h/←] ", .bright_cyan, .none, .{ .bold = true });
        try writer.writeAll("Kiri  ");
        try style_mod.writeStyled(writer, "[l/→] ", .bright_cyan, .none, .{ .bold = true });
        try writer.writeAll("Kanan  ");
        try style_mod.writeStyled(writer, "[k/↑] ", .bright_cyan, .none, .{ .bold = true });
        try writer.writeAll("Atas  ");
        try style_mod.writeStyled(writer, "[j/↓] ", .bright_cyan, .none, .{ .bold = true });
        try writer.writeAll("Bawah  ");
        try style_mod.writeStyled(writer, "[Enter/Space] ", .bright_yellow, .none, .{ .bold = true });
        try writer.writeAll("Detail  ");
        try style_mod.writeStyled(writer, "[r] ", .bright_green, .none, .{ .bold = true });
        try writer.writeAll("Refresh  ");
        try style_mod.writeStyled(writer, "[q] ", .bright_red, .none, .{ .bold = true });
        try writer.writeAll("Keluar\n");
    }

    /// Render board based on active view mode (defaults to two_pane)
    pub fn render(self: *const KanbanBoard, writer: anytype, term_width: u16, term_height: u16) !void {
        switch (self.view_mode) {
            .two_pane => try self.renderTwoPane(writer, term_width, term_height),
            .columns => try self.renderColumns(writer, term_width, term_height),
        }
    }

    /// Render detailed modal popup for the currently selected card
    fn renderModal(self: *const KanbanBoard, arena: std.mem.Allocator, writer: anytype, width: usize) !void {
        const card_opt = self.getSelectedCard();
        const col_opt = self.getSelectedColumn();

        const modal_w = @min(width - 4, 78);
        const inner_w = if (modal_w >= 4) modal_w - 4 else 20;

        // Top Double Border
        try style_mod.writeStyled(writer, "╔", .bright_yellow, .none, .{ .bold = true });
        const title_label = " 🔍 RINCIAN KARTU KANBAN (CARD DRAWER) ";
        try style_mod.writeStyled(writer, title_label, .bright_yellow, .none, .{ .bold = true });
        const title_w = stringWidth(title_label);
        if (modal_w > title_w + 2) {
            for (0..(modal_w - title_w - 2)) |_| {
                try style_mod.writeStyled(writer, "═", .bright_yellow, .none, .{});
            }
        }
        try style_mod.writeStyled(writer, "╗\n", .bright_yellow, .none, .{ .bold = true });

        if (card_opt) |card| {
            try writer.writeAll("║ ");
            try style_mod.writeStyled(writer, "ID       : ", .bright_cyan, .none, .{ .bold = true });
            try writer.print("#{s}\n", .{card.id});

            try writer.writeAll("║ ");
            try style_mod.writeStyled(writer, "Judul    : ", .bright_cyan, .none, .{ .bold = true });
            try style_mod.writeStyled(writer, card.title, .bright_white, .none, .{ .bold = true });
            try writer.writeAll("\n");

            if (col_opt) |col| {
                try writer.writeAll("║ ");
                try style_mod.writeStyled(writer, "Kolom    : ", .bright_cyan, .none, .{ .bold = true });
                const icon = col.icon orelse "📌";
                try writer.print("{s} {s}\n", .{ icon, col.title });
            }

            if (card.badge) |bdg| {
                try writer.writeAll("║ ");
                try style_mod.writeStyled(writer, "Prioritas: ", .bright_cyan, .none, .{ .bold = true });
                try writer.print("[{s}]\n", .{bdg.text});
            }

            if (card.date) |dt| {
                try writer.writeAll("║ ");
                try style_mod.writeStyled(writer, "Tanggal  : ", .bright_cyan, .none, .{ .bold = true });
                try writer.print("{s}\n", .{dt});
            }

            if (card.metadata) |meta| {
                try writer.writeAll("║ ");
                try style_mod.writeStyled(writer, "Metadata : ", .bright_cyan, .none, .{ .bold = true });
                try writer.print("{s}\n", .{meta});
            }

            try style_mod.writeStyled(writer, "╟", .bright_yellow, .none, .{});
            for (0..(modal_w - 2)) |_| {
                try style_mod.writeStyled(writer, "─", .bright_yellow, .none, .{});
            }
            try style_mod.writeStyled(writer, "╢\n", .bright_yellow, .none, .{});

            try writer.writeAll("║ ");
            try style_mod.writeStyled(writer, "Catatan / Uraian Teknis:\n", .bright_green, .none, .{ .bold = true });

            if (card.details) |det| {
                var line_iter = std.mem.splitScalar(u8, det, '\n');
                var line_count: usize = 0;
                while (line_iter.next()) |line| {
                    if (line_count >= 15) {
                        try writer.writeAll("║ \x1b[90m... (uraian dipotong untuk tampilan modal)\x1b[0m\n");
                        break;
                    }
                    const trunc = try truncateWidth(arena, line, inner_w);
                    try writer.print("║   {s}\n", .{trunc});
                    line_count += 1;
                }
            } else {
                try writer.writeAll("║   (Tidak ada rincian tambahan untuk kartu ini)\n");
            }
        } else {
            try writer.writeAll("║ (Tidak ada kartu yang terpilih)\n");
        }

        try style_mod.writeStyled(writer, "╟", .bright_yellow, .none, .{});
        for (0..(modal_w - 2)) |_| {
            try style_mod.writeStyled(writer, "─", .bright_yellow, .none, .{});
        }
        try style_mod.writeStyled(writer, "╢\n", .bright_yellow, .none, .{});

        try writer.writeAll("║ ");
        try style_mod.writeStyled(writer, "[ Tekan ENTER / SPACE / ESC untuk menutup rincian kartu ]\n", .bright_yellow, .none, .{ .bold = true });

        try style_mod.writeStyled(writer, "╚", .bright_yellow, .none, .{ .bold = true });
        for (0..(modal_w - 2)) |_| {
            try style_mod.writeStyled(writer, "═", .bright_yellow, .none, .{});
        }
        try style_mod.writeStyled(writer, "╝\n", .bright_yellow, .none, .{ .bold = true });
    }
};

test "KanbanBoard initialization and navigation" {
    var board = KanbanBoard.init(std.testing.allocator, "TEST KANBAN");
    defer board.deinit();

    var col1 = KanbanColumn.init(std.testing.allocator, "backlog", "Backlog", "📥", .yellow);
    try col1.addCard(std.testing.allocator, .{
        .id = "1",
        .title = "Refactor Database WAL",
        .badge = .{ .text = "Kritis", .color = .red },
    });
    try col1.addCard(std.testing.allocator, .{
        .id = "2",
        .title = "Add TUI Kanban",
        .badge = .{ .text = "Penting", .color = .yellow },
    });
    try board.addColumn(col1);

    var col2 = KanbanColumn.init(std.testing.allocator, "done", "Done", "✅", .green);
    try col2.addCard(std.testing.allocator, .{
        .id = "3",
        .title = "Setup Framework Starter",
    });
    try board.addColumn(col2);

    try std.testing.expectEqual(@as(usize, 2), board.columns.items.len);
    try std.testing.expectEqual(@as(usize, 0), board.selected_col);
    try std.testing.expectEqual(@as(usize, 0), board.selected_card);

    board.moveDown();
    try std.testing.expectEqual(@as(usize, 1), board.selected_card);

    board.moveRight();
    try std.testing.expectEqual(@as(usize, 1), board.selected_col);
    try std.testing.expectEqual(@as(usize, 0), board.selected_card);

    board.moveLeft();
    try std.testing.expectEqual(@as(usize, 0), board.selected_col);

    // Test Two-Pane rendering
    board.view_mode = .two_pane;
    var buf: std.ArrayList(u8) = .empty;
    defer buf.deinit(std.testing.allocator);
    const w = style_mod.bufferWriter(std.testing.allocator, &buf);

    try board.render(w, 80, 24);
    const out = buf.items;
    try std.testing.expect(std.mem.indexOf(u8, out, "TEST KANBAN") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "MENU KOLOM KANBAN") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "RINCIAN KARTU") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "Refactor Database WAL") != null);

    // Test Column view rendering
    board.view_mode = .columns;
    buf.clearRetainingCapacity();
    try board.render(w, 80, 24);
    try std.testing.expect(std.mem.indexOf(u8, buf.items, "Backlog") != null);
}
