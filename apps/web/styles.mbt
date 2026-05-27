///|
fn theme_variables(theme_mode : ThemeMode) -> Array[String] {
  match theme_mode {
    System => theme_variables(Light)
    Dark =>
      [
        "--background: oklch(0.145 0.015 270)", "--background-elevated: color-mix(in srgb, var(--foreground) 1.5%, var(--background))",
        "--foreground: oklch(0.95 0.01 270)", "--foreground-rgb: 237, 236, 240",
        "--accent: oklch(0.65 0.22 293)", "--accent-rgb: 130, 75, 185", "--info: oklch(0.78 0.14 70)",
        "--success: oklch(0.60 0.17 145)", "--destructive: oklch(0.65 0.22 28)",
        "--foreground-2: color-mix(in oklch, var(--foreground) 2%, var(--background))",
        "--foreground-3: color-mix(in oklch, var(--foreground) 3%, var(--background))",
        "--foreground-5: color-mix(in oklch, var(--foreground) 5%, var(--background))",
        "--foreground-10: color-mix(in oklch, var(--foreground) 10%, var(--background))",
        "--foreground-20: color-mix(in oklch, var(--foreground) 20%, var(--background))",
        "--foreground-40: color-mix(in oklch, var(--foreground) 40%, var(--background))",
        "--foreground-50: color-mix(in oklch, var(--foreground) 50%, var(--background))",
        "--foreground-70: color-mix(in oklch, var(--foreground) 70%, var(--background))",
        "--foreground-90: color-mix(in oklch, var(--foreground) 90%, var(--background))",
        "--font-family-ui: system-ui, -apple-system, BlinkMacSystemFont, \"Segoe UI\", Roboto, \"Helvetica Neue\", Arial, sans-serif",
        "--font-title: 14px", "--font-mid: 13px", "--radius-panel: 10px", "--radius-control: 6px",
        "--page-bg: var(--background)", "--page-bg-alt: var(--background)", "--sidebar-bg: var(--background)",
        "--surface-1: var(--foreground-2)", "--surface-2: var(--background)", "--surface-3: var(--foreground-3)",
        "--surface-raised: var(--background)", "--preview-bg: var(--background)",
        "--border-soft: oklch(from var(--foreground) l c h / 0.06)", "--border-strong: oklch(from var(--foreground) l c h / 0.25)",
        "--text-1: var(--foreground)", "--text-2: var(--foreground-70)", "--text-3: var(--foreground-50)",
        "--accent-strong: var(--accent)", "--accent-soft: oklch(from var(--accent) l c h / 0.14)",
        "--action: var(--foreground)", "--action-strong: var(--foreground)", "--action-soft: var(--foreground-5)",
        "--on-action: var(--background)", "--danger: var(--destructive)", "--danger-soft: oklch(from var(--destructive) l c h / 0.12)",
        "--warning: var(--info)", "--warning-soft: oklch(from var(--info) l c h / 0.12)",
        "--shadow-border-opacity: 0.15", "--shadow-blur-opacity: 0.12", "--shadow: rgba(0, 0, 0, 0) 0px 0px 0px 0px, rgba(0, 0, 0, 0) 0px 0px 0px 0px, rgba(var(--foreground-rgb), var(--shadow-border-opacity)) 0px 0px 0px 1px, rgba(0, 0, 0, var(--shadow-blur-opacity)) 0px 1px 1px -0.5px, rgba(0, 0, 0, var(--shadow-blur-opacity)) 0px 3px 3px -1.5px, rgba(0, 0, 0, var(--shadow-blur-opacity)) 0px 6px 6px -3px",
        "--badge-idle-bg: var(--foreground-5)", "--badge-idle-fg: var(--foreground-50)",
        "--badge-running-bg: oklch(from var(--info) l c h / 0.14)", "--badge-running-fg: var(--info)",
        "--badge-success-bg: oklch(from var(--success) l c h / 0.14)", "--badge-success-fg: var(--success)",
        "--badge-failed-bg: oklch(from var(--destructive) l c h / 0.14)", "--badge-failed-fg: var(--destructive)",
        "--badge-cancelled-bg: var(--foreground-5)", "--badge-cancelled-fg: var(--foreground-50)",
        "color-scheme: dark",
      ]
    Light =>
      [
        "--background: oklch(0.98 0.003 265)", "--background-elevated: color-mix(in srgb, var(--foreground) 1.5%, var(--background))",
        "--foreground: oklch(0.185 0.01 270)", "--foreground-rgb: 38, 36, 42", "--accent: oklch(0.62 0.13 293)",
        "--accent-rgb: 104, 78, 133", "--info: oklch(0.75 0.16 70)", "--success: oklch(0.55 0.17 145)",
        "--destructive: oklch(0.58 0.24 28)", "--foreground-2: color-mix(in oklch, var(--foreground) 2%, var(--background))",
        "--foreground-3: color-mix(in oklch, var(--foreground) 3%, var(--background))",
        "--foreground-5: color-mix(in oklch, var(--foreground) 5%, var(--background))",
        "--foreground-10: color-mix(in oklch, var(--foreground) 10%, var(--background))",
        "--foreground-20: color-mix(in oklch, var(--foreground) 20%, var(--background))",
        "--foreground-40: color-mix(in oklch, var(--foreground) 40%, var(--background))",
        "--foreground-50: color-mix(in oklch, var(--foreground) 50%, var(--background))",
        "--foreground-70: color-mix(in oklch, var(--foreground) 70%, var(--background))",
        "--foreground-90: color-mix(in oklch, var(--foreground) 90%, var(--background))",
        "--font-family-ui: system-ui, -apple-system, BlinkMacSystemFont, \"Segoe UI\", Roboto, \"Helvetica Neue\", Arial, sans-serif",
        "--font-title: 14px", "--font-mid: 13px", "--radius-panel: 10px", "--radius-control: 6px",
        "--page-bg: var(--background)", "--page-bg-alt: var(--background)", "--sidebar-bg: var(--background)",
        "--surface-1: var(--foreground-2)", "--surface-2: var(--background)", "--surface-3: var(--foreground-3)",
        "--surface-raised: var(--background)", "--preview-bg: var(--background)",
        "--border-soft: oklch(from var(--foreground) l c h / 0.06)", "--border-strong: oklch(from var(--foreground) l c h / 0.25)",
        "--text-1: var(--foreground)", "--text-2: var(--foreground-70)", "--text-3: var(--foreground-50)",
        "--accent-strong: var(--accent)", "--accent-soft: oklch(from var(--accent) l c h / 0.12)",
        "--action: var(--foreground)", "--action-strong: var(--foreground)", "--action-soft: var(--foreground-5)",
        "--on-action: var(--background)", "--danger: var(--destructive)", "--danger-soft: oklch(from var(--destructive) l c h / 0.10)",
        "--warning: var(--info)", "--warning-soft: oklch(from var(--info) l c h / 0.12)",
        "--shadow-border-opacity: 0.08", "--shadow-blur-opacity: 0.06", "--shadow: rgba(0, 0, 0, 0) 0px 0px 0px 0px, rgba(0, 0, 0, 0) 0px 0px 0px 0px, rgba(var(--foreground-rgb), var(--shadow-border-opacity)) 0px 0px 0px 1px, rgba(0, 0, 0, var(--shadow-blur-opacity)) 0px 1px 1px -0.5px, rgba(0, 0, 0, var(--shadow-blur-opacity)) 0px 3px 3px -1.5px, rgba(0, 0, 0, var(--shadow-blur-opacity)) 0px 6px 6px -3px",
        "--badge-idle-bg: var(--foreground-5)", "--badge-idle-fg: var(--foreground-50)",
        "--badge-running-bg: oklch(from var(--info) l c h / 0.14)", "--badge-running-fg: color-mix(in oklab, var(--info) 50%, var(--foreground))",
        "--badge-success-bg: oklch(from var(--success) l c h / 0.14)", "--badge-success-fg: color-mix(in oklab, var(--success) 50%, var(--foreground))",
        "--badge-failed-bg: oklch(from var(--destructive) l c h / 0.14)", "--badge-failed-fg: color-mix(in oklab, var(--destructive) 50%, var(--foreground))",
        "--badge-cancelled-bg: var(--foreground-5)", "--badge-cancelled-fg: var(--foreground-50)",
        "color-scheme: light",
      ]
  }
}

