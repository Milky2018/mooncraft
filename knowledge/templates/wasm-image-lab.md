---
title: Wasm Image Lab Template
summary: Single-module MoonBit wasm-gc image lab template with a JS host shell
applies_to:
  - templates
  - wasm-image-lab
editable_files:
  - templates/wasm-image-lab/workspace/main.mbt
  - templates/wasm-image-lab/workspace/public
entrypoints:
  - main.mbt
validation:
  - moon check
  - moon build
status: draft
---

# Summary

This is a frontend-only MoonBit wasm-gc template for image tools, pixel experiments, and browser-side compute-heavy visual apps.

# Structure

- `moon.mod.json`: single module manifest with `preferred-target` set to `wasm-gc`
- `moon.pkg`: exports the MoonBit filter functions for the browser host
- `main.mbt`: numeric pixel-processing core compiled into wasm and staged as `app.wasm.txt`
- `public/index.html`: studio shell and controls
- `public/loader.js`: browser host that instantiates wasm, manages upload, and renders the canvas
- `public/styles.css`: visual system and responsive layout

# Invariants

- Keep this template as one MoonBit module.
- Do not add `moon.work`; the root `moon.mod.json` is intentional.
- Keep the exported MoonBit API numeric and browser-host friendly.
- The preview is static-only and stages arbitrary files from `public/` plus a base64-encoded wasm artifact.
- Use relative asset URLs such as `styles.css`, `loader.js`, and `app.wasm.txt`.

# Manual Preview Smoke

```bash
cd templates/wasm-image-lab/workspace
moon clean
moon check
moon build

preview_dir="$(mktemp -d)"
cp -R public/. "$preview_dir"
base64 < _build/wasm-gc/debug/build/wasm-image-lab.wasm > "$preview_dir/app.wasm.txt"

cd ../../..
moon run --manifest-path moon.work --target native services/control-plane -- \
  run-static-preview 19301 "$preview_dir"
```

Open `http://127.0.0.1:19301/`.

# Supported Edits

- add new filters and palette modes in MoonBit
- extend the browser shell with crop, compare, export, or timeline controls
- replace the procedural scenes with domain-specific mock images

# Do Not Do This

- do not move the filter core out of wasm unless the template itself stops being a wasm template
- do not rely on unstable MoonBit-to-JS array layouts across the wasm boundary
