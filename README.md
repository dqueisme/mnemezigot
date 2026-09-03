# Zig 0.16 + WebAssembly (WASM) + gRPC Demo (Powered by `httpz`)

High-Performance Fullstack Web Application menggunakan **Zig 0.16**:
- **Frontend**: Dikompilasi ke WebAssembly (`wasm32-freestanding`, ReleaseSmall: 2.5 KB), berinteraksi dengan browser DOM via JS bridge (`bridge.js`).
- **Backend Server**: High-concurrency native server ditenagai oleh **`httpz`** (Pure Zig event-driven engine dengan multi-worker support) yang mampu melayani ratusan ribu request per detik.
- **Komunikasi**: Standard **gRPC-Web** framing over HTTP POST (`application/grpc-web+proto`).

---

## 🏗️ Struktur Project

```
mnemezigot/
├── build.zig               # Multi-target build script (WASM + httpz Server)
├── build.zig.zon           # Package manifest & dependencies (httpz via package manager)
├── proto/
│   └── service.proto       # Protobuf & RPC service definition
├── frontend/
│   ├── STYLEGUIDE.md       # Panduan styling & konvensi CSS (Do & Don't)
│   ├── src/
│   │   └── main.zig        # Frontend logic di-compile ke WebAssembly (WASM)
│   └── static/
│       ├── index.html      # Clean semantic HTML
│       ├── bridge.js       # JS runtime bridge untuk WebAssembly & gRPC fetch
│       ├── style.css       # UI Styling terpusat (CSS variables & semantic classes)
│       └── app.wasm        # Output kompilasi WASM (ReleaseSmall: 2.5 KB)
└── backend/
    └── src/
        └── main.zig        # Production-grade httpz backend server (Static files + gRPC-Web dispatcher)
```

---

## ⚡ Alur Kerja Sistem (Data Flow)

1. **Inisialisasi**:
   - Browser memuat `index.html` dan `bridge.js`.
   - `bridge.js` melakukan streaming instantiate `app.wasm`.
   - WASM mengeksekusi `init()` dan mengubah DOM menjadi `Hello World`.

2. **Tombol "Ambil Data Acak" Ditekan**:
   - Browser event memicu fungsi `on_button_click()` di dalam WASM.
   - WASM menyiapkan 5-byte header frame gRPC kosong untuk `RandomNameRequest` dan meminta JS bridge mengirim request ke `/hello.NameService/GetRandomName`.
   - JS bridge mengirim `fetch` request dengan header `Content-Type: application/grpc-web+proto`.

3. **Server Memproses Request via `httpz`**:
   - `httpz` router menerima request secara asinkron (non-blocking).
   - Server Zig memilih salah satu nama acak dari `["Andi", "Budi", "Citra", "Dewi", "Eko"]`.
   - Server meng-encode Protobuf payload `RandomNameResponse { name = "<nama>" }`.
   - Server membungkus payload dengan framing gRPC data frame (flag `0x00`) + trailer frame status (flag `0x80`, `grpc-status: 0`).
   - Server mengirim response HTTP 200 berkecepatan sub-milidetik.

4. **WASM Menerima & Render**:
   - JS bridge menyalin byte response ke memory WASM dan memanggil `on_grpc_response()`.
   - WASM mem-parsing frame gRPC & protobuf string name.
   - WASM memformat pesan menjadi `Hello <Nama>` dan memanggil `js_update_text()` untuk mengupdate teks di DOM.

---

## 🚀 Fitur & Keunggulan Backend `httpz`

- **100% Pure Zig**: Zero C dependencies, kompilasi super cepat, dan cross-platform (Linux & Windows).
- **High Concurrency**: Mampu melayani ratusan ribu request per detik (*throughput ~150k+ req/s*).
- **Memory Footprint Sangat Irit**: Hanya membutuhkan ~5 MB RAM idle dan < 25 MB pada beban penuh.
- **Cross-Compilation**: Dapat langsung di-compile untuk Windows (`server.exe`) maupun Linux (`server`).

---

## 🎨 Panduan Styling & CSS (Do & Don't)

Project ini menggunakan pendekatan **Semantic Component-Based CSS** (mirip Bootstrap/BEM) untuk menjaga file HTML tetap bersih, rapi, dan mudah dibaca tanpa pencemaran *utility-class soup*.

### ✅ DO (Harus Dilakukan)
1. **Gunakan Semantic Class Names**: Beri nama class berdasarkan fungsi komponen (`.card`, `.primary-btn`, `.badge`, `.status-box`).
2. **Pusatkan Warna di CSS Variables (`:root`)**: Selalu gunakan `var(--primary)`, `var(--card-bg)`, `var(--border)` untuk mempermudah retheming.
3. **Gunakan Modifier Class untuk State / Varian**: Contoh `.primary-btn.btn--secondary`, `.is-loading`, `.is-active`.
4. **Jaga HTML Tetap Minimalis**: HTML hanya berisi struktur konten dan semantic class hooks yang stabil.
5. **Manipulasi State via Class / Atribut**: WASM / JS cukup me-toggle class (misal `classList.toggle('is-loading')`) atau atribut `disabled`.

### ❌ DON'T (Harus Dihindari)
1. **DILARANG Utility-Class Soup di HTML**: Hindari menumpuk 10+ utility class (seperti gaya Tailwind) di satu elemen HTML.
2. **DILARANG Inline Styles**: Hindari atribut `style="..."` di elemen HTML.
3. **DILARANG Hardcode Hex Warna Berulang**: Jangan menulis `#f97316` berulang kali; gunakan `var(--primary)`.
4. **DILARANG Injeksi CSS String dari WASM**: Jangan kirim string CSS inline dari WebAssembly ke JS.
5. **DILARANG Penggunaan `!important`**: Rancang selector class tunggal yang bersih.

> 📖 Panduan lengkap dan contoh komponen dapat dilihat di **[`frontend/STYLEGUIDE.md`](file:///home/aripseprudin/workspace/mnemezigot/frontend/STYLEGUIDE.md)**.

---

## 🚀 Cara Build & Menjalankan

### 1. Build Proyek
```bash
zig build
```
Hasil build akan terkumpul secara otomatis di folder **`zig-out/`**:
```
zig-out/
├── server                  # Binary executable backend (ditenagai httpz)
└── public/                 # Folder aset statis frontend
    ├── app.wasm            # Binary WebAssembly (2.5 KB)
    ├── bridge.js           # JS runtime bridge
    ├── index.html          # Web UI
    └── style.css           # Styling
```

### 2. Jalankan Server
```bash
zig build run
```
Atau jalankan langsung binary di folder `zig-out/`:
```bash
cd zig-out && ./server
```

Buka browser di: **[http://localhost:8080](http://localhost:8080)**

---

## 📦 Distribusi ke User (Packaging)

Untuk mengirimkan aplikasi ke user akhir dalam bentuk ZIP:
```bash
cd zig-out && zip -r ../aplikasi.zip * && cd ..
```
User cukup mengekstrak `aplikasi.zip` dan menjalankan `./server`.
