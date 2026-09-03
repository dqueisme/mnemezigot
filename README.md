# Zig 0.16 + WebAssembly (WASM) + gRPC Demo

Minimal Fullstack Web Application menggunakan **Zig 0.16**:
- **Frontend**: Dikompilasi ke WebAssembly (`wasm32-freestanding`), berinteraksi dengan browser DOM via JS bridge (`bridge.js`).
- **Backend Server**: Native Zig HTTP & gRPC-Web server yang menyajikan static assets dan menangani RPC calls.
- **Komunikasi**: Standard **gRPC-Web** framing over HTTP POST (`application/grpc-web+proto`).

---

## 🏗️ Struktur Project

```
mnemezigot/
├── build.zig               # Multi-target build script (WASM + Native Server)
├── build.zig.zon           # Package manifest
├── proto/
│   └── service.proto       # Protobuf & RPC service definition
├── frontend/
│   ├── src/
│   │   └── main.zig        # Frontend logic di-compile ke WebAssembly (WASM)
│   └── static/
│       ├── index.html      # UI page
│       ├── bridge.js       # JS runtime bridge untuk WebAssembly & gRPC fetch
│       ├── style.css       # UI Styling
│       └── app.wasm        # Output kompilasi WASM
└── backend/
    └── src/
        └── main.zig        # Native Zig server (HTTP static files + gRPC-Web dispatcher)
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

3. **Server Memproses Request**:
   - Server Zig memilih salah satu nama acak dari `["Andi", "Budi", "Citra", "Dewi", "Eko"]`.
   - Server meng-encode Protobuf payload `RandomNameResponse { name = "<nama>" }`.
   - Server membungkus payload dengan framing gRPC data frame (flag `0x00`) + trailer frame status (flag `0x80`, `grpc-status: 0`).
   - Server mengirim response HTTP 200.

4. **WASM Menerima & Render**:
   - JS bridge menyalin byte response ke memory WASM dan memanggil `on_grpc_response()`.
   - WASM mem-parsing frame gRPC & protobuf string name.
   - WASM memformat pesan menjadi `Hello <Nama>` dan memanggil `js_update_text()` untuk mengupdate teks di DOM.

---

## 🚀 Cara Menjalankan

### 1. Build WASM & Server
```bash
zig build
```

### 2. Jalankan Server
```bash
zig build run
```

Buka browser di: [http://localhost:8080](http://localhost:8080)
