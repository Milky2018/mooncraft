#!/usr/bin/env bash
set -euo pipefail

port="${1:-${MOONCRAFT_PLAYWRIGHT_REAL_AGENT_PORT:-8096}}"
base_url="http://127.0.0.1:${port}"
playwright_version="${MOONCRAFT_PLAYWRIGHT_VERSION:-1.56.1}"
artifact_root="${MOONCRAFT_PLAYWRIGHT_OUTPUT_DIR:-output/playwright/real-agent-story}"
run_stamp="$(date +%Y%m%d-%H%M%S)"
artifact_dir="${artifact_root}/${run_stamp}"
repo_root="$(cd "$(dirname "$0")/.." && pwd)"
default_agent_runtime_image="$(cat "$repo_root/config/agent_runtime_image.txt")"
model="${MOONCRAFT_PLAYWRIGHT_REAL_AGENT_MODEL:-${MOONCRAFT_AGENT_SMOKE_MODEL:-${MOONCRAFT_CODEX_SMOKE_MODEL:-anthropic/claude-sonnet-4.5}}}"
if [[ -n "${MOONCRAFT_PLAYWRIGHT_REAL_AGENT_KEY_REF:-}" ]]; then
  key_ref="$MOONCRAFT_PLAYWRIGHT_REAL_AGENT_KEY_REF"
elif [[ -n "${MOONCRAFT_AGENT_SMOKE_KEY_REF:-}" ]]; then
  key_ref="$MOONCRAFT_AGENT_SMOKE_KEY_REF"
elif [[ -n "${MOONCRAFT_CODEX_SMOKE_KEY_REF:-}" ]]; then
  key_ref="$MOONCRAFT_CODEX_SMOKE_KEY_REF"
elif [[ -n "${MOONCRAFT_PLAYWRIGHT_REAL_AGENT_API_KEY:-}" ]]; then
  key_ref="MOONCRAFT_PLAYWRIGHT_REAL_AGENT_API_KEY"
elif [[ -n "${MOONCRAFT_AGENT_SMOKE_API_KEY:-}" ]]; then
  key_ref="MOONCRAFT_AGENT_SMOKE_API_KEY"
elif [[ -n "${MOONCRAFT_CODEX_SMOKE_API_KEY:-}" ]]; then
  key_ref="MOONCRAFT_CODEX_SMOKE_API_KEY"
else
  key_ref="OPENROUTER_API_KEY"
fi
api_key="${!key_ref:-}"
agent_runtime_image="${MOONCRAFT_AGENT_RUNTIME_IMAGE:-${MOONCRAFT_CODEX_DOCKER_IMAGE:-$default_agent_runtime_image}}"
admin_token="${MOONCRAFT_PLAYWRIGHT_REAL_AGENT_ADMIN_TOKEN:-playwright-real-agent-admin-token}"

if [[ -z "$api_key" ]]; then
  echo "Set $key_ref or MOONCRAFT_PLAYWRIGHT_REAL_AGENT_KEY_REF to an environment variable containing an OpenRouter API key." >&2
  echo "This browser story uses a real platform-managed AI key and is intentionally opt-in." >&2
  exit 1
fi

if ! command -v docker >/dev/null 2>&1; then
  echo "docker is required for the real-agent Playwright story." >&2
  exit 1
fi

if ! command -v npm >/dev/null 2>&1; then
  echo "npm is required for the real-agent Playwright story." >&2
  exit 1
fi

if ! command -v node >/dev/null 2>&1; then
  echo "node is required for the real-agent Playwright story." >&2
  exit 1
fi

if curl -fsS "${base_url}/api/health" >/dev/null 2>&1; then
  echo "Port ${port} is already serving a control plane. Stop it first." >&2
  exit 1
fi

mkdir -p "$artifact_dir"
artifact_dir="$(cd "$artifact_dir" && pwd)"
tmpdir="$(mktemp -d)"
log_file="${artifact_dir}/control-plane.log"
runner_dir="${tmpdir}/playwright-runner"
runner_script="${runner_dir}/real-agent-story.js"
server_pid=""

cleanup() {
  if [[ -n "$server_pid" ]]; then
    kill "$server_pid" >/dev/null 2>&1 || true
    wait "$server_pid" >/dev/null 2>&1 || true
  fi
  rm -rf "$tmpdir"
}
trap cleanup EXIT

mkdir -p "$runner_dir"
(
  cd "$runner_dir"
  npm init -y >/dev/null
  npm install --silent --no-audit --no-fund "playwright@${playwright_version}" >/dev/null
  npx playwright install chromium >/dev/null
)

cat >"$runner_script" <<'EOF'
const fs = require("node:fs")
const path = require("node:path")
const { chromium } = require("playwright")

