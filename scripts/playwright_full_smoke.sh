#!/usr/bin/env bash
set -euo pipefail

port="${1:-8094}"
base_url="http://127.0.0.1:${port}"
pwcli="${CODEX_HOME:-$HOME/.codex}/skills/playwright/scripts/playwright_cli.sh"

if ! command -v npx >/dev/null 2>&1; then
  echo "npx is required for the bundled Playwright CLI wrapper." >&2
  exit 1
fi

if [[ ! -x "$pwcli" ]]; then
  echo "Playwright CLI wrapper not found at $pwcli" >&2
  exit 1
fi

if curl -fsS "${base_url}/api/health" >/dev/null 2>&1; then
  echo "Port ${port} is already serving a control plane. Stop it first." >&2
  exit 1
fi

tmpdir="$(mktemp -d)"
log_file="${tmpdir}/control-plane.log"
generated_script=".playwright-cli/full-smoke.generated.js"
server_pid=""

cleanup() {
  "$pwcli" close >/dev/null 2>&1 || true
  rm -f "$generated_script"
  if [[ -n "$server_pid" ]]; then
    kill "$server_pid" >/dev/null 2>&1 || true
    wait "$server_pid" >/dev/null 2>&1 || true
  fi
  rm -rf "$tmpdir"
}
trap cleanup EXIT

MOONBITCLOUD_PORT="$port" \
MOONBITCLOUD_PUBLIC_BASE_URL="$base_url" \
MOONBITCLOUD_BUILD_PROFILE=debug \
MOONBITCLOUD_CODEX_DOCKER_IMAGE= \
moon run --manifest-path moon.work services/control-plane --target native \
  >"$log_file" 2>&1 &
server_pid=$!

for _ in {1..30}; do
  if curl -fsS "${base_url}/api/health" >/dev/null 2>&1; then
    break
  fi
  sleep 1
done

curl -fsS "${base_url}/api/health" | grep -q '"ok":true'
"$pwcli" open "$base_url" >/dev/null

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
  if ! run_output="$("$pwcli" run-code --filename "$generated_script" --raw 2>&1)"; then
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
  await page.getByText("Signed in").waitFor()
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
"$pwcli" open "$base_url/auth/email/verify?token=$verify_token" >/dev/null
run_playwright_phase "verify email page" <<EOF
async (page) => {
  await page.getByText("Email address verified.").waitFor()
  await page.getByRole("link", { name: "Back to app" }).click()
  await page.getByText("Signed in").waitFor({ timeout: 5000 }).catch(async () => {
    await page.getByRole("button", { name: "Log In" }).first().click()
    await page.getByLabel("Email").fill("$email")
    await page.getByLabel("Password").fill("$password")
    await page.getByRole("button", { name: "Log In" }).last().click()
    await page.getByText("Signed in").waitFor()
  })
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
  const email = "$email"
  const password = "$password"
  const changedPassword = "$changed_password"
  await page.getByPlaceholder("Current password").fill(password)
  await page.getByPlaceholder("New password").fill(changedPassword)
  await page.getByRole("button", { name: "Change Password" }).click()
  await page.getByText("Password changed.").waitFor()
  await page.getByRole("button", { name: "Log Out" }).click()
  await page.getByLabel("Email").waitFor()
  await page.getByLabel("Email").fill(email)
  await page.getByLabel("Password").fill("wrong-password")
  await page.getByRole("button", { name: "Log In" }).last().click()
  await page.getByText("The email or password is incorrect.").waitFor()
  await page.getByLabel("Password").fill(changedPassword)
  await page.getByRole("button", { name: "Log In" }).last().click()
  await page.getByText("Signed in").waitFor()
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
"$pwcli" open "$base_url/auth/password/reset?token=$reset_token" >/dev/null
run_playwright_phase "reset password page and project lifecycle" <<EOF
async (page) => {
  const baseUrl = "$base_url"
  const email = "$email"
  const password = "$reset_password"
  await page.getByPlaceholder("New password").fill(password)
  await page.getByRole("button", { name: "Update Password" }).click()
  await page.getByText("Password updated. Sign in with the new password.").waitFor()
  await page.getByRole("link", { name: "Back to sign in" }).click()
  await page.getByLabel("Email").waitFor()
  await page.getByRole("button", { name: "Log In" }).click()
  await page.getByLabel("Email").fill(email)
  await page.getByLabel("Password").fill(password)
  await page.getByRole("button", { name: "Log In" }).last().click()
  await page.getByText("Signed in").waitFor()
  if (await page.getByText("Theme: Light").count() === 0) {
    await page.getByRole("button", { name: "Light Mode" }).click()
  }
  await page.getByText("Theme: Light").waitFor()
  await page.reload({ waitUntil: "domcontentloaded" })
  await page.getByText("Theme: Light").waitFor()
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
  for (let attempt = 0; attempt < 30; attempt += 1) {
    state = await page.evaluate(async ([projectId, runId]) => {
      const runResponse = await fetch(\`/api/projects/\${projectId}/runs/\${runId}\`)
      if (!runResponse.ok) return null
      const run = await runResponse.json()
      return run.state
    }, [projectId, runId])
    if (state && state !== "Running") break
    await page.waitForTimeout(1000)
  }
  if (state !== "Failed") {
    throw new Error(\`Expected fast worker failure in smoke mode, got \${state}\`)
  }
  const healthy = await page.evaluate(async () => {
    const response = await fetch("/api/health")
    return response.ok
  })
  if (!healthy) {
    throw new Error("Control plane stopped responding after chat submit")
  }
  await page.getByRole("button", { name: "Delete" }).click()
  await page.getByText("Create a project to begin.").waitFor()
  await page.getByRole("button", { name: "Log Out" }).click()
  await page.getByLabel("Email").waitFor()
  await page.getByLabel("Email").fill(email)
  await page.getByLabel("Password").fill(password)
  await page.getByRole("button", { name: "Log In" }).last().click()
  await page.getByText("Signed in").waitFor()
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
