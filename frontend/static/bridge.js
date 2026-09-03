// JavaScript runtime bridge for Zig WASM and gRPC-Web

let wasmInstance = null;
const greetingEl = document.getElementById("greeting");
const fetchBtn = document.getElementById("btn-fetch");
const logEntriesEl = document.getElementById("log-entries");

function addLog(msg) {
  const time = new Date().toLocaleTimeString();
  const entry = document.createElement("div");
  entry.className = "log-line";
  entry.innerHTML = `<span class="log-time">[${time}]</span> ${msg}`;
  logEntriesEl.appendChild(entry);
  logEntriesEl.scrollTop = logEntriesEl.scrollHeight;
}

// Memory helper: read UTF-8 string from WASM memory
function readString(ptr, len) {
  const memory = new Uint8Array(wasmInstance.exports.memory.buffer, ptr, len);
  return new TextDecoder("utf-8").decode(memory);
}

// Memory helper: copy Uint8Array to WASM memory
function copyToWasm(bytes) {
  const ptr = wasmInstance.exports.alloc(bytes.length);
  if (!ptr) throw new Error("Failed to allocate WASM memory");
  const wasmBuffer = new Uint8Array(wasmInstance.exports.memory.buffer, ptr, bytes.length);
  wasmBuffer.set(bytes);
  return { ptr, len: bytes.length };
}

// Imports provided to WASM
const importObject = {
  env: {
    js_update_text: (ptr, len) => {
      const text = readString(ptr, len);
      greetingEl.textContent = text;
      addLog(`UI updated to: <strong>${text}</strong>`);
    },
    js_log: (ptr, len) => {
      const msg = readString(ptr, len);
      addLog(`[WASM] ${msg}`);
    },
    js_send_grpc: async (endpointPtr, endpointLen, bodyPtr, bodyLen) => {
      const endpoint = readString(endpointPtr, endpointLen);
      const bodyBytes = new Uint8Array(wasmInstance.exports.memory.buffer, bodyPtr, bodyLen);

      addLog(`[gRPC-Web] Sending POST ${endpoint} (${bodyBytes.length} bytes)...`);

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
          throw new Error(`HTTP ${response.status}: ${response.statusText}`);
        }

        const arrayBuffer = await response.arrayBuffer();
        const respBytes = new Uint8Array(arrayBuffer);
        addLog(`[gRPC-Web] Received response (${respBytes.length} bytes)`);

        // Transfer bytes into WASM memory and trigger WASM callback
        const { ptr, len } = copyToWasm(respBytes);
        wasmInstance.exports.on_grpc_response(ptr, len);
        wasmInstance.exports.free(ptr, len);
      } catch (err) {
        addLog(`[Error] gRPC call failed: ${err.message}`);
      }
    },
  },
};

// Initialize WASM
async function loadWasm() {
  try {
    addLog("Fetching app.wasm...");
    const response = await fetch("/app.wasm");
    if (!response.ok) {
      throw new Error(`Failed to load app.wasm (${response.status})`);
    }

    const { instance } = await WebAssembly.instantiateStreaming(response, importObject);
    wasmInstance = instance;

    // Call Zig WASM init()
    wasmInstance.exports.init();

    // Enable button
    fetchBtn.disabled = false;
    fetchBtn.addEventListener("click", () => {
      wasmInstance.exports.on_button_click();
    });

    addLog("WASM loaded successfully & ready!");
  } catch (err) {
    addLog(`Initialization Error: ${err.message}`);
    greetingEl.textContent = "Error loading WASM";
  }
}

loadWasm();
