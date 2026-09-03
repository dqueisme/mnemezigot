# Workspace Instructions & Rules: Mnemezigot

Project ini adalah aplikasi fullstack menggunakan **Zig 0.16 + WebAssembly (WASM) + gRPC-Web**.
Agent harus selalu mematuhi pedoman arsitektur dan gaya penulisan berikut:

---

## 📖 Project Context & Documentation (MANDATORY)

1. **Wajib Membaca `README.md`**: Sebelum memulai implementasi fitur, refactoring, atau perubahan kode, Agent **WAJIB** membaca [`README.md`](file:///home/aripseprudin/workspace/mnemezigot/README.md) untuk memahami arsitektur sistem, aliran data (data flow), dan struktur folder proyek terkini.
2. **Wajib Membaca `frontend/STYLEGUIDE.md`**: Saat mengerjakan atau memodifikasi komponen UI/frontend, Agent **WAJIB** merujuk pada [`frontend/STYLEGUIDE.md`](file:///home/aripseprudin/workspace/mnemezigot/frontend/STYLEGUIDE.md).

---

## 🎨 Frontend & CSS Styling Guidelines (MANDATORY)

Seluruh komponen UI dan styling frontend harus mematuhi aturan berikut:

### ✅ DO (Wajib Dilakukan)
1. **Gunakan Semantic & Component-Based Class Names**: Beri nama class berdasarkan fungsi komponen (`.card`, `.primary-btn`, `.badge`, `.status-box`), bukan properti CSS mikro.
2. **Pusatkan Desain pada CSS Variables (`:root`)**: Gunakan variabel global seperti `var(--primary)`, `var(--card-bg)`, `var(--border)` di `frontend/static/style.css`.
3. **Gunakan Modifier Class untuk State / Varian**: Contoh `.primary-btn.btn--secondary`, `.is-loading`, `.is-active`.
4. **HTML Harus Bersih dan Ringkas**: Jangan campur aduk puluhan styling utility class di tag HTML.
5. **Manipulasi State via Class / Atribut di WASM/JS**: WebAssembly / JS hanya perlu mengubah class state (misal `classList.toggle('is-loading')`) atau atribut `disabled`.

### ❌ DON'T (Dilarang Keras)
1. **DILARANG Menggunakan Utility-Class Soup (Gaya Tailwind)**: Dilarang menumpuk class utilitas mikro (seperti `flex items-center justify-center p-4 text-white ...`) langsung di HTML.
2. **DILARANG Inline Style (`style="..."`)**: Jangan pernah menulis atribut `style` langsung pada elemen HTML.
3. **DILARANG Hardcode Hex Warna Berulang**: Selalu rujuk ke variabel `var(...)`.
4. **DILARANG Injeksi CSS String dari WASM**: Jangan kirim string CSS inline dari WebAssembly ke JS.
5. **DILARANG Menggunakan `!important`**: Rancang selector class tunggal yang bersih dan terstruktur.

---

## 🏗️ Build & Distribution Rules

1. **WASM Optimization**: Frontend WASM harus selalu dikompilasi dengan `-Doptimize=ReleaseSmall` dan `strip = true` agar binary size tetap kecil (< 10 KB).
2. **Distribution Package**: Seluruh artefak hasil `zig build` terkumpul di folder `zig-out/` (`server` binary + `public/` static assets) siap di-zip untuk end-user.