///|
fn app_root_style(theme_mode : ThemeMode) -> Array[String] {
  theme_variables(theme_mode) +
  [
    "min-height: 100vh", "padding: 0", "background-color: var(--page-bg)", "background-image: none",
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
    "background: var(--surface-1)", "border: 0", "border-radius: var(--radius-panel)",
    "box-shadow: var(--shadow)", "overflow: hidden", "backdrop-filter: none",
  ]
}

///|
fn section_label_style() -> Array[String] {
  normal_text_style()
}

///|
fn title_text_style() -> Array[String] {
  [
    "font-size: var(--font-title)", "font-weight: 600", "line-height: 1.25", "letter-spacing: 0",
    "color: var(--text-1)",
  ]
}

///|
fn normal_text_style() -> Array[String] {
  [
    "font-size: var(--font-mid)", "font-weight: 400", "line-height: 1.5", "letter-spacing: 0",
    "color: var(--text-2)",
  ]
}

///|
fn value_text_style() -> Array[String] {
  [
    "font-size: var(--font-mid)", "font-weight: 500", "line-height: 1.45", "letter-spacing: 0",
    "color: var(--text-1)",
  ]
}

///|
fn button_style(
  background : String,
  foreground : String,
  enabled : Bool,
) -> Array[String] {
  @shared.button_base_style(
    [
      "font-size: var(--font-mid)", "font-weight: 600", "line-height: 1.45", "letter-spacing: 0",
    ],
    background,
    foreground,
    enabled,
    "7px 10px",
    "1px solid transparent",
  ) +
  ["transition: background 100ms ease, color 100ms ease, opacity 100ms ease"]
}

///|
fn primary_button_style(enabled : Bool) -> Array[String] {
  button_style("var(--action)", "var(--on-action)", enabled) +
  ["box-shadow: none"]
}

///|
fn secondary_button_style(enabled : Bool) -> Array[String] {
  button_style("var(--foreground-5)", "var(--text-1)", enabled)
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
    "padding: 8px 10px",
    "border: 1px solid \{border_color}",
    "border-radius: var(--radius-control)",
    "background: \{background}",
    "outline: none",
    "box-shadow: inset 0 1px 0 rgba(255, 255, 255, 0.02)",
  ]
}
