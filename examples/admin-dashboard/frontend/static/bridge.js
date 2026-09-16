// JavaScript Runtime Bridge for Mnemezigot: Landing Page, Login, Admin Dashboard, WASM & gRPC

let wasmInstance = null;

// Views
const viewLanding = document.getElementById("view-landing");
const viewLogin = document.getElementById("view-login");
const viewAdmin = document.getElementById("view-admin");

// Nav elements
const navLandingBtn = document.getElementById("nav-landing-btn");
const navAdminBtn = document.getElementById("nav-admin-btn");
const navAuthBtn = document.getElementById("nav-auth-btn");
const navAuthText = document.getElementById("nav-auth-text");
const heroAdminBtn = document.getElementById("hero-admin-btn");
const btnBackLanding = document.getElementById("btn-back-landing");
const btnLogout = document.getElementById("btn-logout");

// Landing Live Demo elements
const greetingEl = document.getElementById("greeting");
const fetchBtn = document.getElementById("btn-fetch");
const logEntriesEl = document.getElementById("log-entries");

// Login elements
const loginForm = document.getElementById("login-form");
const inputUsername = document.getElementById("input-username");
const inputPassword = document.getElementById("input-password");
const loginErrorBox = document.getElementById("login-error-box");

// Admin elements
const kpiCountEl = document.getElementById("kpi-count");
const kpiStorageEl = document.getElementById("kpi-storage");
const formAddName = document.getElementById("form-add-name");
const inputNewName = document.getElementById("input-new-name");
const btnAddName = document.getElementById("btn-add-name");
const addSuccessAlert = document.getElementById("add-success-alert");
const btnAdminQuery = document.getElementById("btn-admin-query");
const adminTestName = document.getElementById("admin-test-name");
const adminLogEntries = document.getElementById("admin-log-entries");

// --- Logging Helper ---
function addLog(msg) {
  const time = new Date().toLocaleTimeString();
  const entry = document.createElement("div");
  entry.className = "log-line";
  entry.innerHTML = `<span class="log-time">[${time}]</span> ${msg}`;

  if (logEntriesEl) {
    logEntriesEl.appendChild(entry.cloneNode(true));
    logEntriesEl.scrollTop = logEntriesEl.scrollHeight;
  }
  if (adminLogEntries) {
    adminLogEntries.appendChild(entry);
    adminLogEntries.scrollTop = adminLogEntries.scrollHeight;
  }
}

// --- Memory Helpers for WASM ---
function readString(ptr, len) {
  const memory = new Uint8Array(wasmInstance.exports.memory.buffer, ptr, len);
  return new TextDecoder("utf-8").decode(memory);
}

function copyToWasm(bytes) {
  const ptr = wasmInstance.exports.alloc(bytes.length);
  if (!ptr) throw new Error("Gagal mengalokasikan memory WASM");
  const wasmBuffer = new Uint8Array(wasmInstance.exports.memory.buffer, ptr, bytes.length);
  wasmBuffer.set(bytes);
  return { ptr, len: bytes.length };
}

// --- Router & View Management ---
function isAuthenticated() {
  return sessionStorage.getItem("mnemezigot_admin_auth") === "true";
}

function navigateTo(route) {
  if (route === "admin" && !isAuthenticated()) {
    route = "login";
  }

  // Update URL hash
  if (route === "landing") window.location.hash = "#/";
  else window.location.hash = `#/${route}`;

  // Toggle views
  viewLanding.classList.toggle("is-hidden", route !== "landing");
  viewLogin.classList.toggle("is-hidden", route !== "login");
  viewAdmin.classList.toggle("is-hidden", route !== "admin");

  // Update navigation button active state
  navLandingBtn.classList.toggle("is-active", route === "landing");
  navAdminBtn.classList.toggle("is-active", route === "admin");

  if (isAuthenticated()) {
    navAuthText.textContent = "Admin (Keluar)";
  } else {
    navAuthText.textContent = "Masuk / Login";
  }

  if (route === "admin") {
    fetchStats();
  }
}

// --- Fetch Database Stats ---
async function fetchStats() {
  try {
    const res = await fetch("/api/stats");
    if (res.ok) {
      const data = await res.json();
      if (kpiCountEl) kpiCountEl.textContent = `${data.total_names} Data Tersimpan`;
      if (kpiStorageEl) kpiStorageEl.textContent = `${data.database_file} (${data.journal_mode})`;
      addLog(`[System] Stats SQLite dimuat: ${data.total_names} baris data (WAL Mode).`);
    }
  } catch (err) {
    console.error("Gagal memuat stats:", err);
  }
}

// --- Authentication Handlers ---
loginForm.addEventListener("submit", (e) => {
  e.preventDefault();
  const username = inputUsername.value.trim();
  const password = inputPassword.value.trim();

  if (username === "admin" && password === "admin123") {
    sessionStorage.setItem("mnemezigot_admin_auth", "true");
    loginErrorBox.classList.add("is-hidden");
    addLog(`🔑 <strong>Admin berhasil login</strong> dengan kredensial terverifikasi.`);
    navigateTo("admin");
  } else {
    loginErrorBox.classList.remove("is-hidden");
    addLog(`❌ Percobaan login gagal untuk username: "${username}".`);
  }
});

