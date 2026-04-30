#!/usr/bin/env bash
set -euo pipefail

port="${1:-${MOONCRAFT_PLAYWRIGHT_REAL_AGENT_PORT:-8096}}"
base_url="http://127.0.0.1:${port}"
playwright_version="${MOONCRAFT_PLAYWRIGHT_VERSION:-1.56.1}"
artifact_root="${MOONCRAFT_PLAYWRIGHT_OUTPUT_DIR:-output/playwright/real-agent-story}"
run_stamp="$(date +%Y%m%d-%H%M%S)"
artifact_dir="${artifact_root}/${run_stamp}"
provider="${MOONCRAFT_PLAYWRIGHT_REAL_AGENT_PROVIDER:-${MOONCRAFT_CODEX_SMOKE_PROVIDER:-openrouter}}"
model="${MOONCRAFT_PLAYWRIGHT_REAL_AGENT_MODEL:-${MOONCRAFT_CODEX_SMOKE_MODEL:-openai/gpt-5.5}}"
api_key="${MOONCRAFT_PLAYWRIGHT_REAL_AGENT_API_KEY:-${MOONCRAFT_CODEX_SMOKE_API_KEY:-}}"
codex_image="${MOONCRAFT_CODEX_DOCKER_IMAGE:-docker.io/moonbitcloud/codex:codex-0.125.0-node24}"

if [[ -z "$api_key" ]]; then
  echo "MOONCRAFT_PLAYWRIGHT_REAL_AGENT_API_KEY is required." >&2
  echo "This browser story uses a real provider-backed Codex run and is intentionally opt-in." >&2
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
const provider = process.env.MOONCRAFT_PLAYWRIGHT_REAL_AGENT_PROVIDER
const model = process.env.MOONCRAFT_PLAYWRIGHT_REAL_AGENT_MODEL
const apiKey = process.env.MOONCRAFT_PLAYWRIGHT_REAL_AGENT_API_KEY
const timeoutSeconds = Number(process.env.MOONCRAFT_PLAYWRIGHT_REAL_AGENT_TIMEOUT_SECONDS || "1800")

if (!baseUrl) throw new Error("MOONCRAFT_PLAYWRIGHT_BASE_URL is required")
if (!artifactDir) throw new Error("MOONCRAFT_PLAYWRIGHT_ARTIFACT_DIR is required")
if (!provider) throw new Error("MOONCRAFT_PLAYWRIGHT_REAL_AGENT_PROVIDER is required")
if (!model) throw new Error("MOONCRAFT_PLAYWRIGHT_REAL_AGENT_MODEL is required")
if (!apiKey) throw new Error("MOONCRAFT_PLAYWRIGHT_REAL_AGENT_API_KEY is required")

const screenshot = (name) => path.join(artifactDir, name)
const prompt =
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
  const password = "password123"
  const screenshots = []
  let projectId = ""
  let runId = ""

  try {
    await page.goto(baseUrl, { waitUntil: "domcontentloaded" })
    await page.getByLabel("Email").fill(email)
    await page.getByLabel("Password").fill(password)
    await page.getByLabel("Display Name").fill("Real Agent Tester")
    screenshots.push(screenshot("01-signup-form.png"))
    await page.screenshot({ path: screenshots[screenshots.length - 1], fullPage: true })

    await page.getByRole("button", { name: "Create Account" }).click()
    await page.getByRole("button", { name: /Real Agent Tester/ }).waitFor()
    await page.evaluate(async ({ provider, model, apiKey }) => {
      const response = await fetch("/api/account/ai-settings", {
        method: "PUT",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ provider, model, api_key: apiKey }),
      })
      if (!response.ok) throw new Error(`AI settings failed with HTTP ${response.status}`)
      const settings = await response.json()
      if (!settings.api_key_configured) throw new Error("AI settings did not persist an API key")
    }, { provider, model, apiKey })
    screenshots.push(screenshot("02-ai-settings-configured.png"))
    await page.screenshot({ path: screenshots[screenshots.length - 1], fullPage: true })

    await page.getByRole("button", { name: "+ New Project" }).click()
    await page.getByPlaceholder("Describe the change you want.").fill(prompt)
    screenshots.push(screenshot("03-real-agent-prompt.png"))
    await page.screenshot({ path: screenshots[screenshots.length - 1], fullPage: true })

    const runResponsePromise = page.waitForResponse((response) => {
      return response.url().includes("/api/projects/") &&
        response.url().includes("/runs") &&
        response.request().method() === "POST"
    })
    await page.getByRole("button", { name: "Send Request" }).click()
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
    await page.getByText("The app is updated and the preview is ready.").waitFor()
    const detail = await projectDetail(page, projectId)
    if (!detail.codex_thread_id) {
      throw new Error("Expected a persisted Codex thread id")
    }
    const previewFrame = page.frameLocator(`iframe[src*="${run.preview.url}"]`)
    await previewFrame.locator("body").waitFor()
    screenshots.push(screenshot("05-real-agent-preview.png"))
    await page.screenshot({ path: screenshots[screenshots.length - 1], fullPage: true })

    const report = `# Playwright Real-Agent Story Report

- Result: Passed
- App URL: \`${baseUrl}\`
- Provider: \`${provider}\`
- Model: \`${model}\`
- User: \`${email}\`
- Project ID: \`${projectId}\`
- Run ID: \`${runId}\`
- Preview URL: \`${run.preview.url}\`
- Codex thread ID persisted: yes

## Assertions

- Browser signup succeeds.
- User-scoped AI settings are saved without storing provider secrets in this report.
- Browser prompt starts a real Docker-backed Codex run.
- The run reaches \`Succeeded\`.
- The project persists a Codex thread ID.
- The preview iframe loads the generated app.

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
      provider,
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
- Provider: \`${provider}\`
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

MOONCRAFT_PORT="$port" \
MOONCRAFT_PUBLIC_BASE_URL="$base_url" \
MOONCRAFT_BUILD_PROFILE=debug \
MOONCRAFT_CODEX_FAKE_MODE= \
MOONCRAFT_CODEX_DOCKER_IMAGE="$codex_image" \
moon -C . run --target native services/control-plane >"$log_file" 2>&1 &
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

MOONCRAFT_PLAYWRIGHT_BASE_URL="$base_url" \
MOONCRAFT_PLAYWRIGHT_ARTIFACT_DIR="$artifact_dir" \
MOONCRAFT_PLAYWRIGHT_REAL_AGENT_PROVIDER="$provider" \
MOONCRAFT_PLAYWRIGHT_REAL_AGENT_MODEL="$model" \
MOONCRAFT_PLAYWRIGHT_REAL_AGENT_API_KEY="$api_key" \
  node "$runner_script" | tee "${artifact_dir}/result.json"

echo "Playwright real-agent report: ${artifact_dir}/REPORT.md"
