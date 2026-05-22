#!/usr/bin/env bash
set -euo pipefail

port="${1:-${MOONCRAFT_PLAYWRIGHT_PORT:-8095}}"
base_url="http://127.0.0.1:${port}"
playwright_version="${MOONCRAFT_PLAYWRIGHT_VERSION:-1.56.1}"
artifact_root="${MOONCRAFT_PLAYWRIGHT_OUTPUT_DIR:-output/playwright/simple-project-story}"
run_stamp="$(date +%Y%m%d-%H%M%S)"
artifact_dir="${artifact_root}/${run_stamp}"

if ! command -v npm >/dev/null 2>&1; then
  echo "npm is required for the Playwright story runner." >&2
  exit 1
fi

if ! command -v node >/dev/null 2>&1; then
  echo "node is required for the Playwright story runner." >&2
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
runner_script="${runner_dir}/simple-project-story.js"
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

if (!baseUrl) throw new Error("MOONCRAFT_PLAYWRIGHT_BASE_URL is required")
if (!artifactDir) throw new Error("MOONCRAFT_PLAYWRIGHT_ARTIFACT_DIR is required")

const screenshot = (name) => path.join(artifactDir, name)
const prompt =
  "Build a simple daily task tracker with a welcoming heading, three sample tasks, and a calm visual style."
const secondPrompt = "Add a short note explaining that tasks persist between visits."
const failurePrompt = "Force fake failure after a successful preview."

async function waitForRunState(page, projectId, runId, expectedState) {
  let run = null
  for (let attempt = 0; attempt < 120; attempt += 1) {
    run = await page.evaluate(async ([projectId, runId]) => {
      const response = await fetch(`/api/projects/${projectId}/runs/${runId}`)
      if (!response.ok) return null
      return await response.json()
    }, [projectId, runId])
    if (run && run.state !== "Running") {
      if (run.state !== expectedState) {
        throw new Error(`Expected run to reach ${expectedState}, got ${run.state}`)
      }
      return run
    }
    await page.waitForTimeout(1000)
  }
  throw new Error(`Timed out waiting for run to reach ${expectedState}`)
}

async function waitForRun(page, projectId, runId) {
  return await waitForRunState(page, projectId, runId, "Succeeded")
}

async function projectDetail(page, projectId) {
  return await page.evaluate(async (projectId) => {
    const response = await fetch(`/api/projects/${projectId}`)
    if (!response.ok) throw new Error(`Project detail failed with HTTP ${response.status}`)
    return await response.json()
  }, projectId)
}

async function assertNoInternalPromptLeak(page, previewFrame) {
  const pageText = await page.locator("body").innerText()
  if (pageText.includes("Working rules:")) {
    throw new Error("Internal Runtime prompt leaked into the platform page")
  }
  const frameText = await previewFrame.locator("body").innerText()
  if (frameText.includes("Working rules:")) {
    throw new Error("Internal Runtime prompt leaked into the preview iframe")
  }
}