function handleLogout() {
  sessionStorage.removeItem("mnemezigot_admin_auth");
  addLog("👋 Admin telah logout.");
  navigateTo("landing");
}

if (btnLogout) btnLogout.addEventListener("click", handleLogout);
if (btnBackLanding) btnBackLanding.addEventListener("click", () => navigateTo("landing"));

navAuthBtn.addEventListener("click", () => {
  if (isAuthenticated()) {
    handleLogout();
  } else {
    navigateTo("login");
  }
});

navLandingBtn.addEventListener("click", () => navigateTo("landing"));
navAdminBtn.addEventListener("click", () => navigateTo("admin"));
if (heroAdminBtn) heroAdminBtn.addEventListener("click", () => navigateTo("admin"));

// --- Add Name to SQLite Handler ---
if (formAddName) {
  formAddName.addEventListener("submit", async (e) => {
    e.preventDefault();
    const newName = inputNewName.value.trim();
    if (!newName) return;

    btnAddName.classList.add("is-loading");
    btnAddName.disabled = true;

    try {
      const res = await fetch("/api/names", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ name: newName }),
      });

      if (res.ok) {
        const data = await res.json();
        addSuccessAlert.textContent = `✅ "${newName}" berhasil disimpan! Total sekarang: ${data.total} data.`;
        addSuccessAlert.classList.remove("is-hidden");
        inputNewName.value = "";
        fetchStats();
        addLog(`[SQLite INSERT] Menambahkan data <strong>"${newName}"</strong> ke SQLite (Total: ${data.total}).`);
        setTimeout(() => addSuccessAlert.classList.add("is-hidden"), 4000);
      }
    } catch (err) {
      addLog(`❌ Gagal menyimpan ke SQLite: ${err.message}`);
    } finally {
      btnAddName.classList.remove("is-loading");
      btnAddName.disabled = false;
    }
  });
}

// Admin live query tester
if (btnAdminQuery) {
  btnAdminQuery.addEventListener("click", () => {
    if (wasmInstance && wasmInstance.exports.on_button_click) {
      wasmInstance.exports.on_button_click();
    }
  });
}

// --- WASM & gRPC-Web Bridge Object ---
const importObject = {
  env: {
    js_update_text: (ptr, len) => {
      const text = readString(ptr, len);
      if (greetingEl) greetingEl.textContent = text;
      if (adminTestName) adminTestName.textContent = text.replace("Hello ", "");
      addLog(`UI di-update ke: <strong>${text}</strong>`);
    },
    js_log: (ptr, len) => {
      const msg = readString(ptr, len);
      addLog(`[WASM] ${msg}`);
    },
    js_send_grpc: async (endpointPtr, endpointLen, bodyPtr, bodyLen) => {
      const endpoint = readString(endpointPtr, endpointLen);
      const bodyBytes = new Uint8Array(wasmInstance.exports.memory.buffer, bodyPtr, bodyLen);

      if (fetchBtn) {
        fetchBtn.classList.add("is-loading");
        fetchBtn.disabled = true;
      }
      if (btnAdminQuery) btnAdminQuery.disabled = true;

      try {
        addLog(`[gRPC-Web] Mengirim frame biner ke <code>${endpoint}</code>...`);
        const response = await fetch(endpoint, {
          method: "POST",
          headers: {
            "Content-Type": "application/grpc-web+proto",
            "X-Grpc-Web": "1",
          },
          body: bodyBytes,
        });

        if (!response.ok) {
          throw new Error(`HTTP Error: ${response.status} ${response.statusText}`);
        }

        const respBuffer = await response.arrayBuffer();
        const respBytes = new Uint8Array(respBuffer);

        const { ptr, len } = copyToWasm(respBytes);
        wasmInstance.exports.on_grpc_response(ptr, len);
        wasmInstance.exports.free(ptr, len);
      } catch (err) {
        addLog(`❌ [gRPC Error]: ${err.message}`);
      } finally {
        if (fetchBtn) {
          fetchBtn.classList.remove("is-loading");
          fetchBtn.disabled = false;
        }
        if (btnAdminQuery) btnAdminQuery.disabled = false;
      }
    },
  },
};

// Landing fetch button
if (fetchBtn) {
  fetchBtn.addEventListener("click", () => {
    if (wasmInstance && wasmInstance.exports.on_button_click) {
      wasmInstance.exports.on_button_click();
    }
  });
}

// --- Initialize Application ---
async function init() {
  // Handle URL hash on initial load
  const hash = window.location.hash.replace("#/", "");
  if (hash === "admin") {
    navigateTo("admin");
  } else if (hash === "login") {
    navigateTo("login");
  } else {
    navigateTo("landing");
  }

  // Load WASM Module
  try {
    addLog("Memuat modul WebAssembly (app.wasm)...");
    const response = await fetch("app.wasm");
    const bytes = await response.arrayBuffer();
    const { instance } = await WebAssembly.instantiate(bytes, importObject);
    wasmInstance = instance;

    wasmInstance.exports.init();
    fetchStats();
  } catch (err) {
    addLog(`❌ Gagal memuat WASM: ${err.message}`);
    console.error("WASM load error:", err);
  }
}

window.addEventListener("hashchange", () => {
  const hash = window.location.hash.replace("#/", "");
  navigateTo(hash || "landing");
});

init();
