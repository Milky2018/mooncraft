#!/usr/bin/env node

const targetUrl = process.argv[2];

if (!targetUrl) {
  console.error("Usage: preview_audit.mjs <url>");
  process.exit(2);
}

let playwright;
try {
  playwright = await import("playwright");
} catch {
  try {
    playwright = await import("playwright-core");
  } catch (error) {
    console.error(`Playwright is not available: ${error.message}`);
    process.exit(2);
  }
}

const timeoutMs = Number(process.env.MOONCRAFT_PREVIEW_AUDIT_TIMEOUT_MS || 12000);
const executablePath = process.env.MOONCRAFT_PREVIEW_AUDIT_CHROMIUM || undefined;
const failures = [];

const browser = await playwright.chromium.launch({
  headless: true,
  executablePath,
  args: ["--no-sandbox", "--disable-dev-shm-usage"],
});

try {
  const page = await browser.newPage({
    viewport: { width: 1440, height: 960 },
  });

  page.on("pageerror", (error) => {
    failures.push(`pageerror: ${error.message}`);
  });

  page.on("console", (message) => {
    if (message.type() !== "error") return;
    const text = message.text();
    if (/favicon/i.test(text) && /404|not found/i.test(text)) return;
    if (/^Failed to load resource:/i.test(text)) return;
    failures.push(`console.error: ${text}`);
  });

  page.on("response", (response) => {
    const status = response.status();
    if (status < 400) return;
    const url = response.url();
    if (/\/favicon\.(ico|png|svg)$/i.test(url)) return;
    failures.push(`http ${status}: ${url}`);
  });

  await page.goto(targetUrl, {
    waitUntil: "networkidle",
    timeout: timeoutMs,
  });
  await page.waitForTimeout(750);

  if (failures.length > 0) {
    console.error(`Preview audit failed for ${targetUrl}`);
    for (const failure of failures.slice(0, 20)) {
      console.error(`- ${failure}`);
    }
    if (failures.length > 20) {
      console.error(`- ... ${failures.length - 20} more failures omitted`);
    }
    process.exit(1);
  }

  console.log(`Preview audit passed for ${targetUrl}`);
} finally {
  await browser.close();
}