const baseUrl = process.env.MOONCRAFT_PLAYWRIGHT_BASE_URL
const artifactDir = process.env.MOONCRAFT_PLAYWRIGHT_ARTIFACT_DIR
const model = process.env.MOONCRAFT_PLAYWRIGHT_REAL_AGENT_MODEL
const timeoutSeconds = Number(process.env.MOONCRAFT_PLAYWRIGHT_REAL_AGENT_TIMEOUT_SECONDS || "1800")
const expectedPreviewTerms = (process.env.MOONCRAFT_PLAYWRIGHT_REAL_AGENT_EXPECTED_TERMS || "counter,increment,reset")
  .split(",")
  .map((term) => term.trim().toLowerCase())
  .filter(Boolean)

if (!baseUrl) throw new Error("MOONCRAFT_PLAYWRIGHT_BASE_URL is required")
if (!artifactDir) throw new Error("MOONCRAFT_PLAYWRIGHT_ARTIFACT_DIR is required")
if (!model) throw new Error("MOONCRAFT_PLAYWRIGHT_REAL_AGENT_MODEL is required")

const screenshot = (name) => path.join(artifactDir, name)
const prompt = process.env.MOONCRAFT_PLAYWRIGHT_REAL_AGENT_PROMPT ||
  "Build a tiny MoonBit counter app with a clear heading, increment and reset controls, and a live preview UI."

async function waitForRun(page, projectId, runId) {
  const deadline = Date.now() + timeoutSeconds * 1000
  let run = null
  while (Date.now() < deadline) {
    run = await page.evaluate(async ([projectId, runId]) => {
      const response = await fetch(`/api/projects/${projectId}/runs/${runId}`)
      if (!response.ok) return null
      return await response.json()
    }, [projectId, runId])
    if (run && run.state !== "Running") return run
    await page.waitForTimeout(5000)
  }
  throw new Error(`Timed out after ${timeoutSeconds}s waiting for run ${runId}`)
}

async function projectDetail(page, projectId) {
  return await page.evaluate(async (projectId) => {
    const response = await fetch(`/api/projects/${projectId}`)
    if (!response.ok) throw new Error(`Project detail failed with HTTP ${response.status}`)
    return await response.json()
  }, projectId)
}

function writeReport(name, body) {
  fs.writeFileSync(path.join(artifactDir, name), body)
}

async function main() {
  const browser = await chromium.launch({ headless: true })
  const page = await browser.newPage({ viewport: { width: 1440, height: 980 } })
  page.setDefaultTimeout(30000)
  const email = `real-agent-story-${Date.now()}@example.com`
  const screenshots = []
  let projectId = ""
  let runId = ""

  try {
    await page.goto(baseUrl, { waitUntil: "domcontentloaded" })
    const authResponse = await page.evaluate(async (email) => {
      return await fetch("/api/dev/auth/session", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ email, display_name: "Real Agent Tester" }),
      }).then((response) => ({ ok: response.ok, status: response.status }))
    }, email)
    if (!authResponse.ok) {
      throw new Error(`Development sign-in failed with HTTP ${authResponse.status}`)
    }
    await page.reload({ waitUntil: "domcontentloaded" })
    await page.getByRole("button", { name: /Real Agent Tester/ }).waitFor()
    screenshots.push(screenshot("02-signed-in.png"))
    await page.screenshot({ path: screenshots[screenshots.length - 1], fullPage: true })

    await page.getByPlaceholder("Project name").first().fill("Snake Game")
    await page.getByRole("button", { name: "Create Project" }).first().click()
    await page.locator("textarea").fill(prompt)
    screenshots.push(screenshot("03-real-agent-prompt.png"))
    await page.screenshot({ path: screenshots[screenshots.length - 1], fullPage: true })

    const runResponsePromise = page.waitForResponse((response) => {
      return response.url().includes("/api/projects/") &&
        response.url().includes("/runs") &&
        response.request().method() === "POST"
    })
    await page.getByRole("button", { name: /Build With Mooncraft|Send Request/ }).click()
    screenshots.push(screenshot("04-real-agent-run-started.png"))
    await page.screenshot({ path: screenshots[screenshots.length - 1], fullPage: true })

    const runResponse = await runResponsePromise
    if (!runResponse.ok()) throw new Error(`Run creation failed with HTTP ${runResponse.status()}`)
    const createdRun = await runResponse.json()
    projectId = createdRun.run.project_id
    runId = createdRun.run.run_id

    const run = await waitForRun(page, projectId, runId)
    if (run.state !== "Succeeded") {
      throw new Error(`Expected real-agent run to succeed, got ${run.state}: ${run.error_message || ""}`)
    }
    if (!run.preview || !run.preview.healthy || !run.preview.url) {
      throw new Error("Expected the real-agent run to produce a healthy preview")
    }

    await page.reload({ waitUntil: "domcontentloaded" })
    await page.getByText(prompt).waitFor()
    const detail = await projectDetail(page, projectId)
    if (!detail.codex_thread_id) {
      throw new Error("Expected a persisted Codex thread id")
    }
    const previewFrame = page.frameLocator(`iframe[src*="${run.preview.url}"]`)
    await previewFrame.locator("body").waitFor()
    screenshots.push(screenshot("05-real-agent-preview.png"))
    await page.screenshot({ path: screenshots[screenshots.length - 1], fullPage: true })

    const previewPage = await browser.newPage({ viewport: { width: 1280, height: 900 } })
    await previewPage.goto(`${baseUrl}${run.preview.url}`, { waitUntil: "domcontentloaded" })
    await previewPage.waitForLoadState("networkidle", { timeout: 30000 }).catch(() => {})
    const previewText = (await previewPage.locator("body").innerText({ timeout: 30000 })).toLowerCase()
    if (expectedPreviewTerms.length > 0 && !expectedPreviewTerms.some((term) => previewText.includes(term))) {
      throw new Error(`Preview loaded, but none of the expected terms were visible: ${expectedPreviewTerms.join(", ")}`)
    }
    screenshots.push(screenshot("06-live-preview-direct.png"))
    await previewPage.screenshot({ path: screenshots[screenshots.length - 1], fullPage: true })

    const report = `# Playwright Real-Agent Story Report

- Result: Passed
- App URL: \`${baseUrl}\`
- Provider: \`OpenRouter (platform key pool)\`
- Model: \`${model}\`
- User: \`${email}\`
- Project ID: \`${projectId}\`
- Run ID: \`${runId}\`
- Preview URL: \`${run.preview.url}\`
- Codex thread ID persisted: yes
- Expected preview terms: \`${expectedPreviewTerms.join(", ")}\`

## Assertions

- Development sign-in succeeds.
- Browser prompt starts a real Docker-backed agent run.
- The run reaches \`Succeeded\`.
- The project persists a Codex thread ID.
- The preview iframe loads the generated app.
- The direct preview page contains at least one expected user-facing term.

## Screenshots

${screenshots.map((shot, index) => `### ${index + 1}. ${path.basename(shot)}

