#!/usr/bin/env bash
set -euo pipefail

port="${1:-8094}"
base_url="http://127.0.0.1:${port}"
playwright_version="${MOONCRAFT_PLAYWRIGHT_VERSION:-1.56.1}"

if ! command -v npm >/dev/null 2>&1; then
  echo "npm is required for the Playwright smoke runner." >&2
  exit 1
fi

if ! command -v node >/dev/null 2>&1; then
  echo "node is required for the Playwright smoke runner." >&2
  exit 1
fi

if curl -fsS "${base_url}/api/health" >/dev/null 2>&1; then
  echo "Port ${port} is already serving a control plane. Stop it first." >&2
  exit 1
fi

tmpdir="$(mktemp -d)"
log_file="${tmpdir}/control-plane.log"
generated_script=".playwright-cli/full-smoke.generated.js"
runner_dir="${tmpdir}/playwright-runner"
runner_script="${runner_dir}/runner.js"
browser_profile="${tmpdir}/browser-profile"
server_pid=""

cleanup() {
  rm -f "$generated_script"
  if [[ -n "$server_pid" ]]; then
    kill "$server_pid" >/dev/null 2>&1 || true
    wait "$server_pid" >/dev/null 2>&1 || true
  fi
  rm -rf "$tmpdir"
}
trap cleanup EXIT

mkdir -p "$runner_dir" "$browser_profile"
(
  cd "$runner_dir"
  npm init -y >/dev/null
  npm install --silent --no-audit --no-fund "playwright@${playwright_version}" >/dev/null
  PLAYWRIGHT_BROWSERS_PATH="$runner_dir/browsers" npx playwright install chromium >/dev/null
)
cat >"$runner_script" <<'EOF'
const fs = require("node:fs")
const { chromium } = require("playwright")

const [mode, argument] = process.argv.slice(2)
const userDataDir = process.env.PLAYWRIGHT_USER_DATA_DIR

if (!userDataDir) {
  throw new Error("PLAYWRIGHT_USER_DATA_DIR is required")
}

async function withPage(fn) {
  const context = await chromium.launchPersistentContext(userDataDir, {
    headless: true,
  })
  const page = context.pages()[0] || await context.newPage()
  try {
    const result = await fn(page)
    if (result !== undefined) {
      console.log(JSON.stringify(result, null, 2))
    }
  } finally {
    await context.close()
  }
}

async function main() {
  if (mode === "open") {
    await withPage(async (page) => {
      await page.goto(argument, { waitUntil: "domcontentloaded" })
      return { opened: argument }
    })
    return
  }
  if (mode === "run-code") {
    const source = fs.readFileSync(argument, "utf8")
    const run = eval(`(${source})`)
    if (typeof run !== "function") {
      throw new Error("Generated Playwright smoke phase must evaluate to a function")
    }
    await withPage(run)
    return
  }
  throw new Error(`Unknown mode: ${mode}`)
}

main().catch((error) => {
  console.error(error)
  process.exit(1)
})
EOF

run_playwright() {
  PLAYWRIGHT_BROWSERS_PATH="$runner_dir/browsers" \
  PLAYWRIGHT_USER_DATA_DIR="$browser_profile" \
    node "$runner_script" "$@"
}

MOONCRAFT_PORT="$port" \
MOONCRAFT_PUBLIC_BASE_URL="$base_url" \
MOONCRAFT_BUILD_PROFILE=debug \
MOONCRAFT_CODEX_FAKE_MODE=smoke \
MOONCRAFT_CODEX_DOCKER_IMAGE= \
moon -C . run --target native services/control-plane \
  >"$log_file" 2>&1 &
server_pid=$!

for _ in {1..60}; do
  if curl -fsS "${base_url}/api/health" >/dev/null 2>&1; then
    break
  fi
  sleep 1
done

curl -fsS "${base_url}/api/health" | grep -q '"ok":true'
run_playwright open "$base_url" >/dev/null

mkdir -p "$(dirname "$generated_script")"
email="ui-$(date +%s)-$RANDOM@example.com"
password="password123"
changed_password="password456"
reset_password="password789"
outbox="data/control-plane/account-emails.log"

fail_with_log() {
  echo
  echo "Control plane log:" >&2
  sed -n '1,220p' "$log_file" >&2
  exit 1
}

run_playwright_phase() {
  local label="$1"
  cat >"$generated_script"
  local run_output
  if ! run_output="$(run_playwright run-code "$generated_script" 2>&1)"; then
    printf '%s\n' "$run_output"
    fail_with_log
  fi
  printf '%s\n' "$run_output"
  if printf '%s\n' "$run_output" | grep -q '^### Error'; then
    echo "Playwright phase failed: $label" >&2
    fail_with_log
  fi
}

