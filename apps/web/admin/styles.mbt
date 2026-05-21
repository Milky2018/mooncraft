///|
fn theme_vars() -> Array[String] {
  [
    "--background: oklch(0.98 0.003 265)", "--foreground: oklch(0.185 0.01 270)",
    "--accent: oklch(0.62 0.13 293)", "--success: oklch(0.55 0.17 145)", "--destructive: oklch(0.58 0.24 28)",
    "--foreground-3: color-mix(in oklch, var(--foreground) 3%, var(--background))",
    "--foreground-5: color-mix(in oklch, var(--foreground) 5%, var(--background))",
    "--foreground-10: color-mix(in oklch, var(--foreground) 10%, var(--background))",
    "--foreground-50: color-mix(in oklch, var(--foreground) 50%, var(--background))",
    "--foreground-70: color-mix(in oklch, var(--foreground) 70%, var(--background))",
    "--border: oklch(from var(--foreground) l c h / 0.09)", "--text-1: var(--foreground)",
    "--text-2: var(--foreground-70)", "--text-3: var(--foreground-50)", "--radius-panel: 10px",
    "--radius-control: 6px", "--shadow: rgba(38, 36, 42, 0.08) 0 0 0 1px, rgba(0, 0, 0, 0.06) 0 2px 8px",
    "color-scheme: light",
  ]
}

///|
fn root_style() -> Array[String] {
  theme_vars() +
  [
    "min-height: 100vh", "margin: 0", "background: var(--background)", "font-family: system-ui, -apple-system, BlinkMacSystemFont, \"Segoe UI\", Roboto, \"Helvetica Neue\", Arial, sans-serif",
    "color: var(--text-1)", "font-size: 13px", "line-height: 1.5",
  ]
}

///|
fn title_style() -> Array[String] {
  [
    "font-size: 14px", "font-weight: 650", "line-height: 1.25", "letter-spacing: 0",
    "color: var(--text-1)",
  ]
}

///|
fn normal_style() -> Array[String] {
  [
    "font-size: 13px", "font-weight: 400", "line-height: 1.5", "letter-spacing: 0",
    "color: var(--text-2)",
  ]
}

///|
fn value_style() -> Array[String] {
  [
    "font-size: 13px", "font-weight: 550", "line-height: 1.45", "letter-spacing: 0",
    "color: var(--text-1)",
  ]
}

///|
fn shell_style() -> Array[String] {
  [
    "height: 100vh", "display: grid", "grid-template-columns: 240px minmax(0, 1fr)",
    "overflow: hidden",
  ]
}

///|
fn sidebar_style() -> Array[String] {
  [
    "padding: 12px", "border-right: 1px solid var(--border)", "display: flex", "flex-direction: column",
    "gap: 12px", "background: var(--foreground-3)",
  ]
}

///|
fn content_style() -> Array[String] {
  [
    "min-width: 0", "min-height: 0", "overflow: auto", "padding: 12px", "display: flex",
    "flex-direction: column", "gap: 8px",
  ]
}

///|
fn card_style() -> Array[String] {
  [
    "background: var(--background)", "border: 1px solid var(--border)", "border-radius: var(--radius-panel)",
    "box-shadow: var(--shadow)", "overflow: hidden",
  ]
}

///|
fn table_style() -> Array[String] {
  ["width: 100%", "border-collapse: collapse"]
}

///|
fn th_style() -> Array[String] {
  normal_style() +
  [
    "padding: 9px 10px", "text-align: left", "border-bottom: 1px solid var(--border)",
    "background: var(--foreground-3)",
  ]
}

///|
fn td_style() -> Array[String] {
  value_style() +
  [
    "padding: 9px 10px", "border-bottom: 1px solid var(--border)", "vertical-align: middle",
  ]
}

///|
fn numeric_td_style() -> Array[String] {
  td_style() + ["text-align: right", "font-variant-numeric: tabular-nums"]
}

///|
fn button_style(enabled : Bool) -> Array[String] {
  let cursor = if enabled { "pointer" } else { "not-allowed" }
  let opacity = if enabled { "1" } else { "0.45" }
  value_style() +
  [
    "border: 0",
    "border-radius: var(--radius-control)",
    "background: var(--foreground-5)",
    "color: var(--text-1)",
    "padding: 6px 9px",
    "display: inline-flex",
    "align-items: center",
    "justify-content: center",
    "gap: 6px",
    "cursor: " + cursor,
    "opacity: " + opacity,
  ]
}

///|
fn icon_button_style(enabled : Bool) -> Array[String] {
  button_style(enabled) + ["width: 28px", "height: 28px", "padding: 0"]
}

///|
fn danger_button_style(enabled : Bool) -> Array[String] {
  button_style(enabled) +
  [
    "background: oklch(from var(--destructive) l c h / 0.10)", "color: var(--destructive)",
  ]
}

///|
fn input_style() -> Array[String] {
  value_style() +
  [
    "width: 100%", "padding: 7px 8px", "border: 1px solid var(--border)", "border-radius: var(--radius-control)",
    "background: var(--background)", "outline: none",
  ]
}

///|
fn badge_style(kind : String) -> Array[String] {
  let (background, color) = match kind {
    "success" => ("oklch(from var(--success) l c h / 0.12)", "var(--success)")
    "danger" =>
      ("oklch(from var(--destructive) l c h / 0.10)", "var(--destructive)")
    _ => ("var(--foreground-5)", "var(--text-3)")
  }
  normal_style() +
  [
    "display: inline-flex",
    "align-items: center",
    "padding: 2px 6px",
    "border-radius: var(--radius-control)",
    "background: " + background,
    "color: " + color,
    "font-weight: 550",
  ]
}
