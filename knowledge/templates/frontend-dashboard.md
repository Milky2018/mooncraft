---
title: Frontend Dashboard Template
summary: Single-module MoonBit frontend template for static dashboard pages
applies_to:
  - templates
  - frontend-dashboard
editable_files:
  - templates/frontend-dashboard/workspace/main.mbt
  - templates/frontend-dashboard/workspace/public
entrypoints:
  - main.mbt
validation:
  - moon check
  - moon build
  - run direct static preview smoke
  - run control-plane smoke with template_id frontend-dashboard
status: draft
---

# Summary

This is a pure frontend MoonBit template for dashboard, landing page, and product-page requests.

# Structure

- `moon.mod.json`: single module manifest with `preferred-target` set to `js`
- `moon.pkg`: root executable package
- `main.mbt`: Rabbita page implementation
- `public/index.html`: preview HTML shell
- `public/styles.css`: visual system and responsive layout

# Invariants

- Keep this template as one MoonBit module.
- Do not add `moon.work`; the root `moon.mod.json` is intentional.
- Keep validation to one `moon check` and one `moon build` at the module root.
- Keep the preview static-only; do not add a generated backend.
- Use relative preview asset URLs in `public/index.html`, such as `styles.css` and `app.js`, so the page works under `/p/<preview_public_id>/`.

# Manual Preview Smoke

```bash
cd templates/frontend-dashboard/workspace
moon clean
moon check
moon build

preview_dir="$(mktemp -d)"
cp public/index.html "$preview_dir/index.html"
cp public/styles.css "$preview_dir/styles.css"
cp _build/js/debug/build/frontend-dashboard.js "$preview_dir/app.js"

cd ../../..
moon run --manifest-path moon.work --target native services/control-plane -- \
  run-static-preview 19301 "$preview_dir"
```

Open `http://127.0.0.1:19301/`.

# Product Smoke

```bash
cd /Users/zhengyu/.codex/worktrees/6b76/moonbitcloud
MOONBITCLOUD_CODEX_FAKE_MODE=smoke MOONBITCLOUD_PORT=19312 \
  moon run --manifest-path moon.work --target native services/control-plane
```

Then:

- open `http://127.0.0.1:19312/`
- sign up or log in
- create a project with `template_id: "frontend-dashboard"`
- create one run and wait for a healthy preview
- verify `/p/<preview_public_id>/`, `/p/<preview_public_id>/app.js`, and `/p/<preview_public_id>/styles.css`

# Supported Edits

- change the page copy and visual direction
- add sections, cards, forms, and frontend-only interactions
- reshape the dashboard into a landing page, portfolio, or product page

# Do Not Do This

- do not introduce backend routes or API state into this template
- do not split this template into multiple modules unless the template id and manifest are changed
