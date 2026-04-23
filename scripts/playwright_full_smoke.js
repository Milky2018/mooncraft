async (page) => {
  const baseUrl = page.url().split("/").slice(0, 3).join("/")
  const password = "password123"
  const email = `ui-${Date.now()}-${Math.floor(Math.random() * 10000)}@example.com`

  page.setDefaultTimeout(15000)
  await page.goto(baseUrl, { waitUntil: "domcontentloaded" })

  await page.getByLabel("Email").fill(email)
  await page.getByLabel("Password").fill(password)
  await page.getByLabel("Display Name").fill("Playwright Operator")
  await page.getByRole("button", { name: "Create Account" }).click()

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
      const runResponse = await fetch(`/api/projects/${projectId}/runs/${runId}`)
      if (!runResponse.ok) {
        return null
      }
      const run = await runResponse.json()
      return run.state
    }, [projectId, runId])
    if (state && state !== "Running") {
      break
    }
    await page.waitForTimeout(1000)
  }
  if (state !== "Failed") {
    throw new Error(`Expected fast worker failure in smoke mode, got ${state}`)
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
    runState: state,
    healthAfterRunSubmit: healthy,
  }
}
