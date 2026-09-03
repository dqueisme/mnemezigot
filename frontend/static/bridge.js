// JavaScript runtime bridge for Zig WASM, SQLite & gRPC-Web

let wasmInstance = null;
const fetchBtn = document.getElementById("btn-fetch");
const logEntriesEl = document.getElementById("log-entries");

// User Card Elements
const userNameEl = document.getElementById("user-name");
const userInitialsEl = document.getElementById("user-initials");
const userIdEl = document.getElementById("user-id");
const userJobEl = document.getElementById("user-job");
const userCityEl = document.getElementById("user-city");
const userEmailEl = document.getElementById("user-email");
const userPhoneEl = document.getElementById("user-phone");
const userAddrEl = document.getElementById("user-addr");
const statTotalEl = document.getElementById("stat-total");
const statLatencyEl = document.getElementById("stat-latency");

function addLog(msg) {
  const time = new Date().toLocaleTimeString();
  const entry = document.createElement("div");
  entry.className = "log-line";
  entry.innerHTML = `<span class="log-time">[${time}]</span> ${msg}`;
  logEntriesEl.appendChild(entry);
  logEntriesEl.scrollTop = logEntriesEl.scrollHeight;
}

function readString(ptr, len) {
  const memory = new Uint8Array(wasmInstance.exports.memory.buffer, ptr, len);
  return new TextDecoder("utf-8").decode(memory);
}

function copyToWasm(bytes) {
  const ptr = wasmInstance.exports.alloc(bytes.length);
  if (!ptr) throw new Error("Failed to allocate WASM memory");
  const wasmBuffer = new Uint8Array(wasmInstance.exports.memory.buffer, ptr, bytes.length);
  wasmBuffer.set(bytes);
  return { ptr, len: bytes.length };
}

// Function to generate initials (e.g. "Budi Santoso" -> "BS")
function getInitials(name) {
  const parts = name.trim().split(" ");
  if (parts.length >= 2) {
    return (parts[0][0] + parts[1][0]).toUpperCase();
  }
  return name.slice(0, 2).toUpperCase();
}

// Imports provided to WASM
const importObject = {
  env: {
    js_update_user_card: (
      namePtr, nameLen,
      jobPtr, jobLen,
      cityPtr, cityLen,
      emailPtr, emailLen,
      phonePtr, phoneLen,
      addrPtr, addrLen,
      userId, totalUsers, queryTimeMs
    ) => {
      const name = readString(namePtr, nameLen);
      const job = readString(jobPtr, jobLen);
      const city = readString(cityPtr, cityLen);
      const email = readString(emailPtr, emailLen);
      const phone = readString(phonePtr, phoneLen);
      const addr = readString(addrPtr, addrLen);

      userNameEl.textContent = name;
      userInitialsEl.textContent = getInitials(name);
      userIdEl.textContent = `#${userId.toLocaleString()}`;
      userJobEl.textContent = job;
      userCityEl.textContent = city;
      userEmailEl.textContent = email;
      userPhoneEl.textContent = phone;
      userAddrEl.textContent = addr;

      statTotalEl.textContent = `${totalUsers.toLocaleString()} Baris Data`;
      statLatencyEl.textContent = `${queryTimeMs.toFixed(3)} ms`;

      addLog(`[SQLite] Ditemukan ID #${userId} (${name}) dalam <strong>${queryTimeMs.toFixed(3)} ms</strong>!`);
    },
    js_log: (ptr, len) => {
      const msg = readString(ptr, len);
      addLog(`[WASM] ${msg}`);
    },
    js_send_grpc: async (endpointPtr, endpointLen, bodyPtr, bodyLen) => {
      const endpoint = readString(endpointPtr, endpointLen);
      const bodyBytes = new Uint8Array(wasmInstance.exports.memory.buffer, bodyPtr, bodyLen);

      fetchBtn.classList.add("is-loading");
      fetchBtn.disabled = true;

      try {
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

        // Copy response to WASM memory
        const { ptr, len } = copyToWasm(respBytes);

        // Call WASM response handler
        wasmInstance.exports.on_grpc_response(ptr, len);

        // Free memory allocated in WASM
        wasmInstance.exports.free(ptr, len);
      } catch (err) {
        addLog(`❌ [Error] gRPC call failed: ${err.message}`);
      } finally {
        fetchBtn.classList.remove("is-loading");
        fetchBtn.disabled = false;
      }
    },
  },
};

// Button event listener
fetchBtn.addEventListener("click", () => {
  if (wasmInstance && wasmInstance.exports.on_button_click) {
    wasmInstance.exports.on_button_click();
  }
});

// Load WASM Module
async function initWasm() {
  try {
    addLog("Memuat binary WebAssembly (app.wasm)...");
    const response = await fetch("app.wasm");
    const bytes = await response.arrayBuffer();
    const { instance } = await WebAssembly.instantiate(bytes, importObject);
    wasmInstance = instance;

    // Trigger initialisation in WASM
    wasmInstance.exports.init();

    // Otomatis fetch 1 user saat halaman pertama kali terbuka
    setTimeout(() => {
      if (wasmInstance.exports.on_button_click) {
        wasmInstance.exports.on_button_click();
      }
    }, 200);
  } catch (err) {
    addLog(`❌ Gagal memuat WASM: ${err.message}`);
    console.error("WASM loading error:", err);
  }
}

initWasm();
