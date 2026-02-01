import * as wasiModule from "https://esm.sh/@wasmer/wasi@1.2.2?bundle";
import * as wasmfsModule from "https://esm.sh/@wasmer/wasmfs@0.12.0?bundle";
import { unzipSync } from "https://esm.sh/fflate@0.8.2?bundle";

const encoder = new TextEncoder();
const decoder = new TextDecoder();

const elements = {
  dropZone: document.getElementById("drop-zone"),
  projectInput: document.getElementById("project-input"),
  projectZipInput: document.getElementById("project-zip-input"),
  projectName: document.getElementById("project-name"),
  projectCount: document.getElementById("project-count"),
  runButton: document.getElementById("run-button"),
  resetButton: document.getElementById("reset-button"),
  queryInput: document.getElementById("query-input"),
  exampleList: document.getElementById("example-list"),
  status: document.getElementById("status"),
  output: document.getElementById("output"),
};

const examples = [
  {
    name: "Targets + types",
    query: "targets { name type }",
  },
  {
    name: "Build configurations",
    query: "buildConfigurations",
  },
  {
    name: "Target sources (normalized)",
    query: "targetSources(pathMode: NORMALIZED) { target path }",
  },
  {
    name: "Target resources",
    query: "targetResources { target path }",
  },
  {
    name: "Build scripts",
    query: "targetBuildScripts { target name stage }",
  },
  {
    name: "Link dependencies",
    query: "targetLinkDependencies { target name kind embed weak }",
  },
  {
    name: "Target dependencies",
    query: "targetDependencies { target name type }",
  },
  {
    name: "Swift packages",
    query: "swiftPackages { name identity url }",
  },
  {
    name: "Build settings (SWIFT keys)",
    query: "targetBuildSettings(filter: { key: { contains: \"SWIFT\" } }) { target configuration key value }",
  },
  {
    name: "Schemes",
    query: "schemes { name isShared buildTargets testTargets runTarget }",
  },
];

const state = {
  entries: [],
  projectRoot: null,
  pbxprojEntry: null,
  fileCount: 0,
  source: "none",
};

let wasiReady = false;

function setStatus(message, tone = "idle") {
  elements.status.textContent = message;
  elements.status.dataset.tone = tone;
}

function updateMeta() {
  elements.projectName.textContent = state.projectRoot ?? "None";
  elements.projectCount.textContent = `${state.fileCount}`;
  elements.runButton.disabled = !state.pbxprojEntry;
}

function renderExamples() {
  if (!elements.exampleList) {
    return;
  }
  elements.exampleList.innerHTML = "";
  for (const example of examples) {
    const button = document.createElement("button");
    button.type = "button";
    button.className = "example-button";
    button.textContent = example.name;
    button.title = example.query;
    button.addEventListener("click", () => {
      elements.queryInput.value = example.query;
      setStatus(`Example loaded: ${example.name}`, "success");
    });
    elements.exampleList.appendChild(button);
  }
}

function resetState() {
  state.entries = [];
  state.projectRoot = null;
  state.pbxprojEntry = null;
  state.fileCount = 0;
  state.source = "none";
  elements.output.textContent = "// Output will appear here.";
  setStatus("Waiting for a project…", "idle");
  updateMeta();
}

function normalizePath(value) {
  return value.replace(/\\/g, "/").replace(/^\.\/+/, "");
}

function isIgnoredEntry(value) {
  return value.endsWith(".DS_Store") || value.includes("/.DS_Store");
}

function detectProjectRoot(paths) {
  for (const rawPath of paths) {
    const normalized = normalizePath(rawPath);
    const match = normalized.match(/(.+\.xcodeproj)(\/|$)/i);
    if (match) {
      return match[1];
    }
  }
  return null;
}

function findPbxprojEntry(entries, projectRoot) {
  if (!projectRoot) return null;
  const pbxprojPath = `${projectRoot}/project.pbxproj`;
  return entries.find((entry) => normalizePath(entry.path) === pbxprojPath) ?? null;
}

async function readEntriesFromFileList(fileList) {
  const entries = [];
  for (const file of fileList) {
    const relPath = normalizePath(file.webkitRelativePath || file._relativePath || file.name);
    if (!relPath || isIgnoredEntry(relPath)) {
      continue;
    }
    try {
      const data = new Uint8Array(await file.arrayBuffer());
      entries.push({ path: relPath, data });
    } catch (error) {
      if (error && typeof error === "object" && error.name === "NotFoundError") {
        // Likely a directory entry from drag/drop; skip it.
        continue;
      }
      throw error;
    }
  }
  return entries;
}

function readAllDirectoryEntries(reader) {
  return new Promise((resolve, reject) => {
    const entries = [];
    const readBatch = () => {
      reader.readEntries((batch) => {
        if (!batch.length) {
          resolve(entries);
          return;
        }
        entries.push(...batch);
        readBatch();
      }, reject);
    };
    readBatch();
  });
}