extract_outbox_token() {
  local target_email="$1"
  local path_fragment="$2"
  { grep -A8 "to: $target_email" "$outbox" || true; } \
    | sed -n "s#.*$path_fragment?token=\([^[:space:]]*\).*#\1#p" \
    | tail -n1
}

run_playwright_phase "signup and resend verification" <<EOF
async (page) => {
  const baseUrl = "$base_url"
  const email = "$email"
  const password = "$password"
  page.setDefaultTimeout(15000)
  await page.goto(baseUrl, { waitUntil: "domcontentloaded" })
  await page.getByLabel("Email").fill(email)
  await page.getByLabel("Password").fill(password)
  await page.getByLabel("Display Name").fill("Playwright Operator")
  await page.getByRole("button", { name: "Create Account" }).click()
  await page.getByRole("button", { name: /Playwright Operator/ }).waitFor()
  await page.getByText("Verification pending").waitFor()
  await page.getByRole("button", { name: "Resend Verification" }).click()
  await page.getByText("Verification link has been queued.").waitFor()
  return { phase: "signup", email }
}
EOF

verify_token="$(extract_outbox_token "$email" "/auth/email/verify")"
if [[ -z "$verify_token" ]]; then
  echo "Failed to parse verification token for $email from $outbox" >&2
  fail_with_log
fi
run_playwright_phase "verify email page" <<EOF
async (page) => {
  await page.goto("$base_url/auth/email/verify?token=$verify_token", { waitUntil: "domcontentloaded" })
  await page.getByText("Email address verified.").waitFor()
  await page.getByRole("link", { name: "Back to app" }).click()
  await page.getByRole("button", { name: /Playwright Operator/ }).waitFor({ timeout: 5000 }).catch(async () => {
    await page.getByRole("button", { name: "Log In" }).first().click()
    await page.getByLabel("Email").fill("$email")
    await page.getByLabel("Password").fill("$password")
    await page.getByRole("button", { name: "Log In" }).last().click()
    await page.getByRole("button", { name: /Playwright Operator/ }).waitFor()
  })
  if (await page.getByText("Verified").count() === 0) {
    await page.getByRole("button", { name: "Account" }).click()
  }
  await page.getByText("Verified").waitFor()
  const verified = await page.evaluate(async () => {
    const response = await fetch("/api/session")
    if (!response.ok) return false
    const session = await response.json()
    return Boolean(session.user?.email_verified)
  })
  if (!verified) {
    throw new Error("Expected the signed-in user email to be verified")
  }
  return { phase: "verify-email", verified }
}
EOF

run_playwright_phase "change password and forgot password request" <<EOF
async (page) => {
  await page.goto("$base_url", { waitUntil: "domcontentloaded" })
  const email = "$email"
  const password = "$password"
  const changedPassword = "$changed_password"
  const openAccountMenu = async () => {
    if (await page.getByRole("button", { name: "Log Out" }).count() === 0) {
      await page.getByRole("button", { name: /Playwright Operator/ }).click()
    }
  }
  if (await page.getByRole("button", { name: "Change Password" }).count() === 0) {
    await page.getByRole("button", { name: /Playwright Operator/ }).click()
  }
  await page.getByRole("button", { name: "Change Password" }).click()
  await page.getByPlaceholder("Current password").fill(password)
  await page.getByPlaceholder("New password").fill(changedPassword)
  await page.getByRole("button", { name: "Save Password" }).click()
  await page.getByText("Password changed.").waitFor()
  await openAccountMenu()
  await page.getByRole("button", { name: "Log Out" }).click()
  await page.getByLabel("Email").waitFor()
  await page.getByLabel("Email").fill(email)
  await page.getByLabel("Password").fill("wrong-password")
  await page.getByRole("button", { name: "Log In" }).last().click()
  await page.getByText("The email or password is incorrect.").waitFor()
  await page.getByLabel("Password").fill(changedPassword)
  await page.getByRole("button", { name: "Log In" }).last().click()
  await page.getByRole("button", { name: /Playwright Operator/ }).waitFor()
  await openAccountMenu()
  await page.getByRole("button", { name: "Log Out" }).click()
  await page.getByLabel("Email").waitFor()
  await page.getByRole("button", { name: "Forgot password?" }).click()
  await page.getByText("Reset your password").waitFor()
  await page.getByLabel("Email").fill(email)
  await page.getByRole("button", { name: "Send Reset Link" }).click()
  await page.getByText("If that email is registered, a reset link has been queued.").waitFor()
  return { phase: "change-password-and-request-reset" }
}
EOF

reset_token="$(extract_outbox_token "$email" "/auth/password/reset")"
if [[ -z "$reset_token" ]]; then
  echo "Failed to parse password reset token for $email from $outbox" >&2
  fail_with_log
