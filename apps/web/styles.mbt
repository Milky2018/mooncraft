///|
fn theme_variables(theme_mode : ThemeMode) -> Array[String] {
  match theme_mode {
    System => theme_variables(Light)
    Dark =>
      [
        "--font-family-ui: \"IBM Plex Mono\", \"SFMono-Regular\", Menlo, monospace",
        "--font-title: 24px", "--font-mid: 14px", "--radius-panel: 6px", "--radius-control: 4px",
        "--page-bg: #101113", "--page-bg-alt: #111214", "--sidebar-bg: rgba(23, 24, 26, 0.92)",
        "--surface-1: #17181b", "--surface-2: #1c1d20", "--surface-3: #222328", "--surface-raised: #25262b",
        "--preview-bg: #111214", "--border-soft: rgba(255, 255, 255, 0.09)", "--border-strong: rgba(47, 132, 255, 0.72)",
        "--text-1: #f4f4f5", "--text-2: #c7c7cb", "--text-3: #8c8e95", "--accent: #0b8f7f",
        "--accent-strong: #007f72", "--accent-soft: rgba(0, 127, 114, 0.18)", "--action: #2f84ff",
        "--action-strong: #136dff", "--action-soft: rgba(47, 132, 255, 0.20)", "--on-action: #ffffff",
        "--danger: #ff7a7a", "--danger-soft: rgba(255, 122, 122, 0.12)", "--warning: #ffcf66",
        "--warning-soft: rgba(255, 207, 102, 0.12)", "--shadow: 0 10px 24px rgba(0, 0, 0, 0.22), 0 0 0 1px rgba(255, 255, 255, 0.02)",
        "--badge-idle-bg: rgba(115, 137, 160, 0.14)", "--badge-idle-fg: #a7bad0",
        "--badge-running-bg: rgba(45, 125, 255, 0.16)", "--badge-running-fg: #91c0ff",
        "--badge-success-bg: rgba(18, 216, 156, 0.14)", "--badge-success-fg: #7af0c6",
        "--badge-failed-bg: rgba(255, 122, 122, 0.14)", "--badge-failed-fg: #ffb0b0",
        "color-scheme: dark",
      ]
    Light =>
      [
        "--font-family-ui: \"IBM Plex Mono\", \"SFMono-Regular\", Menlo, monospace",
        "--font-title: 24px", "--font-mid: 14px", "--radius-panel: 6px", "--radius-control: 4px",
        "--page-bg: #eef2f7", "--page-bg-alt: #f8fafc", "--sidebar-bg: rgba(248, 250, 252, 0.88)",
        "--surface-1: rgba(255, 255, 255, 0.90)", "--surface-2: #ffffff", "--surface-3: #f1f5f9",
        "--surface-raised: #ffffff", "--preview-bg: #f8fafc", "--border-soft: rgba(15, 23, 42, 0.10)",
        "--border-strong: rgba(15, 118, 110, 0.36)", "--text-1: #0f172a", "--text-2: #475569",
        "--text-3: #94a3b8", "--accent: #0f766e", "--accent-strong: #115e59", "--accent-soft: rgba(15, 118, 110, 0.10)",
        "--action: #0f766e", "--action-strong: #115e59", "--action-soft: rgba(15, 118, 110, 0.14)",
        "--on-action: #ffffff", "--danger: #b94747", "--danger-soft: rgba(185, 71, 71, 0.10)",
        "--warning: #9b6b10", "--warning-soft: rgba(155, 107, 16, 0.12)", "--shadow: 0 18px 48px rgba(15, 23, 42, 0.08), 0 1px 0 rgba(255, 255, 255, 0.78) inset",
        "--badge-idle-bg: rgba(92, 110, 130, 0.12)", "--badge-idle-fg: #526173",
        "--badge-running-bg: rgba(31, 115, 232, 0.12)", "--badge-running-fg: #175ab9",
        "--badge-success-bg: rgba(0, 110, 99, 0.12)", "--badge-success-fg: #075f56",
        "--badge-failed-bg: rgba(185, 71, 71, 0.12)", "--badge-failed-fg: #9d3838",
        "color-scheme: light",
      ]
  }
}

