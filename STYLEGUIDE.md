# 🎨 CSS & Frontend Styling Guidelines

Panduan ini bertujuan menjaga kode HTML tetap bersih, semantik, mudah dibaca, dan konsisten (menggunakan pendekatan *Component-Driven CSS / Semantic Classes* mirip Bootstrap/BEM, **tanpa** utility-class soup seperti Tailwind).

---

## 🎯 Filosofi Desain

1. **Separation of Concerns**: HTML mendefinisikan *struktur & makna*, CSS mengontrol *tampilan & tema*, WASM/JS mengontrol *logika & data*.
2. **Clean HTML**: HTML harus mudah dibaca oleh manusia, ramah aksesibilitas, dan memiliki hook class yang stabil untuk manipulasi WebAssembly.
3. **Design Tokens First**: Semua warna, radius, border, dan typography berpusat pada CSS Variables (`:root`).

---

## ✅ DO (Yang Harus Dilakukan)

| Praktik | Contoh Baik | Alasan |
| :--- | :--- | :--- |
| **Gunakan Semantic Class Names** | `<div class="card">`<br>`<button class="primary-btn">` | Jelas fungsinya, HTML ringkas dan tidak tercemar puluhan class styling mikro. |
| **Gunakan CSS Variables (`:root`)** | `background: var(--card-bg);`<br>`color: var(--primary);` | Memudahkan retheming (Dark/Light mode) dan menjaga konsistensi warna global. |
| **Gunakan Modifier Class untuk State** | `<button class="primary-btn is-loading">`<br>`<div class="alert alert--danger">` | Mengubah state komponen secara eksplisit tanpa merombak struktur class dasar. |
| **Gunakan State Hooks untuk WASM/JS** | `<button disabled>`<br>`<div class="user-card is-active">` | Mudah dimanipulasi dari WebAssembly / JS Bridge (`classList.toggle`, `setAttribute`). |
| **Layout Responsif di Level CSS** | `.container { max-width: 580px; width: 100%; }` | Mengontrol breakpoint dan adaptasi ukuran layar terpusat di stylesheet. |

---

## ❌ DON'T (Yang Harus Dihindari)

| Praktik Buruk | Contoh Salah | Alasan |
| :--- | :--- | :--- |
| **Utility Class Soup di HTML** | `<div class="flex items-center justify-center p-4 bg-slate-800 text-white rounded-xl shadow-lg border border-slate-700">` | Mengotori HTML, sulit di-maintain saat komponen digunakan di banyak tempat. |
| **Inline Styles (`style="..."`)** | `<h1 style="color: #f97316; margin-top: 10px;">` | Merusak konsistensi tema, sulit di-override, dan memperbesar ukuran transfer HTML. |
| **Hardcoding Nilai / Warna** | `border: 1px solid #334155;` *(berulang-ulang)* | Gunakan `var(--border)` agar perubahan desain cukup dilakukan di 1 baris `:root`. |
| **Penggunaan `!important`** | `.btn { color: white !important; }` | Indikasi struktur selector yang buruk. Gunakan spesifisitas class tunggal yang rapi. |
| **Injeksi CSS String dari WASM** | `wasm -> js: "element.style.background = 'red'"` | WASM sebaiknya hanya memanipulasi data/state class (misal: toggle `.has-error`). |

---

## 📐 Pola Standar Komponen (Reference Patterns)

### 1. Design Tokens (`:root`)
```css
:root {
  /* Color Palette */
  --bg: #0f172a;
  --card-bg: #1e293b;
  --text-main: #f8fafc;
  --text-muted: #94a3b8;
  --primary: #f97316;
  --primary-hover: #ea580c;
  --accent: #38bdf8;
  --border: #334155;
  --code-bg: #0b0f19;

  /* Spacing & Radii */
  --radius-sm: 6px;
  --radius-md: 10px;
  --radius-lg: 16px;
  --radius-full: 9999px;
  --shadow-card: 0 25px 50px -12px rgba(0, 0, 0, 0.5);
}
```

### 2. Button Component Pattern
```html
<!-- HTML Bersih -->
<button class="primary-btn">
  <span class="btn-icon">⚡</span>
  <span class="btn-text">Ambil Data Acak</span>
</button>

<button class="primary-btn btn--secondary">Batal</button>
```

```css
/* CSS Terpusat */
.primary-btn {
  background: linear-gradient(135deg, var(--primary), var(--primary-hover));
  color: white;
  border: none;
  padding: 0.9rem 2rem;
  font-size: 1.05rem;
  font-weight: 600;
  border-radius: var(--radius-md);
  cursor: pointer;
  display: inline-flex;
  align-items: center;
  gap: 0.5rem;
  transition: all 0.2s ease;
}

.primary-btn:hover:not(:disabled) {
  transform: translateY(-2px);
}

.primary-btn:disabled {
  opacity: 0.5;
  cursor: not-allowed;
  filter: grayscale(1);
}

/* Variant Modifier */
.primary-btn.btn--secondary {
  background: transparent;
  border: 1px solid var(--border);
  color: var(--text-main);
}
```

### 3. Card & Content Box Pattern
```html
<!-- HTML Bersih -->
<div class="card">
  <div class="badge">Status Info</div>
  <h1 class="card-title">Judul Card</h1>
  <p class="card-desc">Deskripsi konten...</p>
</div>
```

```css
/* CSS Terpusat */
.card {
  background: var(--card-bg);
  border: 1px solid var(--border);
  border-radius: var(--radius-lg);
  padding: 2.5rem;
  box-shadow: var(--shadow-card);
}

.badge {
  display: inline-block;
  background: rgba(249, 115, 22, 0.15);
  color: var(--primary);
  border: 1px solid rgba(249, 115, 22, 0.3);
  font-size: 0.8rem;
  font-weight: 600;
  padding: 0.35rem 0.85rem;
  border-radius: var(--radius-full);
}
```
