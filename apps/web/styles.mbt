///|
fn mono_style() -> Array[String] {
  ["font-family: \"IBM Plex Mono\", \"SFMono-Regular\", Menlo, monospace"]
}

///|
fn theme_variables(theme_mode : ThemeMode) -> Array[String] {
  match theme_mode {
    System => theme_variables(Dark)
    Dark =>
      [
        "--page-bg: #101113", "--page-bg-alt: #111214", "--sidebar-bg: #17181a",
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
        "--page-bg: #f4f6f8", "--page-bg-alt: #ffffff", "--sidebar-bg: #eef1f5",
        "--surface-1: #ffffff", "--surface-2: #f6f8fb", "--surface-3: #edf1f5", "--surface-raised: #ffffff",
        "--preview-bg: #f7f9fc", "--border-soft: rgba(25, 35, 48, 0.14)", "--border-strong: rgba(47, 132, 255, 0.54)",
        "--text-1: #121821", "--text-2: #3f4b5a", "--text-3: #707b8a", "--accent: #087b6d",
        "--accent-strong: #006e63", "--accent-soft: rgba(0, 110, 99, 0.12)", "--action: #1f73e8",
        "--action-strong: #155fd0", "--action-soft: rgba(31, 115, 232, 0.14)", "--on-action: #ffffff",
        "--danger: #b94747", "--danger-soft: rgba(185, 71, 71, 0.10)", "--warning: #9b6b10",
        "--warning-soft: rgba(155, 107, 16, 0.12)", "--shadow: 0 10px 24px rgba(24, 36, 52, 0.10), 0 0 0 1px rgba(25, 35, 48, 0.03)",
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
    "min-height: 100vh", "padding: 0", "background-color: var(--page-bg)", "background-image: linear-gradient(180deg, var(--page-bg-alt), var(--page-bg))",
    "background-size: auto", "color: var(--text-1)", "font-family: \"IBM Plex Sans\", \"Avenir Next\", \"Segoe UI\", sans-serif",
  ]
}

///|
fn app_stack_style() -> Array[String] {
  [
    "min-height: calc(100vh - 24px)", "display: flex", "flex-direction: column",
    "gap: 10px", "padding: 12px",
  ]
}

///|
fn panel_style() -> Array[String] {
  [
    "background: var(--surface-1)", "border: 1px solid var(--border-soft)", "border-radius: 8px",
    "box-shadow: var(--shadow)", "overflow: hidden", "backdrop-filter: blur(14px)",
  ]
}

///|
fn inset_panel_style() -> Array[String] {
  [
    "background: var(--surface-2)", "border: 1px solid var(--border-soft)", "border-radius: 6px",
  ]
}

///|
fn section_label_style() -> Array[String] {
  mono_style() +
  [
    "font-size: 12px", "letter-spacing: 0.08em", "text-transform: uppercase", "color: var(--text-3)",
    "font-weight: 700",
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
  [
    "display: inline-flex",
    "align-items: center",
    "justify-content: center",
    "gap: 10px",
    "padding: 10px 14px",
    "border: 1px solid var(--border-soft)",
    "border-radius: 6px",
    "background: " + background,
    "color: " + foreground,
    "font-size: 14px",
    "font-weight: 700",
    "cursor: " + cursor,
    "opacity: " + opacity,
    "transition: opacity 120ms ease, transform 120ms ease",
  ]
}

///|
fn primary_button_style(enabled : Bool) -> Array[String] {
  button_style(
    "linear-gradient(135deg, var(--action-strong), var(--action))", "var(--on-action)",
    enabled,
  ) +
  ["box-shadow: 0 8px 18px var(--action-soft)"]
}

///|
fn secondary_button_style(enabled : Bool) -> Array[String] {
  button_style("var(--surface-3)", "var(--text-1)", enabled)
}

///|
fn subtle_danger_button_style(enabled : Bool) -> Array[String] {
  let foreground = if enabled { "var(--danger)" } else { "var(--text-3)" }
  let border_color = if enabled {
    "rgba(255, 122, 122, 0.18)"
  } else {
    "var(--border-soft)"
  }
  let background = if enabled {
    "rgba(255, 122, 122, 0.06)"
  } else {
    "transparent"
  }
  let cursor = if enabled { "pointer" } else { "not-allowed" }
  let opacity = if enabled { "1" } else { "0.45" }
  mono_style() +
  [
    "display: inline-flex",
    "align-items: center",
    "justify-content: center",
    "padding: 8px 10px",
    "border: 1px solid " + border_color,
    "border-radius: 5px",
    "background: " + background,
    "color: " + foreground,
    "font-size: 11px",
    "font-weight: 700",
    "letter-spacing: 0.06em",
    "text-transform: uppercase",
    "cursor: " + cursor,
    "opacity: " + opacity,
  ]
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
  [
    "width: 100%",
    "padding: 12px 14px",
    "border: 1px solid " + border_color,
    "border-radius: 6px",
    "background: " + background,
    "font-size: 15px",
    "line-height: 1.5",
    "color: var(--text-1)",
    "outline: none",
    "box-shadow: inset 0 1px 0 rgba(255, 255, 255, 0.02)",
  ]
}