///|
fn app_root_style(theme_mode : ThemeMode) -> Array[String] {
  theme_variables(theme_mode) +
  [
    "min-height: 100vh", "padding: 0", "background-color: var(--page-bg)", "background-image: radial-gradient(circle at 18% 0%, rgba(15, 118, 110, 0.12), transparent 30%), radial-gradient(circle at 86% 8%, rgba(37, 99, 235, 0.08), transparent 28%), linear-gradient(135deg, var(--page-bg-alt), var(--page-bg))",
    "background-size: auto", "font-family: var(--font-family-ui)",
  ] +
  normal_text_style()
}

///|
fn app_stack_style() -> Array[String] {
  [
    "min-height: calc(100vh - 12px)", "display: flex", "flex-direction: column",
    "gap: 4px", "padding: 8px",
  ]
}

///|
fn panel_style() -> Array[String] {
  [
    "background: var(--surface-1)", "border: 1px solid var(--border-soft)", "border-radius: var(--radius-panel)",
    "box-shadow: var(--shadow)", "overflow: hidden", "backdrop-filter: blur(8px)",
  ]
}

///|
fn inset_panel_style() -> Array[String] {
  ["background: var(--surface-2)", "border-radius: var(--radius-control)"]
}

///|
fn section_label_style() -> Array[String] {
  normal_text_style()
}

///|
fn title_text_style() -> Array[String] {
  [
    "font-size: var(--font-title)", "font-weight: 700", "line-height: 1.12", "letter-spacing: -0.02em",
    "color: var(--text-1)",
  ]
}

///|
fn normal_text_style() -> Array[String] {
  [
    "font-size: var(--font-mid)", "font-weight: 500", "line-height: 1.55", "letter-spacing: 0",
    "color: var(--text-2)",
  ]
}

///|
fn value_text_style() -> Array[String] {
  [
    "font-size: var(--font-mid)", "font-weight: 600", "line-height: 1.45", "letter-spacing: 0",
    "color: var(--text-1)",
  ]
}

///|
fn button_style(
  background : String,
  foreground : String,
  enabled : Bool,
) -> Array[String] {
  let cursor = if enabled { "pointer" } else { "not-allowed" }
  let opacity = if enabled { "1" } else { "0.45" }
  value_text_style() +
  [
    "display: inline-flex",
    "align-items: center",
    "justify-content: center",
    "gap: 4px",
    "padding: 8px 12px",
    "border: 1px solid transparent",
    "border-radius: var(--radius-control)",
    "background: " + background,
    "color: " + foreground,
    "cursor: " + cursor,
    "opacity: " + opacity,
    "transition: opacity 120ms ease, transform 120ms ease, box-shadow 120ms ease",
  ]
}

///|
fn primary_button_style(enabled : Bool) -> Array[String] {
  button_style(
    "linear-gradient(135deg, var(--action-strong), var(--action))", "var(--on-action)",
    enabled,
  ) +
  ["box-shadow: none"]
}

///|
fn secondary_button_style(enabled : Bool) -> Array[String] {
  button_style("var(--surface-3)", "var(--text-1)", enabled)
}

///|
fn input_style(disabled : Bool) -> Array[String] {
  let border_color = if disabled {
    "var(--border-soft)"
  } else {
    "var(--border-strong)"
  }
  let background = if disabled {
    "var(--surface-3)"
  } else {
    "var(--surface-2)"
  }
  value_text_style() +
  [
    "width: 100%",
    "padding: 8px 12px",
    "border: 1px solid " + border_color,
    "border-radius: var(--radius-control)",
    "background: " + background,
    "outline: none",
    "box-shadow: inset 0 1px 0 rgba(255, 255, 255, 0.02)",
  ]
}