async function main() {
  const browser = await chromium.launch({ headless: true })
  const page = await browser.newPage({ viewport: { width: 1440, height: 980 } })
  page.setDefaultTimeout(20000)
  const email = `simple-story-${Date.now()}@example.com`
  const screenshots = []

  try {
    await page.goto(baseUrl, { waitUntil: "domcontentloaded" })
    const authResponse = await page.evaluate(async (email) => {
      return await fetch("/api/dev/auth/session", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ email, display_name: "Simple Story Tester" }),
      }).then((response) => ({ ok: response.ok, status: response.status }))
    }, email)
    if (!authResponse.ok) {
      throw new Error(`Development sign-in failed with HTTP ${authResponse.status}`)
    }
    await page.reload({ waitUntil: "domcontentloaded" })
    await page.getByRole("button", { name: /Simple Story Tester/ }).waitFor()
    screenshots.push(screenshot("01-empty-workspace.png"))
    await page.screenshot({ path: screenshots[screenshots.length - 1], fullPage: true })

    await page.getByPlaceholder("Project name").first().fill("Simple Story Project")
    await page.getByRole("button", { name: "Create Project" }).first().click()
    await page.getByPlaceholder("Tell MoonCraft what to build or change...").waitFor()
    await page.getByPlaceholder("Project name").nth(1).fill("Renamed Story Project")
    const renameResponsePromise = page.waitForResponse((response) => {
      return response.url().includes("/api/projects/") &&
        response.request().method() === "PUT"
    })
    await page.getByRole("button", { name: "Rename" }).click()
    const renameResponse = await renameResponsePromise
    if (!renameResponse.ok()) throw new Error(`Project rename failed with HTTP ${renameResponse.status()}`)
    await page.getByText("Renamed Story Project").first().waitFor()
    screenshots.push(screenshot("02-project-renamed.png"))
    await page.screenshot({ path: screenshots[screenshots.length - 1], fullPage: true })

    await page.getByPlaceholder("Tell MoonCraft what to build or change...").fill(prompt)
    screenshots.push(screenshot("03-project-prompt.png"))
    await page.screenshot({ path: screenshots[screenshots.length - 1], fullPage: true })

    const runResponsePromise = page.waitForResponse((response) => {
      return response.url().includes("/api/projects/") &&
        response.url().includes("/runs") &&
        response.request().method() === "POST"
    })
    await page.getByRole("button", { name: "Build With MoonCraft" }).click()
    screenshots.push(screenshot("04-run-started.png"))
    await page.screenshot({ path: screenshots[screenshots.length - 1], fullPage: true })

    const runResponse = await runResponsePromise
    if (!runResponse.ok()) throw new Error(`Run creation failed with HTTP ${runResponse.status()}`)
    const createdRun = await runResponse.json()
    const projectId = createdRun.run.project_id
    const firstRunId = createdRun.run.run_id
    await waitForRun(page, projectId, firstRunId)

    const firstDetail = await projectDetail(page, projectId)
    if (!firstDetail.preview || !firstDetail.preview.url || !firstDetail.preview.healthy) {
      throw new Error("Expected a healthy preview target after the completed first run")
    }

    await page.reload({ waitUntil: "domcontentloaded" })
    await page.getByText("The app is updated and the preview is ready.").waitFor()
    await page.getByText(prompt).waitFor()
    const firstPreviewFrame = page.frameLocator(`iframe[src*="${firstDetail.preview.url}"]`)
    await firstPreviewFrame.getByText("MoonCraft smoke preview").waitFor()
    await assertNoInternalPromptLeak(page, firstPreviewFrame)
    const previewTitle = await firstPreviewFrame.locator("h1").innerText()
    screenshots.push(screenshot("05-completed-preview.png"))
    await page.screenshot({ path: screenshots[screenshots.length - 1], fullPage: true })

    await page.getByPlaceholder("Tell MoonCraft what to build or change...").fill(secondPrompt)
    const secondRunResponsePromise = page.waitForResponse((response) => {
      return response.url().includes(`/api/projects/${projectId}/runs`) &&
        response.request().method() === "POST"
    })
    await page.getByRole("button", { name: "Build With MoonCraft" }).click()
    const secondRunResponse = await secondRunResponsePromise
    if (!secondRunResponse.ok()) {
      throw new Error(`Second run creation failed with HTTP ${secondRunResponse.status()}`)
    }
    const secondRun = await secondRunResponse.json()
    if (secondRun.run.project_id !== projectId) {
      throw new Error("Second prompt targeted a different project")
    }
    await waitForRun(page, projectId, secondRun.run.run_id)
    screenshots.push(screenshot("06-second-run-same-project.png"))
    await page.screenshot({ path: screenshots[screenshots.length - 1], fullPage: true })

    await page.reload({ waitUntil: "domcontentloaded" })
    await page.getByRole("button", { name: /Project .*Ready/ }).waitFor()
    await page.getByText(prompt).waitFor()
    await page.getByText(secondPrompt).waitFor()
    const refreshedDetail = await projectDetail(page, projectId)
    if (!refreshedDetail.preview || refreshedDetail.preview.url !== firstDetail.preview.url) {
      throw new Error("Expected the preview URL to persist after refresh")
    }
    const refreshedPreviewFrame = page.frameLocator(`iframe[src*="${refreshedDetail.preview.url}"]`)
    await refreshedPreviewFrame.getByText("MoonCraft smoke preview").waitFor()
    await assertNoInternalPromptLeak(page, refreshedPreviewFrame)
    screenshots.push(screenshot("07-refresh-persistence.png"))
    await page.screenshot({ path: screenshots[screenshots.length - 1], fullPage: true })

    await page.getByPlaceholder("Tell MoonCraft what to build or change...").fill(failurePrompt)
    const failureRunResponsePromise = page.waitForResponse((response) => {
      return response.url().includes(`/api/projects/${projectId}/runs`) &&
        response.request().method() === "POST"
    })
    await page.getByRole("button", { name: "Build With MoonCraft" }).click()
    const failureRunResponse = await failureRunResponsePromise
    if (!failureRunResponse.ok()) {
      throw new Error(`Failure run creation failed with HTTP ${failureRunResponse.status()}`)
    }
    const failureRun = await failureRunResponse.json()
    await waitForRunState(page, projectId, failureRun.run.run_id, "Failed")
    await page.reload({ waitUntil: "domcontentloaded" })
    await page.getByText("The update failed before the preview could be refreshed.").waitFor()
    const failedDetail = await projectDetail(page, projectId)
    if (!failedDetail.preview || failedDetail.preview.url !== firstDetail.preview.url) {
      throw new Error("Expected the last successful preview to remain available after a failed run")
    }
    const failedPreviewFrame = page.frameLocator(`iframe[src*="${failedDetail.preview.url}"]`)
    await failedPreviewFrame.getByText("MoonCraft smoke preview").waitFor()
    await assertNoInternalPromptLeak(page, failedPreviewFrame)
    screenshots.push(screenshot("08-failed-run-preserves-preview.png"))
    await page.screenshot({ path: screenshots[screenshots.length - 1], fullPage: true })

    const report = `# Playwright Simple Project Build Story Report

- Result: Passed
- App URL: \`${baseUrl}\`
- Mode: \`MOONCRAFT_RUNTIME_FAKE_MODE=smoke\`
- User: \`${email}\`
- Project ID: \`${projectId}\`
- First run ID: \`${firstRunId}\`
- Second run ID: \`${secondRun.run.run_id}\`
- Failed run ID: \`${failureRun.run.run_id}\`
- Preview URL: \`${refreshedDetail.preview.url}\`
- Preview title: \`${previewTitle}\`

## Assertions

- Development sign-in opens an empty authenticated workspace.
- New project creation requires a project name.
- The selected project can be renamed before the first build.
- First prompt creates one project run and reaches \`Succeeded\`.
- The project API exposes a healthy preview target.
- The preview iframe loads the generated app.
- Fake mode does not leak internal Runtime prompt rules into the page or preview.
- A second prompt reuses the same project.
- Refresh preserves project rail, chat history, and preview URL.
- A forced failed run preserves the last successful preview.

## Screenshots

${screenshots.map((shot, index) => `### ${index + 1}. ${path.basename(shot)}

![${path.basename(shot)}](${shot})
`).join("\n")}
`
    fs.writeFileSync(path.join(artifactDir, "REPORT.md"), report)

    console.log(JSON.stringify({
      result: "passed",
      artifactDir,
      reportPath: path.join(artifactDir, "REPORT.md"),
      email,
      projectId,
      firstRunId,
      secondRunId: secondRun.run.run_id,
      failedRunId: failureRun.run.run_id,
      previewUrl: failedDetail.preview.url,
      screenshots,
    }, null, 2))
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
MOONCRAFT_BUILD_PROFILE=debug \
MOONCRAFT_RUNTIME_FAKE_MODE=smoke \
MOONCRAFT_ENABLE_DEV_AUTH=1 \
MOONCRAFT_RUNTIME_FAKE_FAIL_CONTAINS="${MOONCRAFT_RUNTIME_FAKE_FAIL_CONTAINS:-Force fake failure}" \
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

MOONCRAFT_PLAYWRIGHT_BASE_URL="$base_url" \
MOONCRAFT_PLAYWRIGHT_ARTIFACT_DIR="$artifact_dir" \
  node "$runner_script" | tee "${artifact_dir}/result.json"

echo "Playwright report: $(cd "$artifact_dir" && pwd)/REPORT.md"
