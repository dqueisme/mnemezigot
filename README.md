# Mnemezigot Framework

**Mnemezigot** adalah fullstack web framework modern dan ultra-cepat untuk **Zig 0.16** yang dirancang sebagai package reusable. Framework ini menggabungkan server berperforma tinggi, database embedded SQLite dengan mode WAL otomatis, dan dukungan penuh untuk WebAssembly (WASM) serta gRPC-Web.

---

## 🌟 Karakteristik Utama

1. **Zero-Config SQLite (HANYA WAL Mode)**:
   - Database otomatis diinisialisasi dengan `PRAGMA journal_mode = WAL;`, `busy_timeout = 5000;`, dan `synchronous = NORMAL;`.
   - Menggunakan embedded SQLite 3.46 C amalgamation dengan thread-safety aktif (`SQLITE_THREADSAFE=1`).
   - Bebas konfigurasi rumit, langsung siap pakai via `ctx.db`.

2. **Hanya 3 Bentuk Keluaran**:
   - **Keluaran 1: Web UI (HTML, CSS & WASM)**: Logika frontend dikompilasi langsung dari Zig ke WebAssembly (`app.wasm` < 10 KB) tanpa overhead framework JS berat.
   - **Keluaran 2: REST API (JSON)**: Serialisasi dan deserialisasi JSON berkecepatan tinggi via `ctx.json(data)` dan `ctx.bindJson(T)`.
   - **Keluaran 3: gRPC (gRPC-Web / Protobuf)**: Komunikasi biner performa tinggi langsung dari browser dengan framing standar HTTP via `ctx.grpcResponse(proto)`.

3. **Single File Entry Point**:
   - Struktur kode sederhana dan ringkas terinspirasi kemudahan web framework modern, di mana backend logic, migrasi database, dan routing terpusat dalam satu file entrypoint.

4. **WASM Client SDK Terintegrasi**:
   - Menyediakan modul `mnemezigot_client` untuk mempermudah komunikasi WASM <-> browser bridge (DOM text update, memory management `alloc`/`free`, dan decode frame gRPC-Web biner).

---

## 📦 Menggunakan Mnemezigot sebagai Package

Tambahkan `mnemezigot` ke `build.zig.zon` pada proyek Anda:

```zig
.{
    .name = .my_app,
    .version = "0.1.0",
    .fingerprint = 0x...,
    .dependencies = .{
        .mnemezigot = .{
            .url = "https://github.com/dqueisme/mnemezigot/archive/refs/heads/master.tar.gz",
            .hash = "...", // atau .path = "../mnemezigot" untuk pengembangan lokal
        },
    },
    .paths = .{ "" },
}
```

Pada `build.zig` aplikasi Anda:

```zig
const mn_dep = b.dependency("mnemezigot", .{
    .target = target,
    .optimize = optimize,
});

// Import backend server module
server.root_module.addImport("mnemezigot", mn_dep.module("mnemezigot"));

// Import WASM client module (untuk target wasm32-freestanding)
wasm.root_module.addImport("mnemezigot_client", mn_dep.module("mnemezigot_client"));
```

---

## 🚀 Contoh Penggunaan (Single File Backend)

```zig
const std = @import("std");
const mn = @import("mnemezigot");

fn handleIndex(ctx: *mn.Context) !void {
    try ctx.html("<h1>Halo dari Mnemezigot Framework!</h1>");
}

fn handleGetStats(ctx: *mn.Context) !void {
    const total = try ctx.db.queryScalarInt("SELECT COUNT(*) FROM users;");
    try ctx.json(.{
        .status = "ok",
        .total_users = total,
        .engine = "SQLite WAL",
    });
}

pub fn main() !void {
    const allocator = std.heap.smp_allocator;

    var app = try mn.App.init(allocator, .{
        .port = 8080,
        .db_path = "data/app.db", // Otomatis WAL mode aktif
    });
    defer app.deinit();

    // 1. Skema SQLite
    try app.db.exec("CREATE TABLE IF NOT EXISTS users (id INTEGER PRIMARY KEY, name TEXT);");

    // 2. Registrasi Routing
    try app.get("/", handleIndex);
    try app.get("/api/stats", handleGetStats);

    // 3. Jalankan Server
    try app.listen();
}
```

---

## 📁 Struktur Repositori Framework

```text
mnemezigot/
├── build.zig               # Export modules: "mnemezigot" & "mnemezigot_client"
├── build.zig.zon           # Package manifest
├── c/                      # SQLite 3.46 C Amalgamation
│   ├── sqlite3.c
│   ├── sqlite3.h
│   └── sqlite3ext.h
├── src/                    # Source code Framework Core
│   ├── mnemezigot.zig      # Entrypoint package library
│   ├── app.zig             # Server Engine (httpz wrapper & routing)
│   ├── context.zig         # Context (HTML, CSS, WASM, JSON, gRPC responses)
│   ├── db.zig              # Zero-Config SQLite WAL Engine
│   ├── grpc.zig            # gRPC-Web framing & Protobuf encoding
│   └── client.zig          # WASM Frontend Client SDK
├── starter/                # Template Starter Project Resmi (mnemezigot-starter)
├── examples/               # Contoh Implementasi Aplikasi Lengkap
│   └── admin-dashboard/    # Full app: Landing page, auth, dan admin dashboard
└── STYLEGUIDE.md           # Panduan styling UI (CSS variables, semantic classes)
```

---

## 🎯 Starter Template

Untuk langsung memulai proyek baru berbasis Mnemezigot tanpa menulis boilerplate, gunakan template resmi di folder [`starter/`](starter/):
- Sudah terkonfigurasi dengan backend server Zig.
- Frontend WebAssembly (`app.wasm` < 3 KB) dengan browser bridge JS.
- Styling semantic CSS patuh pada [`STYLEGUIDE.md`](STYLEGUIDE.md).
- Menjalankan 3 bentuk keluaran secara live.

---

## 🗺️ Feature Roadmap

Untuk melihat daftar lengkap rekomendasi dan rencana pengembangan fitur Mnemezigot Framework ke depannya, silakan pelajari dokumen [`ROADMAP.md`](ROADMAP.md).

---

## 🧪 Pengujian Unit Framework

Untuk menjalankan seluruh unit test framework:
```bash
zig build test
```
