#!/usr/bin/env node

const targetUrl = process.argv[2] || "";
const timeoutSeconds = Number(process.env.MOONCRAFT_PREVIEW_AUDIT_TIMEOUT_SECONDS || "12");

function fail(message, body = "") {
  console.error(message);
  if (body) {
    console.error(body.slice(0, 1200));
  }
  process.exit(1);
}

function requireHttpUrl(value) {
  try {
    const url = new URL(value);
    if (url.protocol !== "http:" && url.protocol !== "https:") {
      return null;
    }
    return url;
  } catch {
    return null;
  }
}

function skippableUrl(ref) {
  const value = ref.trim().toLowerCase();
  return (
    value === "" ||
    value.startsWith("#") ||
    value.startsWith("mailto:") ||
    value.startsWith("tel:") ||
    value.startsWith("data:") ||
    value.startsWith("blob:") ||
    value.startsWith("javascript:") ||
    value.includes("favicon")
  );
}

function splitSrcset(value) {
  const refs = [];
  for (const item of value.split(",")) {
    const ref = item.trim().split(/\s+/, 1)[0];
    if (ref) refs.push(ref);
  }
  return refs;
}

function readTag(html, start) {
  let quote = "";
  for (let index = start; index < html.length; index += 1) {
    const ch = html[index];
    if (quote) {
      if (ch === quote) quote = "";
    } else if (ch === '"' || ch === "'") {
      quote = ch;
    } else if (ch === ">") {
      return { text: html.slice(start + 1, index), end: index + 1 };
    }
  }
  return { text: html.slice(start + 1), end: html.length };
}

function skipSpaces(text, index) {
  while (index < text.length && /\s/.test(text[index])) index += 1;
  return index;
}

function readName(text, index) {
  const start = index;
  while (
    index < text.length &&
    !/\s/.test(text[index]) &&
    text[index] !== "=" &&
    text[index] !== "/" &&
    text[index] !== ">"
  ) {
    index += 1;
  }
  return { value: text.slice(start, index).toLowerCase(), index };
}

function readAttributeValue(text, index) {
  index = skipSpaces(text, index);
  if (index >= text.length) return { value: "", index };
  const quote = text[index] === '"' || text[index] === "'" ? text[index] : "";
  if (quote) {
    const start = index + 1;
    index = start;
    while (index < text.length && text[index] !== quote) index += 1;
    return { value: text.slice(start, index), index: Math.min(index + 1, text.length) };
  }
  const start = index;
  while (index < text.length && !/\s/.test(text[index]) && text[index] !== ">") {
    index += 1;
  }
  return { value: text.slice(start, index), index };
}

function collectAssetRefs(html) {
  const refs = [];
  let index = 0;
  while (index < html.length) {
    const tagStart = html.indexOf("<", index);
    if (tagStart < 0) break;
    const tag = readTag(html, tagStart);
    index = tag.end;
    const text = tag.text.trim();
    if (!text || text.startsWith("!") || text.startsWith("?") || text.startsWith("/")) {
      continue;
    }
    let cursor = 0;
    const tagName = readName(text, cursor);
    cursor = tagName.index;
    while (cursor < text.length) {
      cursor = skipSpaces(text, cursor);
      if (cursor >= text.length || text[cursor] === "/") break;
      const attr = readName(text, cursor);
      cursor = attr.index;
      cursor = skipSpaces(text, cursor);
      if (text[cursor] !== "=") continue;
      const value = readAttributeValue(text, cursor + 1);
      cursor = value.index;
      if (attr.value === "src" || attr.value === "href" || attr.value === "action") {
        refs.push(value.value);
      } else if (attr.value === "srcset") {
        refs.push(...splitSrcset(value.value));
      }
    }
  }
  return refs;
}

async function fetchText(url, label) {
  const controller = new AbortController();
  const timeout = setTimeout(
    () => controller.abort(),
    Math.max(1, timeoutSeconds) * 1000,
  );
  try {
    const response = await fetch(url, {
      redirect: "follow",
      signal: controller.signal,
    });
    const body = await response.text();
    return { status: response.status, body };
  } catch {
    fail(`Preview audit failed for ${targetUrl}: ${label} request failed.`);
  } finally {
    clearTimeout(timeout);
  }
}

async function main() {
  const target = requireHttpUrl(targetUrl);
  if (!target) {
    fail(`Preview audit failed for ${targetUrl}: expected an absolute http(s) URL.`);
  }

  const page = await fetchText(target, "page");
  if (page.status < 200 || page.status >= 400) {
    fail(`Preview audit failed for ${targetUrl}: HTTP ${page.status}.`, page.body);
  }
  const byteCount = Buffer.byteLength(page.body);
  if (byteCount <= 0) {
    fail(`Preview audit failed for ${targetUrl}: response body is empty.`);
  }
  const errorNeedles = [
    "No preview is available",
    "preview process is not reachable",
    "preview could not be restarted",
    "Bad Gateway",
  ];
  if (errorNeedles.some((needle) => page.body.includes(needle))) {
    fail(
      `Preview audit failed for ${targetUrl}: response contains a preview error page.`,
      page.body,
    );
  }

  const checked = new Set();
  for (const ref of collectAssetRefs(page.body)) {
    if (skippableUrl(ref)) continue;
    const asset = new URL(ref, target);
    if (asset.origin !== target.origin) continue;
    const href = asset.href;
    if (checked.has(href)) continue;
    checked.add(href);
    const result = await fetchText(asset, `asset ${href}`);
    if (result.status < 200 || result.status >= 400) {
      fail(
        `Preview audit failed for ${targetUrl}: asset ${href} returned HTTP ${result.status}.`,
      );
    }
  }

  console.log(
    `Preview audit passed for ${targetUrl}: HTTP ${page.status}, ${byteCount} bytes, ${checked.size} same-origin browser assets reachable.`,
  );
}

await main();
