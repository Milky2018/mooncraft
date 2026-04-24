const state = {
  scene: 0,
  filter: 0,
  exposure: 12,
  contrast: 18,
  grain: 22,
  vignette: 26,
  accent: 58,
  sourceKind: "generated",
  sourceLabel: "Editorial Portrait",
  uploadPixels: null,
  width: 384,
  height: 256,
};

const sceneLabels = [
  "Editorial Portrait",
  "Spectrum Poster",
  "X-Ray Scan",
];

const filterLabels = [
  "Lift",
  "Noir Glass",
  "Duotone Heat",
  "Thermal",
  "Poster",
  "Bloom",
];

const elements = {
  canvas: document.getElementById("preview-canvas"),
  statusCopy: document.getElementById("status-copy"),
  renderStats: document.getElementById("render-stats"),
  sourceLabel: document.getElementById("source-label"),
  fileInput: document.getElementById("file-input"),
  clearUpload: document.getElementById("clear-upload"),
  downloadButton: document.getElementById("download-button"),
  sceneButtons: [...document.querySelectorAll("[data-scene]")],
  filterButtons: [...document.querySelectorAll("[data-filter]")],
  sliders: {
    exposure: document.getElementById("exposure"),
    contrast: document.getElementById("contrast"),
    grain: document.getElementById("grain"),
    vignette: document.getElementById("vignette"),
    accent: document.getElementById("accent"),
  },
  sliderValues: {
    exposure: document.getElementById("exposure-value"),
    contrast: document.getElementById("contrast-value"),
    grain: document.getElementById("grain-value"),
    vignette: document.getElementById("vignette-value"),
    accent: document.getElementById("accent-value"),
  },
};

const outputContext = elements.canvas.getContext("2d");
const sourceCanvas = document.createElement("canvas");
const sourceContext = sourceCanvas.getContext("2d", {
  willReadFrequently: true,
});

let wasm = null;
let renderQueued = false;

function clampDimension(width, height) {
  const maxEdge = 448;
  const longest = Math.max(width, height);
  if (longest <= maxEdge) {
    return { width, height };
  }
  const scale = maxEdge / longest;
  return {
    width: Math.max(1, Math.round(width * scale)),
    height: Math.max(1, Math.round(height * scale)),
  };
}

function packRgb(r, g, b) {
  return (r * 65536 + g * 256 + b) | 0;
}

function unpackRgb(value) {
  const rgb = value >>> 0;
  return {
    r: (rgb >>> 16) & 255,
    g: (rgb >>> 8) & 255,
    b: rgb & 255,
  };
}

function updateActiveButtons(buttons, selected) {
  for (const button of buttons) {
    button.classList.toggle("is-active", Number(button.dataset.scene ?? button.dataset.filter) === selected);
  }
}

function updateSliderLabels() {
  for (const [key, input] of Object.entries(elements.sliders)) {
    elements.sliderValues[key].textContent = input.value;
  }
}

function updateStatus(text) {
  elements.statusCopy.textContent = text;
}

function updateSourceLabel() {
  elements.sourceLabel.textContent =
    state.sourceKind === "upload"
      ? `Using uploaded source at ${state.width}×${state.height}`
      : `Using built-in source: ${state.sourceLabel}`;
}

function setRenderSize(width, height) {
  state.width = width;
  state.height = height;
  elements.canvas.width = width;
  elements.canvas.height = height;
}

async function loadWasm() {
  updateStatus("Loading the MoonBit wasm-gc image core.");
  const response = await fetch("app.wasm.txt");
  if (!response.ok) {
    throw new Error(`Failed to load app.wasm.txt: ${response.status}`);
  }
  const encoded = (await response.text()).replace(/\s+/g, "");
  const binary = atob(encoded);
  const bytes = new Uint8Array(binary.length);
  for (let index = 0; index < binary.length; index += 1) {
    bytes[index] = binary.charCodeAt(index);
  }
  const { instance } = await WebAssembly.instantiate(bytes, {});
  if (typeof instance.exports._start === "function") {
    instance.exports._start();
  }
  wasm = instance.exports;
  updateStatus("MoonBit wasm-gc core loaded. Adjust a preset or upload an image.");
}

function scheduleRender() {
  if (renderQueued) {
    return;
  }
  renderQueued = true;
  requestAnimationFrame(() => {
    renderQueued = false;
    render();
  });
}

function readSliderState() {
  state.exposure = Number(elements.sliders.exposure.value);
  state.contrast = Number(elements.sliders.contrast.value);
  state.grain = Number(elements.sliders.grain.value);
  state.vignette = Number(elements.sliders.vignette.value);
  state.accent = Number(elements.sliders.accent.value);
  updateSliderLabels();
}

function renderGenerated(target, data) {
  const { width, height } = state;
  for (let y = 0; y < height; y += 1) {
    for (let x = 0; x < width; x += 1) {
      const offset = (y * width + x) * 4;
      const pixel = wasm.render_scene_pixel(
        state.scene,
        state.filter,
        x,
        y,
        width,
        height,
        state.exposure,
        state.contrast,
        state.grain,
        state.vignette,
        state.accent,
      );
      const rgb = unpackRgb(pixel);
      data[offset] = rgb.r;
      data[offset + 1] = rgb.g;
      data[offset + 2] = rgb.b;
      data[offset + 3] = 255;
    }
  }
}

