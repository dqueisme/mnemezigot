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

pub const ProjectSummary = struct {
    id: []const u8,
    name: []const u8,
    filename: ?[]const u8 = null,
    total_cards: usize = 0,
    done_cards: usize = 0,
    in_progress_cards: usize = 0,
    backlog_cards: usize = 0,
    completion_rate: f64 = 0.0,
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

    /// Render the Kanban board in modern, robust 2-Pane Master-Detail layout (tui-design Archetype B)
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

        // 1. Render Modal Overlay if active
        if (self.show_modal) {
            try self.renderModal(arena, writer, width);
            return;
        }

        // 2. Top Header Band with Interactive Column Tabs (Archetype B Header)
        var head_buf: std.ArrayList(u8) = .empty;
        var hw = style_mod.bufferWriter(arena, &head_buf);

        try hw.print(" \x1b[1;96m📋 {s}\x1b[0m \x1b[90m│\x1b[0m", .{self.title});

        for (self.columns.items, 0..) |col, c_idx| {
            const is_col = (c_idx == self.selected_col);
            const num = c_idx + 1;
            const icon = col.icon orelse "📌";
            if (is_col) {
                try hw.print(" \x1b[7;1;36m [{d}] {s} {s} ({d}) \x1b[0m", .{ num, icon, col.title, col.cards.items.len });
            } else {
                try hw.print(" \x1b[90m[{d}] {s}\x1b[0m \x1b[37m{s}\x1b[0m \x1b[90m({d})\x1b[0m", .{ num, icon, col.title, col.cards.items.len });
            }
        }

        const head_vis_w = stringWidth(head_buf.items);
        try writer.writeAll(head_buf.items);

        // Far right board / subtitle meta
        if (self.subtitle) |sub| {
            const sub_vis_w = stringWidth(sub) + 2;
            if (width > head_vis_w + sub_vis_w) {
                for (0..(width - head_vis_w - sub_vis_w)) |_| try writer.writeAll(" ");
                try writer.print("\x1b[90m{s}\x1b[0m  \n", .{sub});
            } else {
                try writer.writeAll("\n");
            }
        } else {
            try writer.writeAll("\n");
        }

        // 3. Compute Split Widths
        var left_w = (width * 38) / 100;
        if (left_w < 30) left_w = 30;
        if (left_w > 42) left_w = 42;
        const right_w = if (width > left_w) width - left_w else 30;

        const left_inner_w = if (left_w >= 2) left_w - 2 else 28;
        const right_inner_w = if (right_w >= 2) right_w - 2 else 28;

        const body_height = if (height > 4) height - 4 else 15;
        const avail_card_rows = if (body_height >= 2) body_height - 2 else 10;

        const active_col = &self.columns.items[self.selected_col];

        // 4. Build Left Pane Lines (Card List)
        var left_lines = std.ArrayList([]const u8).empty;

        // Top Border of Left Pane
        var ltop_buf: std.ArrayList(u8) = .empty;
        var ltw = style_mod.bufferWriter(arena, &ltop_buf);
        const ltitle = try std.fmt.allocPrint(arena, "╭─ KARTU: {s} ({d}) ", .{ active_col.title, active_col.cards.items.len });
        try ltw.print("\x1b[1;36m{s}", .{ltitle});
        const ltitle_vis = stringWidth(ltitle);
        if (left_w > ltitle_vis + 1) {
            for (0..(left_w - ltitle_vis - 1)) |_| try ltw.writeAll("─");
        }
        try ltw.writeAll("╮\x1b[0m");
        try left_lines.append(arena, ltop_buf.items);

        // Card items
        if (active_col.cards.items.len == 0) {
            var empty_buf: std.ArrayList(u8) = .empty;
            var ew = style_mod.bufferWriter(arena, &empty_buf);
            try ew.writeAll("\x1b[1;36m│\x1b[0m \x1b[90m(Belum ada kartu di kolom ini)\x1b[0m");
            const evis = stringWidth(" (Belum ada kartu di kolom ini)");
            if (left_inner_w > evis) {
                for (0..(left_inner_w - evis)) |_| try ew.writeAll(" ");
            }
            try ew.writeAll("\x1b[1;36m│\x1b[0m");
            try left_lines.append(arena, empty_buf.items);
        } else {
            var scroll_start: usize = 0;
            if (self.selected_card >= avail_card_rows) {
                scroll_start = self.selected_card - avail_card_rows + 1;
            }
            const scroll_end = @min(active_col.cards.items.len, scroll_start + avail_card_rows);

            for (active_col.cards.items[scroll_start..scroll_end], scroll_start..) |card, k_idx| {
                const is_card = (k_idx == self.selected_card);
                const max_title_w = if (left_inner_w >= 14) left_inner_w - 14 else 10;
                const trunc_title = try truncateWidth(arena, card.title, max_title_w);

                var badge_glyph: []const u8 = "  ";
                if (card.badge) |bdg| {
                    if (std.mem.indexOf(u8, bdg.text, "Kritis") != null) {
                        badge_glyph = "🔴";
                    } else if (std.mem.indexOf(u8, bdg.text, "Penting") != null) {
                        badge_glyph = "🟡";
                    } else if (std.mem.indexOf(u8, bdg.text, "Rendah") != null) {
                        badge_glyph = "🟢";
                    }
                }

                var card_item_buf: std.ArrayList(u8) = .empty;
                var cw = style_mod.bufferWriter(arena, &card_item_buf);

                try cw.writeAll("\x1b[1;36m│\x1b[0m");
                if (is_card) {
                    try cw.print("\x1b[7;1;36m❯\x1b[0m \x1b[1;97m#{s} {s} {s}\x1b[0m", .{ card.id, badge_glyph, trunc_title });
                } else {
                    try cw.print("  \x1b[90m#{s}\x1b[0m \x1b[37m{s} {s}\x1b[0m", .{ card.id, badge_glyph, trunc_title });
                }

                // Pad row
                const prefix_w: usize = 2;
                const cur_item_vis = prefix_w + 1 + stringWidth(card.id) + 1 + stringWidth(badge_glyph) + 1 + stringWidth(trunc_title);
                if (left_inner_w > cur_item_vis) {
                    for (0..(left_inner_w - cur_item_vis)) |_| try cw.writeAll(" ");
                }
                try cw.writeAll("\x1b[1;36m│\x1b[0m");
                try left_lines.append(arena, card_item_buf.items);
            }
        }

        // Fill remaining card rows in left pane
        while (left_lines.items.len < avail_card_rows + 1) {
            var pad_buf: std.ArrayList(u8) = .empty;
            var pw = style_mod.bufferWriter(arena, &pad_buf);
            try pw.writeAll("\x1b[1;36m│\x1b[0m");
            for (0..left_inner_w) |_| try pw.writeAll(" ");
            try pw.writeAll("\x1b[1;36m│\x1b[0m");
            try left_lines.append(arena, pad_buf.items);
        }

        // Bottom Border of Left Pane
        var lbot_buf: std.ArrayList(u8) = .empty;
        var lbw = style_mod.bufferWriter(arena, &lbot_buf);
        const card_count = active_col.cards.items.len;
        const cur_pos = if (card_count > 0) self.selected_card + 1 else 0;
        const pos_label = try std.fmt.allocPrint(arena, " {d} of {d} ─╯", .{ cur_pos, card_count });
        try lbw.writeAll("\x1b[1;36m╰");
        const pos_vis = stringWidth(pos_label);
        if (left_w > pos_vis + 1) {
            for (0..(left_w - pos_vis - 1)) |_| try lbw.writeAll("─");
        }
        try lbw.print("\x1b[90m{s}\x1b[0m", .{pos_label});
        try left_lines.append(arena, lbot_buf.items);

        // 5. Build Right Pane Lines (Card Detail Viewer / Live Inspector)
        var right_lines = std.ArrayList([]const u8).empty;

        const card_opt = self.getSelectedCard();
        if (card_opt) |card| {
            // Box top
            var rtop_buf: std.ArrayList(u8) = .empty;
            var rtw = style_mod.bufferWriter(arena, &rtop_buf);
            const rtop_title = try std.fmt.allocPrint(arena, "╭─ #{s} ─", .{card.id});
            try rtw.print("\x1b[90m{s}", .{rtop_title});
            const rtop_vis = stringWidth(rtop_title);
            const status_pill = try std.fmt.allocPrint(arena, " 🔍 LIVE INSPECTOR: {s} ─╮", .{active_col.title});
            const pill_vis = stringWidth(status_pill);

            if (right_w > rtop_vis + pill_vis) {
                for (0..(right_w - rtop_vis - pill_vis)) |_| try rtw.writeAll("─");
                try rtw.print("\x1b[36m{s}\x1b[0m", .{status_pill});
            } else {
                if (right_w > rtop_vis + 1) {
                    for (0..(right_w - rtop_vis - 1)) |_| try rtw.writeAll("─");
                }
                try rtw.writeAll("╮\x1b[0m");
            }
            try right_lines.append(arena, rtop_buf.items);

            // Title line (wrapped)
            const detail_content_w = if (right_inner_w >= 14) right_inner_w - 14 else 15;
            var title_lines = std.ArrayList([]const u8).empty;
            try wrapText(arena, card.title, detail_content_w, &title_lines);

            for (title_lines.items, 0..) |tline, idx| {
                var tl_buf: std.ArrayList(u8) = .empty;
                var tw = style_mod.bufferWriter(arena, &tl_buf);
                try tw.writeAll("\x1b[90m│\x1b[0m ");
                if (idx == 0) {
                    try tw.print("\x1b[90mJudul     :\x1b[0m \x1b[1;97m{s}\x1b[0m", .{tline});
                    const tvis = 12 + stringWidth(tline);
                    if (right_inner_w > tvis) for (0..(right_inner_w - tvis)) |_| try tw.writeAll(" ");
                } else {
                    try tw.print("            \x1b[1;97m{s}\x1b[0m", .{tline});
                    const tvis = 12 + stringWidth(tline);
                    if (right_inner_w > tvis) for (0..(right_inner_w - tvis)) |_| try tw.writeAll(" ");
                }
                try tw.writeAll(" \x1b[90m│\x1b[0m");
                try right_lines.append(arena, tl_buf.items);
            }

            // Column row
            {
                var cl_buf: std.ArrayList(u8) = .empty;
                var cw = style_mod.bufferWriter(arena, &cl_buf);
                try cw.writeAll("\x1b[90m│\x1b[0m ");
                const icon = active_col.icon orelse "📌";
                try cw.print("\x1b[90mKolom     :\x1b[0m \x1b[36m{s} {s}\x1b[0m", .{ icon, active_col.title });
                const cvis = 12 + stringWidth(icon) + 1 + stringWidth(active_col.title);
                if (right_inner_w > cvis) for (0..(right_inner_w - cvis)) |_| try cw.writeAll(" ");
                try cw.writeAll(" \x1b[90m│\x1b[0m");
                try right_lines.append(arena, cl_buf.items);
            }

            // Priority badge row
            if (card.badge) |bdg| {
                var bl_buf: std.ArrayList(u8) = .empty;
                var bw = style_mod.bufferWriter(arena, &bl_buf);
                try bw.writeAll("\x1b[90m│\x1b[0m ");
                try bw.print("\x1b[90mPrioritas :\x1b[0m \x1b[1;93m[{s}]\x1b[0m", .{bdg.text});
                const bvis = 12 + stringWidth(bdg.text) + 2;
                if (right_inner_w > bvis) for (0..(right_inner_w - bvis)) |_| try bw.writeAll(" ");
                try bw.writeAll(" \x1b[90m│\x1b[0m");
                try right_lines.append(arena, bl_buf.items);
            }

            // Date row
            if (card.date) |dt| {
                var dl_buf: std.ArrayList(u8) = .empty;
                var dw = style_mod.bufferWriter(arena, &dl_buf);
                try dw.writeAll("\x1b[90m│\x1b[0m ");
                try dw.print("\x1b[90mTanggal   :\x1b[0m \x1b[90m{s}\x1b[0m", .{dt});
                const dvis = 12 + stringWidth(dt);
                if (right_inner_w > dvis) for (0..(right_inner_w - dvis)) |_| try dw.writeAll(" ");
                try dw.writeAll(" \x1b[90m│\x1b[0m");
                try right_lines.append(arena, dl_buf.items);
            }

            // Metadata row
            if (card.metadata) |meta| {
                var ml_buf: std.ArrayList(u8) = .empty;
                var mw = style_mod.bufferWriter(arena, &ml_buf);
                try mw.writeAll("\x1b[90m│\x1b[0m ");
                try mw.print("\x1b[90mPapan     :\x1b[0m \x1b[35m{s}\x1b[0m", .{meta});
                const mvis = 12 + stringWidth(meta);
                if (right_inner_w > mvis) for (0..(right_inner_w - mvis)) |_| try mw.writeAll(" ");
                try mw.writeAll(" \x1b[90m│\x1b[0m");
                try right_lines.append(arena, ml_buf.items);
            }

            // Section divider
            var rdiv_buf: std.ArrayList(u8) = .empty;
            var rdw = style_mod.bufferWriter(arena, &rdiv_buf);
            try rdw.writeAll("\x1b[90m├─ \x1b[1;92mCatatan & Uraian Teknis\x1b[0m \x1b[90m");
            const div_title_vis = stringWidth("├─ Catatan & Uraian Teknis ");
            if (right_w > div_title_vis + 1) {
                for (0..(right_w - div_title_vis - 1)) |_| try rdw.writeAll("─");
            }
            try rdw.writeAll("┤\x1b[0m");
            try right_lines.append(arena, rdiv_buf.items);

            // Notes body
            if (card.details) |det| {
                var wrapped_notes = std.ArrayList([]const u8).empty;
                const note_inner_w = if (right_inner_w >= 4) right_inner_w - 4 else 15;
                try wrapText(arena, det, note_inner_w, &wrapped_notes);

                const max_note_lines = if (body_height > right_lines.items.len + 2) body_height - right_lines.items.len - 2 else 4;
                for (wrapped_notes.items[0..@min(wrapped_notes.items.len, max_note_lines)]) |nline| {
                    var nl_buf: std.ArrayList(u8) = .empty;
                    var nw = style_mod.bufferWriter(arena, &nl_buf);
                    try nw.print("\x1b[90m│\x1b[0m   \x1b[37m{s}\x1b[0m", .{nline});
                    const nvis = 3 + stringWidth(nline);
                    if (right_inner_w > nvis) for (0..(right_inner_w - nvis)) |_| try nw.writeAll(" ");
                    try nw.writeAll(" \x1b[90m│\x1b[0m");
                    try right_lines.append(arena, nl_buf.items);
                }
                if (wrapped_notes.items.len > max_note_lines) {
                    var cut_buf: std.ArrayList(u8) = .empty;
                    var cw = style_mod.bufferWriter(arena, &cut_buf);
                    try cw.writeAll("\x1b[90m│   ... (uraian dipotong untuk preview live)");
                    const cvis = stringWidth("   ... (uraian dipotong untuk preview live)");
                    if (right_inner_w > cvis) for (0..(right_inner_w - cvis)) |_| try cw.writeAll(" ");
                    try cw.writeAll(" │\x1b[0m");
                    try right_lines.append(arena, cut_buf.items);
                }
            } else {
                var nodet_buf: std.ArrayList(u8) = .empty;
                var nw = style_mod.bufferWriter(arena, &nodet_buf);
                try nw.writeAll("\x1b[90m│   (Tidak ada catatan tambahan untuk kartu ini)");
                const nvis = stringWidth("   (Tidak ada catatan tambahan untuk kartu ini)");
                if (right_inner_w > nvis) for (0..(right_inner_w - nvis)) |_| try nw.writeAll(" ");
                try nw.writeAll(" │\x1b[0m");
                try right_lines.append(arena, nodet_buf.items);
            }

            // Fill remaining lines in right pane
            while (right_lines.items.len < avail_card_rows + 1) {
                var pad_buf: std.ArrayList(u8) = .empty;
                var pw = style_mod.bufferWriter(arena, &pad_buf);
                try pw.writeAll("\x1b[90m│\x1b[0m");
                for (0..right_inner_w) |_| try pw.writeAll(" ");
                try pw.writeAll("\x1b[90m│\x1b[0m");
                try right_lines.append(arena, pad_buf.items);
            }

            // Box bottom
            var rbot_buf: std.ArrayList(u8) = .empty;
            var rbw = style_mod.bufferWriter(arena, &rbot_buf);
            try rbw.writeAll("\x1b[90m╰");
            if (right_w >= 2) {
                for (0..(right_w - 2)) |_| try rbw.writeAll("─");
            }
            try rbw.writeAll("╯\x1b[0m");
            try right_lines.append(arena, rbot_buf.items);
        } else {
            // Empty right pane
            var rtop_buf: std.ArrayList(u8) = .empty;
            var rtw = style_mod.bufferWriter(arena, &rtop_buf);
            const rtop_title = try std.fmt.allocPrint(arena, "╭─ 🔍 LIVE INSPECTOR: {s} ─", .{active_col.title});
            try rtw.print("\x1b[90m{s}", .{rtop_title});
            const rtop_vis = stringWidth(rtop_title);
            if (right_w > rtop_vis + 1) {
                for (0..(right_w - rtop_vis - 1)) |_| try rtw.writeAll("─");
            }
            try rtw.writeAll("╮\x1b[0m");
            try right_lines.append(arena, rtop_buf.items);

            var em_buf: std.ArrayList(u8) = .empty;
            var ew = style_mod.bufferWriter(arena, &em_buf);
            try ew.writeAll("\x1b[90m│  (Pilih salah satu kartu pada pane kiri untuk membaca rincian)");
            const evis = stringWidth("  (Pilih salah satu kartu pada pane kiri untuk membaca rincian)");
            if (right_inner_w > evis) for (0..(right_inner_w - evis)) |_| try ew.writeAll(" ");
            try ew.writeAll(" │\x1b[0m");
            try right_lines.append(arena, em_buf.items);

            while (right_lines.items.len < avail_card_rows + 1) {
                var pad_buf: std.ArrayList(u8) = .empty;
                var pw = style_mod.bufferWriter(arena, &pad_buf);
                try pw.writeAll("\x1b[90m│\x1b[0m");
                for (0..right_inner_w) |_| try pw.writeAll(" ");
                try pw.writeAll("\x1b[90m│\x1b[0m");
                try right_lines.append(arena, pad_buf.items);
            }

            var rbot_buf: std.ArrayList(u8) = .empty;
            var rbw = style_mod.bufferWriter(arena, &rbot_buf);
            try rbw.writeAll("\x1b[90m╰");
            for (0..(right_w - 2)) |_| try rbw.writeAll("─");
            try rbw.writeAll("╯\x1b[0m");
            try right_lines.append(arena, rbot_buf.items);
        }

        // 6. Merge Left and Right Lines Row by Row
        const total_render_rows = @min(body_height, @max(left_lines.items.len, right_lines.items.len));

        for (0..total_render_rows) |r| {
            if (r < left_lines.items.len) {
                try writer.writeAll(left_lines.items[r]);
            } else {
                for (0..left_w) |_| try writer.writeAll(" ");
            }

            if (r < right_lines.items.len) {
                try writer.writeAll(right_lines.items[r]);
            } else {
                for (0..right_w) |_| try writer.writeAll(" ");
            }

            try writer.writeAll("\n");
        }

        // 7. Message Status Line (Row height - 2)
        if (self.stats_summary) |stats| {
            try writer.print(" \x1b[32m✓\x1b[0m \x1b[37m{s}\x1b[0m \x1b[90m· Obsidian Vault tersinkronisasi\x1b[0m\n", .{stats});
        } else {
            try writer.writeAll(" \x1b[32m✓\x1b[0m \x1b[37mObsidian Vault tersinkronisasi\x1b[0m\n");
        }

        // 8. Keybar Footer (Row height - 1)
        try writer.writeAll(" \x1b[1;96m1-4\x1b[0m \x1b[37mkolom\x1b[0m   \x1b[1;96mTab\x1b[0m \x1b[37mganti\x1b[0m   \x1b[1;96m↑↓/jk\x1b[0m \x1b[37mpilih\x1b[0m   \x1b[1;96mSpace\x1b[0m \x1b[37mmodal\x1b[0m   \x1b[1;96mr\x1b[0m \x1b[37mreload\x1b[0m   \x1b[1;96mq\x1b[0m \x1b[37mkeluar\x1b[0m\n");
    }

    /// Render Project Selection screen (Step 1 of the 3-step Kanban flow)
    pub fn renderProjectPicker(
        self: *const KanbanBoard,
        writer: anytype,
        projects: []const ProjectSummary,
        selected_project: usize,
        term_width: u16,
        term_height: u16,
    ) !void {
        var arena_state = std.heap.ArenaAllocator.init(self.allocator);
        defer arena_state.deinit();
        const arena = arena_state.allocator();

        const width: usize = @max(@as(usize, term_width), 60);
        const height: usize = @max(@as(usize, term_height), 20);

        // 1. Top Header Band
        var head_buf: std.ArrayList(u8) = .empty;
        var hw = style_mod.bufferWriter(arena, &head_buf);
        try hw.print(" \x1b[1;96m📋 {s}\x1b[0m \x1b[90m│\x1b[0m \x1b[1;97mPILIH PROYEK KANBAN\x1b[0m", .{self.title});
        const head_vis = stringWidth(head_buf.items);
        try writer.writeAll(head_buf.items);

        const count_tag = try std.fmt.allocPrint(arena, "{d} Proyek ", .{projects.len});
        const tag_vis = stringWidth(count_tag);
        if (width > head_vis + tag_vis) {
            for (0..(width - head_vis - tag_vis)) |_| try writer.writeAll(" ");
            try writer.print("\x1b[90m{s}\x1b[0m\n", .{count_tag});
        } else {
            try writer.writeAll("\n");
        }

        // 2. Project List Panel Box
        const body_height = if (height > 4) height - 4 else 15;
        const box_inner_w = if (width >= 4) width - 4 else 56;

        var top_buf: std.ArrayList(u8) = .empty;
        var tw = style_mod.bufferWriter(arena, &top_buf);
        const top_title = try std.fmt.allocPrint(arena, "╭─ 📁 DAFTAR PROYEK KANBAN ({d}) ", .{projects.len});
        try tw.print("\x1b[1;36m{s}", .{top_title});
        const top_vis = stringWidth(top_title);
        if (width > top_vis + 1) {
            for (0..(width - top_vis - 1)) |_| try tw.writeAll("─");
        }
        try tw.writeAll("╮\x1b[0m\n");
        try writer.writeAll(top_buf.items);

        const avail_rows = if (body_height >= 2) body_height - 2 else 10;
        var row_count: usize = 0;

        for (projects, 0..) |p, idx| {
            if (row_count >= avail_rows) break;
            const is_sel = (idx == selected_project);

            var row_buf: std.ArrayList(u8) = .empty;
            var rw = style_mod.bufferWriter(arena, &row_buf);
            try rw.writeAll("\x1b[1;36m│\x1b[0m ");

            const prefix = if (is_sel) "\x1b[7;1;36m❯\x1b[0m " else "  ";
            const name_styled = if (is_sel)
                try std.fmt.allocPrint(arena, "\x1b[1;97m📋 {s}\x1b[0m", .{p.name})
            else
                try std.fmt.allocPrint(arena, "\x1b[37m📋 {s}\x1b[0m", .{p.name});

            const stat_str = try std.fmt.allocPrint(arena, "{d} kartu · {d} selesai ({d:.1}%)", .{ p.total_cards, p.done_cards, p.completion_rate });
            const sum_str = try std.fmt.allocPrint(arena, "{d} Backlog · {d} In Progress", .{ p.backlog_cards, p.in_progress_cards });

            try rw.print("{s}{s}  \x1b[36m{s}\x1b[0m  \x1b[90m({s})\x1b[0m", .{ prefix, name_styled, stat_str, sum_str });

            const row_vis: usize = 2 + 1 + 2 + 1 + stringWidth(p.name) + 2 + stringWidth(stat_str) + 3 + stringWidth(sum_str) + 1;
            if (box_inner_w > row_vis) {
                for (0..(box_inner_w - row_vis)) |_| try rw.writeAll(" ");
            }
            try rw.writeAll(" \x1b[1;36m│\x1b[0m\n");
            try writer.writeAll(row_buf.items);
            row_count += 1;
        }

        while (row_count < avail_rows) : (row_count += 1) {
            try writer.writeAll("\x1b[1;36m│\x1b[0m");
            for (0..box_inner_w + 2) |_| try writer.writeAll(" ");
            try writer.writeAll("\x1b[1;36m│\x1b[0m\n");
        }

        // Bottom border
        var bot_buf: std.ArrayList(u8) = .empty;
        var bw = style_mod.bufferWriter(arena, &bot_buf);
        const cur_p = if (projects.len > 0) selected_project + 1 else 0;
        const pos_label = try std.fmt.allocPrint(arena, " {d} of {d} ─╯", .{ cur_p, projects.len });
        try bw.writeAll("\x1b[1;36m╰");
        const pos_vis = stringWidth(pos_label);
        if (width > pos_vis + 1) {
            for (0..(width - pos_vis - 1)) |_| try bw.writeAll("─");
        }
        try bw.print("\x1b[90m{s}\x1b[0m\n", .{pos_label});
        try writer.writeAll(bot_buf.items);

        // 3. Message Status Line
        try writer.print(" \x1b[32m✓\x1b[0m \x1b[37mObsidian Vault terhubung · {d} berkas papan di Boards/\x1b[0m\n", .{projects.len});

        // 4. Keybar Footer
        try writer.writeAll(" \x1b[1;96m↑↓/jk\x1b[0m \x1b[37mpilih proyek\x1b[0m   \x1b[1;96mEnter\x1b[0m \x1b[37mbuka proyek\x1b[0m   \x1b[1;96mr\x1b[0m \x1b[37mreload\x1b[0m   \x1b[1;96mq\x1b[0m \x1b[37mkeluar\x1b[0m\n");
    }

    /// Render Column Overview & Card Counts screen (Step 2 of the 3-step Kanban flow)
    pub fn renderColumnOverview(
        self: *const KanbanBoard,
        writer: anytype,
        project_name: []const u8,
        filename: ?[]const u8,
        selected_col_idx: usize,
        term_width: u16,
        term_height: u16,
    ) !void {
        var arena_state = std.heap.ArenaAllocator.init(self.allocator);
        defer arena_state.deinit();
        const arena = arena_state.allocator();

        const width: usize = @max(@as(usize, term_width), 60);
        _ = term_height;

        // 1. Top Header Band
        var head_buf: std.ArrayList(u8) = .empty;
        var hw = style_mod.bufferWriter(arena, &head_buf);
        try hw.print(" \x1b[1;96m📋 {s}\x1b[0m \x1b[90m│\x1b[0m \x1b[1;95mProyek: {s}\x1b[0m", .{ self.title, project_name });
        const head_vis = stringWidth(head_buf.items);
        try writer.writeAll(head_buf.items);

        if (filename) |f| {
            const f_vis = stringWidth(f) + 2;
            if (width > head_vis + f_vis) {
                for (0..(width - head_vis - f_vis)) |_| try writer.writeAll(" ");
                try writer.print("\x1b[90m{s}\x1b[0m  \n", .{f});
            } else {
                try writer.writeAll("\n");
            }
        } else {
            try writer.writeAll("\n");
        }

        const box_inner_w = if (width >= 4) width - 4 else 56;

        // 2. Upper Panel: Column Summary Box
        var ctop_buf: std.ArrayList(u8) = .empty;
        var ctw = style_mod.bufferWriter(arena, &ctop_buf);
        const col_box_title = "╭─ 📊 RINGKASAN KOLOM & JUMLAH KARTU ";
        try ctw.print("\x1b[1;36m{s}", .{col_box_title});
        const ctop_vis = stringWidth(col_box_title);
        if (width > ctop_vis + 1) {
            for (0..(width - ctop_vis - 1)) |_| try ctw.writeAll("─");
        }
        try ctw.writeAll("╮\x1b[0m\n");
        try writer.writeAll(ctop_buf.items);

        var total_cards: usize = 0;
        var done_cards: usize = 0;

        for (self.columns.items, 0..) |col, idx| {
            const is_sel = (idx == selected_col_idx);
            const num = idx + 1;
            const icon = col.icon orelse "📌";
            const count = col.cards.items.len;
            total_cards += count;
            if (std.mem.indexOf(u8, col.id, "done") != null or std.mem.indexOf(u8, col.title, "Done") != null) {
                done_cards += count;
            }

            // Meter bar (dots or blocks)
            const meter_dots: usize = @min(count, 30);
            var meter_buf: [32]u8 = undefined;
            for (0..meter_dots) |m| meter_buf[m] = '=';
            const meter_str = meter_buf[0..meter_dots];

            var crow_buf: std.ArrayList(u8) = .empty;
            var crw = style_mod.bufferWriter(arena, &crow_buf);
            try crw.writeAll("\x1b[1;36m│\x1b[0m ");

            if (is_sel) {
                try crw.print("\x1b[7;1;36m❯\x1b[0m \x1b[1;97m[{d}] {s} {s}\x1b[0m  \x1b[1;93m{d} kartu\x1b[0m  \x1b[36m[{s}]\x1b[0m", .{ num, icon, col.title, count, meter_str });
            } else {
                try crw.print("  \x1b[90m[{d}]\x1b[0m \x1b[37m{s} {s}\x1b[0m  \x1b[90m{d} kartu  [{s}]\x1b[0m", .{ num, icon, col.title, count, meter_str });
            }

            const row_vis: usize = 2 + 1 + 3 + 1 + stringWidth(icon) + 1 + stringWidth(col.title) + 2 + 6 + 2 + 1 + meter_dots + 1;
            if (box_inner_w > row_vis) {
                for (0..(box_inner_w - row_vis)) |_| try crw.writeAll(" ");
            }
            try crw.writeAll(" \x1b[1;36m│\x1b[0m\n");
            try writer.writeAll(crow_buf.items);
        }

        // Bottom border of Column Summary Box
        var cbot_buf: std.ArrayList(u8) = .empty;
        var cbw = style_mod.bufferWriter(arena, &cbot_buf);
        const cur_c = if (self.columns.items.len > 0) selected_col_idx + 1 else 0;
        const cpos_label = try std.fmt.allocPrint(arena, " {d} of {d} ─╯", .{ cur_c, self.columns.items.len });
        try cbw.writeAll("\x1b[1;36m╰");
        const cpos_vis = stringWidth(cpos_label);
        if (width > cpos_vis + 1) {
            for (0..(width - cpos_vis - 1)) |_| try cbw.writeAll("─");
        }
        try cbw.print("\x1b[90m{s}\x1b[0m\n", .{cpos_label});
        try writer.writeAll(cbot_buf.items);

        // 3. Lower Panel: Project Stats Box
        const comp_pct: f64 = if (total_cards > 0) (@as(f64, @floatFromInt(done_cards)) / @as(f64, @floatFromInt(total_cards))) * 100.0 else 0.0;
        var stop_buf: std.ArrayList(u8) = .empty;
        var stw = style_mod.bufferWriter(arena, &stop_buf);
        const stat_box_title = "╭─ 📈 STATISTIK RINGKAS PROYEK ";
        try stw.print("\x1b[90m{s}", .{stat_box_title});
        const stop_vis = stringWidth(stat_box_title);
        if (width > stop_vis + 1) {
            for (0..(width - stop_vis - 1)) |_| try stw.writeAll("─");
        }
        try stw.writeAll("╮\x1b[0m\n");
        try writer.writeAll(stop_buf.items);

        // Stat lines
        const line1 = try std.fmt.allocPrint(arena, "  \x1b[90mTotal Kartu :\x1b[0m \x1b[1;97m{d} kartu\x1b[0m", .{total_cards});
        const line2 = try std.fmt.allocPrint(arena, "  \x1b[90mPenyelesaian:\x1b[0m \x1b[1;92m{d} kartu ({d:.1}% selesai)\x1b[0m", .{ done_cards, comp_pct });

        for ([_][]const u8{ line1, line2 }) |line| {
            try writer.print("\x1b[90m│\x1b[0m{s}", .{line});
            const lvis: usize = 2 + stringWidth(line);
            if (box_inner_w > lvis) {
                for (0..(box_inner_w - lvis)) |_| try writer.writeAll(" ");
            }
            try writer.writeAll(" \x1b[90m│\x1b[0m\n");
        }

        // Bottom of stat box
        var sbot_buf: std.ArrayList(u8) = .empty;
        var sbw = style_mod.bufferWriter(arena, &sbot_buf);
        try sbw.writeAll("\x1b[90m╰");
        if (width >= 2) {
            for (0..(width - 2)) |_| try sbw.writeAll("─");
        }
        try sbw.writeAll("╯\x1b[0m\n");
        try writer.writeAll(sbot_buf.items);

        // 4. Message Status Line
        try writer.writeAll(" \x1b[32m✓\x1b[0m \x1b[37mPilih salah satu kolom untuk menampilkan list tugas\x1b[0m\n");

        // 5. Keybar Footer
        try writer.writeAll(" \x1b[1;96m1-4/↑↓\x1b[0m \x1b[37mpilih kolom\x1b[0m   \x1b[1;96mEnter\x1b[0m \x1b[37mbuka list tugas\x1b[0m   \x1b[1;96mEsc/b\x1b[0m \x1b[37mganti proyek\x1b[0m   \x1b[1;96mr\x1b[0m \x1b[37mreload\x1b[0m   \x1b[1;96mq\x1b[0m \x1b[37mkeluar\x1b[0m\n");
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

        // Top Rounded Border
        try writer.writeAll("\x1b[1;36m╭─ \x1b[1;97m🔍 RINCIAN KARTU KANBAN (CARD DRAWER)\x1b[0m \x1b[1;36m");
        const title_label = "╭─ 🔍 RINCIAN KARTU KANBAN (CARD DRAWER) ";
        const title_w = stringWidth(title_label);
        if (modal_w > title_w + 1) {
            for (0..(modal_w - title_w - 1)) |_| {
                try writer.writeAll("─");
            }
        }
        try writer.writeAll("╮\x1b[0m\n");

        if (card_opt) |card| {
            try writer.print("\x1b[1;36m│\x1b[0m \x1b[90mID       :\x1b[0m \x1b[1;97m#{s}\x1b[0m\n", .{card.id});
            try writer.print("\x1b[1;36m│\x1b[0m \x1b[90mJudul    :\x1b[0m \x1b[1;97m{s}\x1b[0m\n", .{card.title});

            if (col_opt) |col| {
                const icon = col.icon orelse "📌";
                try writer.print("\x1b[1;36m│\x1b[0m \x1b[90mKolom    :\x1b[0m \x1b[36m{s} {s}\x1b[0m\n", .{ icon, col.title });
            }

            if (card.badge) |bdg| {
                try writer.print("\x1b[1;36m│\x1b[0m \x1b[90mPrioritas:\x1b[0m \x1b[1;93m[{s}]\x1b[0m\n", .{bdg.text});
            }

            if (card.date) |dt| {
                try writer.print("\x1b[1;36m│\x1b[0m \x1b[90mTanggal  :\x1b[0m \x1b[90m{s}\x1b[0m\n", .{dt});
            }

            if (card.metadata) |meta| {
                try writer.print("\x1b[1;36m│\x1b[0m \x1b[90mMetadata :\x1b[0m \x1b[35m{s}\x1b[0m\n", .{meta});
            }

            try writer.writeAll("\x1b[1;36m├─ \x1b[1;92mCatatan / Uraian Teknis\x1b[0m \x1b[1;36m");
            const div_w = stringWidth("├─ Catatan / Uraian Teknis ");
            if (modal_w > div_w + 1) {
                for (0..(modal_w - div_w - 1)) |_| {
                    try writer.writeAll("─");
                }
            }
            try writer.writeAll("┤\x1b[0m\n");

            if (card.details) |det| {
                var line_iter = std.mem.splitScalar(u8, det, '\n');
                var line_count: usize = 0;
                while (line_iter.next()) |line| {
                    if (line_count >= 15) {
                        try writer.writeAll("\x1b[1;36m│\x1b[0m \x1b[90m... (uraian dipotong untuk tampilan modal)\x1b[0m\n");
                        break;
                    }
                    const trunc = try truncateWidth(arena, line, inner_w);
                    try writer.print("\x1b[1;36m│\x1b[0m   \x1b[37m{s}\x1b[0m\n", .{trunc});
                    line_count += 1;
                }
            } else {
                try writer.writeAll("\x1b[1;36m│\x1b[0m   \x1b[90m(Tidak ada rincian tambahan untuk kartu ini)\x1b[0m\n");
            }
        } else {
            try writer.writeAll("\x1b[1;36m│\x1b[0m (Tidak ada kartu yang terpilih)\n");
        }

        try writer.writeAll("\x1b[1;36m├─ \x1b[1;93m[ Tekan ENTER / SPACE / ESC untuk menutup rincian kartu ]\x1b[0m \x1b[1;36m");
        const hint_w = stringWidth("├─ [ Tekan ENTER / SPACE / ESC untuk menutup rincian kartu ] ");
        if (modal_w > hint_w + 1) {
            for (0..(modal_w - hint_w - 1)) |_| {
                try writer.writeAll("─");
            }
        }
        try writer.writeAll("┤\x1b[0m\n");

        try writer.writeAll("\x1b[1;36m╰");
        for (0..(modal_w - 2)) |_| {
            try writer.writeAll("─");
        }
        try writer.writeAll("╯\x1b[0m\n");
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
    try std.testing.expect(std.mem.indexOf(u8, out, "KARTU: Backlog") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "LIVE INSPECTOR") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "Refactor Database WAL") != null);

    // Test Column view rendering
    board.view_mode = .columns;
    buf.clearRetainingCapacity();
    try board.render(w, 80, 24);
    try std.testing.expect(std.mem.indexOf(u8, buf.items, "Backlog") != null);
}