![${path.basename(shot)}](${shot})
`).join("\n")}
`
    writeReport("REPORT.md", report)
    console.log(JSON.stringify({
      result: "passed",
      artifactDir,
      reportPath: path.join(artifactDir, "REPORT.md"),
      model,
      email,
      projectId,
      runId,
      previewUrl: run.preview.url,
      screenshots,
    }, null, 2))
  } catch (error) {
    const failureShot = screenshot("failure.png")
    await page.screenshot({ path: failureShot, fullPage: true }).catch(() => {})
    writeReport("FAILURE.md", `# Playwright Real-Agent Story Failure

- Result: Failed
- App URL: \`${baseUrl}\`
- Provider: \`OpenRouter (platform key pool)\`
- Model: \`${model}\`
- Project ID: \`${projectId || "unknown"}\`
- Run ID: \`${runId || "unknown"}\`
- Error: \`${String(error.message || error)}\`

![Failure screenshot](${failureShot})
`)
    throw error
  } finally {
    await browser.close()
  }
}

main().catch((error) => {
  console.error(error)
  process.exit(1)
})
EOF

moon -C . build

MOONCRAFT_PORT="$port" \
MOONCRAFT_PUBLIC_BASE_URL="$base_url" \
MOONCRAFT_APP_MODE="${MOONCRAFT_APP_MODE:-test}" \
MOONCRAFT_BUILD_PROFILE=debug \
MOONCRAFT_CODEX_FAKE_MODE= \
MOONCRAFT_ENABLE_DEV_AUTH=1 \
MOONCRAFT_ADMIN_TOKEN="$admin_token" \
MOONCRAFT_AGENT_RUNTIME_IMAGE="$agent_runtime_image" \
./_build/native/debug/build/mooncraft/control-plane/control-plane.exe >"$log_file" 2>&1 &
server_pid=$!

for _ in {1..60}; do
  if curl -fsS "${base_url}/api/health" >/dev/null 2>&1; then
    break
  fi
  sleep 1
done

if ! curl -fsS "${base_url}/api/health" | grep -q '"ok":true'; then
  echo "Control plane did not become healthy. Log: ${log_file}" >&2
  sed -n '1,220p' "$log_file" >&2 || true
  exit 1
fi

admin_header=(-H "Authorization: Bearer $admin_token" -H 'Content-Type: application/json')
curl -fsS "${admin_header[@]}" \
  -X PUT "${base_url}/api/admin/ai/config" \
  --data-binary "{\"default_model\":\"$model\",\"allowed_models\":[\"$model\"]}" \
  >/dev/null
curl -fsS "${admin_header[@]}" \
  -X POST "${base_url}/api/admin/ai/keys" \
  --data-binary "{\"label\":\"Playwright real-agent key\",\"api_key\":\"$api_key\",\"priority\":100}" \
  >/dev/null

MOONCRAFT_PLAYWRIGHT_BASE_URL="$base_url" \
MOONCRAFT_PLAYWRIGHT_ARTIFACT_DIR="$artifact_dir" \
MOONCRAFT_PLAYWRIGHT_REAL_AGENT_MODEL="$model" \
  node "$runner_script" | tee "${artifact_dir}/result.json"

echo "Playwright real-agent report: ${artifact_dir}/REPORT.md"
