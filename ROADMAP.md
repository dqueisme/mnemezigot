# 🗺️ Mnemezigot Framework - Feature Roadmap

Dokumen ini berisi peta jalan (roadmap) pengembangan fitur untuk **Mnemezigot Framework**, sebuah fullstack web framework modern dan ultra-cepat menggunakan bahasa **Zig 0.16**.

---

## 🎯 Visi Framework
Mnemezigot dirancang sebagai web framework berperforma tinggi, ringan, dan zero-config dengan fondasi utama:
- **Server HTTP**: Powered by `httpz` & Zig 0.16.
- **Embedded Database**: SQLite 3.46 dengan mode WAL otomatis.
- **Tri-Output Engine**: Web UI (HTML/WASM), REST API (JSON), dan gRPC-Web (Protobuf).

---

## 📋 Rencana Pengembangan Fitur

### 1. 🚀 Core Framework Features (High Priority)

- [x] **Middleware Support & Pipeline System**
  - Arsitektur middleware bertingkat: Global, Route Group, dan Per-Route middleware.
  - Built-in middleware bawaan:
    - `Logger`: Pencatatan HTTP Method, Path, Status Code, dan Response Latency.
    - `CORS`: Pengaturan header `Access-Control-Allow-*` secara fleksibel.
    - `Recovery`: Menangkap panic/error runtime agar server tidak crash.
    - `Auth / Bearer Token`: Extensible middleware untuk verifikasi token JWT / Session.

- [x] **Route Grouping & Sub-Routing**
  - Pengelompokan route berdasarkan prefix dan middleware kolektif.
  - Contoh penggunaan:
    ```zig
    var api = app.group("/api/v1");
    api.use(authMiddleware);
    try api.get("/users", handleGetUsers);
    try api.post("/users", handleCreateUser);
    ```

- [x] **Static File & Embedded Asset Serving**
  - Servis file statis dari direktori lokal (`public/`, `dist/`) atau file terenkapsulasi biner via `@embedFile`.
  - Deteksi *MIME type* otomatis dan dukungan HTTP Caching (`ETag`, `Cache-Control`).

- [x] **Request Context Helpers**
  - **Query Parameters**: Parsing URL query string (`ctx.query("search")`, `ctx.queryInt("page")`).
  - **Cookies**: Helper membaca & menulis cookie dengan atribut keamanan (`HttpOnly`, `SameSite`, `Secure`).
  - **Headers**: Pembacaan header HTTP yang lebih mudah (`ctx.header("User-Agent")`).
  - **Form & Multipart Parsing**: Helper ekstraksi data form-urlencoded dan file upload.

---

### 2. 🗄️ Database & Data Layer Enhancements (Medium-High Priority)

- [x] **Zero-Config Database Migration Engine**
  - Sistem migrasi terstruktur berbasis versi skema (tabel `schema_migrations`) untuk mengelola perubahan skema database SQLite secara aman.

- [x] **Peningkatan ModelQuery (ORM)**
  - Dukungan metode query tambahan:
    - `.update(data)`: Memperbarui record berdasarkan kriteria.
    - `.limit(n)` & `.offset(n)`: Dukungan paginasi.
    - `.orderBy("created_at DESC")`: Pengurutan hasil query.
  - **Database Transactions**: Helper eksekusi transaksi atomis multi-query (`db.transaction(...)`).

---

### 3. 🌐 Real-Time & Output Features (Medium Priority)

- [x] **Server-Sent Events (SSE) & WebSocket Support**
  - Streaming data real-time berbasis event dari backend Zig ke WASM Client / Browser UI secara efisien.

- [x] **Type-Safe HTML Component Builder & HTMX Integration**
  - Helper untuk merender komponen HTML secara type-safe di Zig tanpa overhead template engine berat, dengan integrasi siap pakai untuk HTMX.

---

### 4. 🛠️ Tooling & Developer Experience (DevX)

- [ ] **CLI Watcher / Hot Reload Tool**
  - Utility CLI sederhana untuk auto-rebuild & auto-restart server Mnemezigot saat terjadi perubahan file source code `.zig`.

- [ ] **Project Generator (CLI Scaffolding)**
  - Perintah CLI untuk memicu pembuatan proyek baru dari template `starter/`.

---

## 🤝 Kontribusi & Saran
Arah pengembangan ini fleksibel dan terbuka terhadap masukan dari komunitas. Jika Anda memiliki ide atau kebutuhan fitur tambahan, silakan buka *Issue* atau *Pull Request* di repositori ini.