fi
run_playwright_phase "reset password page and project lifecycle" <<EOF
async (page) => {
  await page.goto("$base_url/auth/password/reset?token=$reset_token", { waitUntil: "domcontentloaded" })
  const baseUrl = "$base_url"
  const email = "$email"
  const password = "$reset_password"
  const hasVisibleThemeButton = async () => {
    return await page.evaluate(() => {
      return [...document.querySelectorAll("button")].some((candidate) => {
        const rect = candidate.getBoundingClientRect()
        const style = window.getComputedStyle(candidate)
        return candidate.textContent?.trim().startsWith("Theme: ") &&
          rect.width > 0 &&
          rect.height > 0 &&
          style.visibility !== "hidden" &&
          style.display !== "none"
      })
    })
  }
  const openAccountMenu = async () => {
    if (await hasVisibleThemeButton()) {
      return
    }
    for (let attempt = 0; attempt < 2; attempt += 1) {
      await page.getByRole("button", { name: /Playwright Operator/ }).click()
      if (await hasVisibleThemeButton()) {
        return
      }
      await page.waitForTimeout(150)
    }
    throw new Error("Expected the account menu to show the theme button")
  }
  const clickVisibleButtonByText = async (text) => {
    const clicked = await page.evaluate((label) => {
      const button = [...document.querySelectorAll("button")].find((candidate) => {
        const rect = candidate.getBoundingClientRect()
        const style = window.getComputedStyle(candidate)
        return candidate.textContent?.trim() === label &&
          rect.width > 0 &&
          rect.height > 0 &&
          style.visibility !== "hidden" &&
          style.display !== "none" &&
          !candidate.disabled
      })
      if (!button) return false
      button.click()
      return true
    }, text)
    if (!clicked) {
      throw new Error(\`Expected visible enabled button: \${text}\`)
    }
    await page.waitForTimeout(100)
  }
  await page.getByPlaceholder("New password").fill(password)
  await page.getByRole("button", { name: "Update Password" }).click()
  await page.getByText("Password updated. Sign in with the new password.").waitFor()
  await page.evaluate(async ([email, password]) => {
    const response = await fetch("/api/auth/login", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ email, password }),
    })
    if (!response.ok) {
      throw new Error(\`Reset password login failed with HTTP \${response.status}\`)
    }
  }, [email, password])
  await page.goto(baseUrl, { waitUntil: "domcontentloaded" })
  await page.getByRole("button", { name: /Playwright Operator/ }).waitFor()
  await openAccountMenu()
  if (await page.getByText("Syncs with preview theme").count() > 0) {
    throw new Error("Appearance helper copy should not be visible")
  }
  await page.getByRole("button", { name: "+ New Project" }).click()
  await page.getByPlaceholder("Describe the change you want.").fill(
    "Build a deterministic Playwright smoke app.",
  )
  const runResponsePromise = page.waitForResponse((response) => {
    return response.url().includes("/api/projects/") &&
      response.url().includes("/runs") &&
      response.request().method() === "POST"
  })
  await page.getByRole("button", { name: "Send Request" }).click()
  const runResponse = await runResponsePromise
  const createdRun = await runResponse.json()
  const projectId = createdRun.run.project_id
  const runId = createdRun.run.run_id

  let state = null
  for (let attempt = 0; attempt < 120; attempt += 1) {
    state = await page.evaluate(async ([projectId, runId]) => {
      const runResponse = await fetch(\`/api/projects/\${projectId}/runs/\${runId}\`)
      if (!runResponse.ok) return null
      const run = await runResponse.json()
      return run.state
    }, [projectId, runId])
    if (state && state !== "Running") break
    await page.waitForTimeout(1000)
  }
  if (state !== "Succeeded") {
    throw new Error(\`Expected deterministic worker success in smoke mode, got \${state}\`)
  }
  const healthy = await page.evaluate(async () => {
    const response = await fetch("/api/health")
    return response.ok
  })
  if (!healthy) {
    throw new Error("Control plane stopped responding after chat submit")
  }
  await page.getByRole("button", { name: "Delete" }).click()
  await page.getByRole("button", { name: "Confirm Delete" }).click()
  await page.getByText("Create a project to begin.").waitFor()
  await openAccountMenu()
  await clickVisibleButtonByText("Log Out")
  await page.getByLabel("Email").waitFor()
  await page.getByLabel("Email").fill(email)
  await page.getByLabel("Password").fill(password)
  await page.getByRole("button", { name: "Log In" }).last().click()
  await page.getByRole("button", { name: /Playwright Operator/ }).waitFor()
  return {
    email,
    emailVerifiedInBrowser: true,
    changedPasswordLogin: true,
    resetPasswordLogin: true,
    runState: state,
    healthAfterRunSubmit: healthy,
  }
}
EOF