function entryRelativePath(entry, rootName) {
  if (entry.fullPath) {
    const trimmed = entry.fullPath.replace(/^\//, "");
    if (trimmed.startsWith(`${rootName}/`)) {
      return trimmed;
    }
    return `${rootName}/${trimmed}`;
  }
  return `${rootName}/${entry.name}`;
}

async function collectFilesFromEntry(entry, rootName, files) {
  if (entry.isFile) {
    await new Promise((resolve, reject) => {
      entry.file((file) => {
        const relativePath = entryRelativePath(entry, rootName);
        try {
          Object.defineProperty(file, "webkitRelativePath", {
            value: relativePath,
          });
        } catch (error) {
          // Best effort; fall back to name if the property is read-only.
        }
        try {
          file._relativePath = relativePath;
        } catch (error) {
          // Ignore if the File object is sealed.
        }
        files.push(file);
        resolve();
      }, reject);
    });
    return;
  }

  if (entry.isDirectory) {
    const reader = entry.createReader();
    const children = await readAllDirectoryEntries(reader);
    for (const child of children) {
      await collectFilesFromEntry(child, rootName, files);
    }
  }
}

async function handleFolderSelection(fileList) {
  if (!fileList || fileList.length === 0) {
    return;
  }
  setStatus("Reading folder…", "idle");
  let entries = [];
  try {
    entries = await readEntriesFromFileList(fileList);
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    setStatus(message, "error");
    return;
  }
  const projectRoot = detectProjectRoot(entries.map((entry) => entry.path));
  const pbxprojEntry = findPbxprojEntry(entries, projectRoot);

  state.entries = entries;
  state.projectRoot = projectRoot;
  state.pbxprojEntry = pbxprojEntry;
  state.fileCount = entries.length;
  state.source = "folder";

  updateMeta();
  if (!pbxprojEntry) {
    setStatus("project.pbxproj not found in selection.", "error");
  } else {
    setStatus("Project loaded. Ready to query.", "success");
  }
}

async function handleZipSelection(file) {
  if (!file) {
    return;
  }
  setStatus("Reading zip…", "idle");
  const buffer = new Uint8Array(await file.arrayBuffer());
  const zipEntries = unzipSync(buffer);
  const entries = Object.entries(zipEntries)
    .map(([path, data]) => ({ path: normalizePath(path), data }))
    .filter((entry) => entry.path && !isIgnoredEntry(entry.path));

  const projectRoot = detectProjectRoot(entries.map((entry) => entry.path));
  const pbxprojEntry = findPbxprojEntry(entries, projectRoot);

  state.entries = entries;
  state.projectRoot = projectRoot;
  state.pbxprojEntry = pbxprojEntry;
  state.fileCount = entries.length;
  state.source = "zip";

  updateMeta();
  if (!pbxprojEntry) {
    setStatus("project.pbxproj not found in zip.", "error");
  } else {
    setStatus("Zip loaded. Ready to query.", "success");
  }
}

async function handleDrop(event) {
  const dataTransfer = event.dataTransfer;
  if (!dataTransfer) {
    setStatus("Drop a .xcodeproj folder or .zip file.", "error");
    return;
  }

  const items = Array.from(dataTransfer.items || []);
  const entries = items
    .map((item) => (item.webkitGetAsEntry ? item.webkitGetAsEntry() : null))
    .filter(Boolean);

  if (entries.length) {
    const xcodeprojEntry = entries.find((entry) => entry.isDirectory && entry.name.endsWith(".xcodeproj"));
    const directoryEntry = xcodeprojEntry || entries.find((entry) => entry.isDirectory);
    if (directoryEntry) {
      const files = [];
      await collectFilesFromEntry(directoryEntry, directoryEntry.name, files);
      if (!files.length) {
        setStatus("Dropped folder had no readable files.", "error");
        return;
      }
      await handleFolderSelection(files);
      return;
    }

    const zipEntry = entries.find((entry) => entry.isFile && entry.name.endsWith(".zip"));
    if (zipEntry && zipEntry.file) {
      zipEntry.file((file) => handleZipSelection(file));
      return;
    }
  }

  const files = Array.from(dataTransfer.files || []);
  if (files.length === 1 && files[0].name.endsWith(".zip")) {
    await handleZipSelection(files[0]);
    return;
  }
  if (files.length) {
    await handleFolderSelection(files);
    return;
  }

  setStatus("Drop a .xcodeproj folder or .zip file.", "error");
}

async function createRuntime(args = []) {
  if (!wasiReady) {
    const init = wasiModule.init ?? wasiModule.default;
    if (typeof init === "function") {
      await init();
    }
    wasiReady = true;
  }

  const WasmFs = wasmfsModule.WasmFs;
  const WASI = wasiModule.WASI;
  if (!WasmFs || !WASI) {
    throw new Error("WASI runtime failed to load.");
  }

  const wasmFs = new WasmFs();
  if (!("volume" in wasmFs.fs)) {
    wasmFs.fs.volume = wasmFs.volume;
  }

  const defaultBindings = wasiModule.defaultBindings ?? {};
  const wasi = new WASI({
    args,
    env: {},
    preopenDirectories: {},
    bindings: {
      ...defaultBindings,
      fs: wasmFs.fs,
    },
  });

  const wasmResponse = await fetch("xcodequery-wasm.wasm");
  if (!wasmResponse.ok) {
    throw new Error("xcodequery-wasm.wasm not found in web/.");
  }

  const module = await WebAssembly.compileStreaming(wasmResponse);
  const instance = await WebAssembly.instantiate(module, wasi.getImports(module));

  if (typeof wasi.initialize === "function") {
    wasi.initialize(instance);
  } else if (typeof wasi.start === "function") {
    try {
      wasi.start(instance);
    } catch (error) {
      const message = String(error);
      if (!message.includes("exit code: 0")) {
        console.warn(error);
      }
    }
  }

  return { instance };
}

function allocBytes(instance, data) {
  const alloc = instance.exports.xcq_alloc;
  if (!alloc) {
    throw new Error("xcq_alloc export is missing.");
  }
  const ptr = alloc(data.length);
  if (!ptr) {
    throw new Error("Unable to allocate memory inside WASM.");
  }
  const memory = new Uint8Array(instance.exports.memory.buffer, ptr, data.length);
  memory.set(data);
  return ptr;
}

function readCString(instance, ptr) {
  const memory = new Uint8Array(instance.exports.memory.buffer);
  let end = ptr;
  while (memory[end] !== 0) {
    end += 1;
  }
  return decoder.decode(memory.subarray(ptr, end));
}

function freeCString(instance, ptr) {
  const free = instance.exports.xcq_free;
  if (free && ptr) {
    free(ptr);
  }
}

function getLastError(instance) {
  const lastError = instance.exports.xcq_last_error;
  if (!lastError) {
    return null;
  }
  const ptr = lastError();
  if (!ptr) {
    return null;
  }
  const message = readCString(instance, ptr);
  freeCString(instance, ptr);
  return message;
}

async function runQuery() {
  if (!state.pbxprojEntry) {
    setStatus("Load a .xcodeproj folder or zip first.", "error");
    return;
  }

  const query = elements.queryInput.value.trim();
  if (!query) {
    setStatus("Enter a query to run.", "error");
    return;
  }

  elements.runButton.disabled = true;
  setStatus("Running query…", "idle");
  elements.output.textContent = "// Running…";

  try {
    const { instance } = await createRuntime(["xcodequery-wasm"]);
    const queryFn = instance.exports.xcq_query_from_pbxproj_json;
    if (!queryFn) {
      throw new Error("Missing export: xcq_query_from_pbxproj_json");
    }

    const projectPath = state.projectRoot ? `/workspace/${state.projectRoot}` : "/workspace/Project.xcodeproj";

    const dataPtr = allocBytes(instance, state.pbxprojEntry.data);
    const queryBytes = encoder.encode(query);
    const queryPtr = allocBytes(instance, queryBytes);
    const pathBytes = encoder.encode(projectPath);
    const pathPtr = allocBytes(instance, pathBytes);

    const resultPtr = queryFn(
      dataPtr,
      state.pbxprojEntry.data.length,
      queryPtr,
      queryBytes.length,
      pathPtr,
      pathBytes.length
    );

    freeCString(instance, dataPtr);
    freeCString(instance, queryPtr);
    freeCString(instance, pathPtr);

    if (!resultPtr) {
      const error = getLastError(instance) || "Unknown error";
      throw new Error(error);
    }

    const json = readCString(instance, resultPtr);
    freeCString(instance, resultPtr);
    elements.output.textContent = json;
    setStatus("Query complete.", "success");
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    elements.output.textContent = `// Error\n${message}`;
    setStatus(message, "error");
  } finally {
    elements.runButton.disabled = !state.pbxprojEntry;
  }
}

function attachEvents() {
  elements.projectInput.addEventListener("change", (event) => {
    handleFolderSelection(event.target.files);
  });

  elements.projectZipInput.addEventListener("change", (event) => {
    const file = event.target.files?.[0];
    handleZipSelection(file);
  });

  elements.dropZone.addEventListener("dragover", (event) => {
    event.preventDefault();
    elements.dropZone.classList.add("dragover");
  });

  elements.dropZone.addEventListener("dragleave", () => {
    elements.dropZone.classList.remove("dragover");
  });

  elements.dropZone.addEventListener("drop", (event) => {
    event.preventDefault();
    elements.dropZone.classList.remove("dragover");
    handleDrop(event);
  });

  elements.runButton.addEventListener("click", runQuery);
  elements.resetButton.addEventListener("click", resetState);
}

resetState();
renderExamples();
attachEvents();