function renderUpload(target, data) {
  const source = state.uploadPixels;
  const { width, height } = state;
  for (let y = 0; y < height; y += 1) {
    for (let x = 0; x < width; x += 1) {
      const offset = (y * width + x) * 4;
      const sourceRgb = packRgb(
        source[offset],
        source[offset + 1],
        source[offset + 2],
      );
      const pixel = wasm.filter_pixel(
        sourceRgb,
        state.filter,
        x,
        y,
        width,
        height,
        state.exposure,
        state.contrast,
        state.grain,
        state.vignette,
        state.accent,
      );
      const rgb = unpackRgb(pixel);
      data[offset] = rgb.r;
      data[offset + 1] = rgb.g;
      data[offset + 2] = rgb.b;
      data[offset + 3] = 255;
    }
  }
}

function render() {
  if (!wasm || !outputContext) {
    return;
  }
  const { width, height } = state;
  const frame = outputContext.createImageData(width, height);
  const start = performance.now();
  if (state.sourceKind === "upload" && state.uploadPixels) {
    renderUpload(outputContext, frame.data);
  } else {
    renderGenerated(outputContext, frame.data);
  }
  outputContext.putImageData(frame, 0, 0);
  const elapsed = performance.now() - start;
  elements.renderStats.textContent = `${filterLabels[state.filter]} · ${width}×${height} · ${elapsed.toFixed(1)}ms`;
}

function resetToGenerated() {
  state.sourceKind = "generated";
  state.uploadPixels = null;
  state.sourceLabel = sceneLabels[state.scene];
  setRenderSize(384, 256);
  updateSourceLabel();
  updateStatus("Back on the procedural MoonBit source.");
  scheduleRender();
}

async function loadUpload(file) {
  const url = URL.createObjectURL(file);
  try {
    const image = new Image();
    await new Promise((resolve, reject) => {
      image.onload = resolve;
      image.onerror = reject;
      image.src = url;
    });
    const nextSize = clampDimension(image.naturalWidth, image.naturalHeight);
    sourceCanvas.width = nextSize.width;
    sourceCanvas.height = nextSize.height;
    sourceContext.clearRect(0, 0, nextSize.width, nextSize.height);
    sourceContext.drawImage(image, 0, 0, nextSize.width, nextSize.height);
    state.uploadPixels = sourceContext.getImageData(
      0,
      0,
      nextSize.width,
      nextSize.height,
    ).data;
    state.sourceKind = "upload";
    state.sourceLabel = file.name;
    setRenderSize(nextSize.width, nextSize.height);
    updateSourceLabel();
    updateStatus("Uploaded image ready. The filter core is now processing your pixels in MoonBit.");
    scheduleRender();
  } finally {
    URL.revokeObjectURL(url);
  }
}

function wireControls() {
  updateSliderLabels();
  updateSourceLabel();

  for (const button of elements.sceneButtons) {
    button.addEventListener("click", () => {
      state.scene = Number(button.dataset.scene);
      state.sourceLabel = sceneLabels[state.scene];
      updateActiveButtons(elements.sceneButtons, state.scene);
      if (state.sourceKind !== "upload") {
        updateSourceLabel();
      }
      scheduleRender();
    });
  }

  for (const button of elements.filterButtons) {
    button.addEventListener("click", () => {
      state.filter = Number(button.dataset.filter);
      updateActiveButtons(elements.filterButtons, state.filter);
      scheduleRender();
    });
  }

  for (const input of Object.values(elements.sliders)) {
    input.addEventListener("input", () => {
      readSliderState();
      scheduleRender();
    });
  }

  elements.fileInput.addEventListener("change", async (event) => {
    const file = event.target.files?.[0];
    if (!file) {
      return;
    }
    try {
      updateStatus("Decoding upload and staging it for the MoonBit filter core.");
      await loadUpload(file);
    } catch (error) {
      updateStatus(`Upload failed: ${error instanceof Error ? error.message : String(error)}`);
    }
  });

  elements.clearUpload.addEventListener("click", () => {
    elements.fileInput.value = "";
    resetToGenerated();
  });

  elements.downloadButton.addEventListener("click", () => {
    elements.canvas.toBlob((blob) => {
      if (!blob) {
        return;
      }
      const url = URL.createObjectURL(blob);
      const link = document.createElement("a");
      link.href = url;
      link.download = "wasm-image-lab.png";
      link.click();
      URL.revokeObjectURL(url);
    });
  });
}

async function boot() {
  readSliderState();
  wireControls();
  updateActiveButtons(elements.sceneButtons, state.scene);
  updateActiveButtons(elements.filterButtons, state.filter);
  try {
    await loadWasm();
    scheduleRender();
  } catch (error) {
    updateStatus(
      `This browser could not start the MoonBit wasm-gc core. ${error instanceof Error ? error.message : String(error)}`,
    );
    elements.renderStats.textContent = "wasm start failed";
  }
}

boot();
