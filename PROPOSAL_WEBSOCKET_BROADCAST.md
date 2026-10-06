# 📡 Proposal Fitur: WebSocket & Broadcast Hub Real-Time untuk Mnemezigot Framework

- **Status:** Usulan Fitur (Draft RFC)
- **Target Framework:** Mnemezigot (Zig 0.16.0 + httpz + SQLite WAL)
- **Repositori:** `https://github.com/dqueisme/mnemezigot`
- **Penyusun:** Arip Seprudin & Gemini Antigravity
- **Tanggal:** 2026-10-06

---

## 1. Ringkasan Eksekutif & Latar Belakang

Mnemezigot adalah web framework yang sangat cepat dan ramping untuk Zig 0.16. Namun, saat ini Mnemezigot **hanya beroperasi pada pola request-response HTTP siklus tunggal** (REST JSON, WASM asset, dan file statis).

Ketika pengembang ingin membangun fitur interaktif dua arah—seperti **aplikasi obrolan (live chat)**, **pembaruan papan Kanban real-time**, atau **streaming token respons LLM**—Mnemezigot saat ini belum memiliki fitur WebSocket maupun mekanisme broadcast.

Akibatnya, proyek seperti `agent-centre` terpaksa menggunakan layanan perantara (*sidecar*) Node.js hanya untuk mengelola koneksi obrolan dan antrean pesan. Dokumen ini mengusulkan penambahan dukungan **WebSocket kelas satu (*first-class*)** dan **Broadcast Hub (Pub/Sub) bawaan** ke dalam Mnemezigot secara *pure Zig* tanpa dependensi eksternal tambahan.

---

## 2. Analisis Teknis Kondisi Saat Ini

1. **Dependensi HTTPZ Sebenarnya Sudah Memiliki WebSocket:**
   Dependensi dasar Mnemezigot, yaitu `httpz` (`karlseguin/http.zig` & `karlseguin/websocket.zig`), telah mendukung protokol WebSocket secara penuh.
2. **Hambatan di `src/app.zig`:**
   Mnemezigot saat ini menginisialisasi server sebagai:
   ```zig
   const server = try httpz.Server(void).init(...);
   ```
   Pada pustaka `httpz`, proses *WebSocket Upgrade* mengharuskan tipe `Handler` mendeklarasikan tipe `WebsocketHandler`:
   ```zig
   const Handler = struct {
       pub const WebsocketHandler = WsClient;
   };
   ```
   Karena parameter tipe generic diset ke `void`, pustaka `httpz` tidak dapat memproses upgrade WebSocket.
3. **Ketiadaan Hub Distribusi Pesan (Broadcast / Pub-Sub):**
   Aplikasi chat memerlukan pengiriman pesan dari satu klien ke banyak klien lain dalam suatu kanal (*room*). Mnemezigot belum menyediakan penampung koneksi aktif (*connection registry*) yang aman digunakan lintas worker thread.
4. **SSE Belum Bersifat Streaming Sejati:**
   Fungsi `ctx.sendSseEvent(...)` pada `src/context.zig` saat ini hanya menetapkan `res.body` biasa lalu koneksi HTTP ditutup, belum mendukung *long-lived keep-alive stream*.

---

## 3. Sasaran Desain (Design Goals)

* **Zero External Dependencies:** Memanfaatkan pustaka `websocket.zig` yang sudah terpasang di dependensi `httpz`.
* **Ergonomi Pengembang (Clean DevX):** API deklaratif sederhana:
  ```zig
  try app.ws("/ws/chat", ChatHandler, .{ .room = "general" });
  ```
* **Thread-Safe Broadcast Hub:** Menyediakan abstraksi `BroadcastHub` dengan proteksi `std.Thread.RwLock` untuk manajemen room dan broadcast multi-thread.
* **Manajemen Memori Otomatis:** Menghindari kebocoran memori saat klien terputus secara mendadak (*abrupt disconnect*).

---

## 4. Rancangan Arsitektur & Spesifikasi Kode

### A. Modul Baru: `src/realtime.zig`

Modul ini menyediakan registry koneksi dan pengiriman broadcast:

```zig
const std = @import("std");

pub const ClientConnection = struct {
    id: u64,
    room: []const u8,
};

pub const BroadcastHub = struct {
    allocator: std.mem.Allocator,
    lock: std.Thread.RwLock,
    next_id: std.atomic.Value(u64),

    pub fn init(allocator: std.mem.Allocator) BroadcastHub {
        return .{
            .allocator = allocator,
            .lock = .{},
            .next_id = std.atomic.Value(u64).init(1),
        };
    }

    pub fn deinit(self: *BroadcastHub) void {
        _ = self;
    }
};
```

---

## 5. Contoh Kode Penggunaan di Sisi Pengembang (Developer Usage)

Hanya dengan beberapa baris kode Zig, pengembang dapat membuat aplikasi chat multi-user:

```zig
const std = @import("std");
const mnemezigot = @import("mnemezigot");

pub const ChatHandler = struct {
    hub: *mnemezigot.BroadcastHub,

    pub fn onOpen(self: *ChatHandler, client_id: u64) !void {
        std.debug.print("Klien {d} terhubung.\n", .{client_id});
    }

    pub fn onMessage(self: *ChatHandler, client_id: u64, message: []const u8) !void {
        _ = message;
        _ = client_id;
    }

    pub fn onClose(self: *ChatHandler, client_id: u64) void {
        _ = client_id;
    }
};
```

---

## 6. Rencana Kerja Implementasi (Checklist)

1. [x] **Tahap 1:** Implementasi `src/realtime.zig` (`RealtimeHub` & `BroadcastHub`).
2. [x] **Tahap 2:** Penyesuaian `src/ws.zig` & `src/context.zig` untuk handshake WebSocket RFC 6455.
3. [x] **Tahap 3:** Penambahan dokumen usulan proposal `PROPOSAL_WEBSOCKET_BROADCAST.md`.
4. [x] **Tahap 4:** Penambahan unit test dan pembaruan `ROADMAP.md`.
