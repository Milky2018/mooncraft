///|
fn render_message(message : @sdk.ChatMessage) -> @rabbita.Html {
  let is_user = message.role is User
  let bubble_background = if is_user {
    "linear-gradient(135deg, var(--action-strong), var(--action))"
  } else {
    "var(--surface-2)"
  }
  let bubble_foreground = if is_user {
    "var(--on-action)"
  } else {
    "var(--text-1)"
  }
  let justify = if is_user { "flex-end" } else { "flex-start" }
  let bubble_border = if is_user {
    "rgba(255,255,255,0.08)"
  } else {
    "var(--border-soft)"
  }
  @html.div(style=["display: flex", "justify-content: " + justify]) <| (@html.div(
    style=[
      "max-width: min(720px, 88%)",
      "padding: 16px 18px",
      "border-radius: 16px",
      "background: " + bubble_background,
      "color: " + bubble_foreground,
      "border: 1px solid " + bubble_border,
      "box-shadow: 0 14px 32px rgba(15, 23, 42, 0.08)",
    ],
  ) <| [
    @html.div(
      style=mono_style() +
        [
          "font-size: 11px", "letter-spacing: 0.08em", "text-transform: uppercase",
          "opacity: 0.86", "margin-bottom: 8px", "font-weight: 700",
        ],
      message.role.label(),
    ),
    render_markdown_message(message.content, is_user~),
  ])
}

///|
fn latest_run_event_text(events : Array[@sdk.RunEvent]) -> String {
  let mut text = "Starting the builder..."
  for event in events {
    if event.content != "" {
      text = event.content
    }
  }
  friendly_run_event_text(text)
}

///|
fn friendly_run_event_text(text : String) -> String {
  if text.contains("Fetching MoonBit project dependencies") ||
    text.contains("moon fetch") {
    "Gathering the app building blocks."
  } else if text.contains("Formatting") || text.contains("moon fmt") {
    "Tidying the project files."
  } else if text.contains("Checking") || text.contains("moon check") {
    "Checking that the app is consistent."
  } else if text.contains("Running tests") || text.contains("moon test") {
    "Testing the generated app."
  } else if text.contains("Refreshing MoonBit registry") ||
    text.contains("moon update") {
    "Refreshing the MoonBit package index."
  } else if text.contains("Updated project files") {
    "Updated the app files."
  } else if text.contains("Started the builder session") ||
    text.contains("Planning") {
    "Planning the next version."
  } else if text.contains("Running local builder") {
    "Drafting the app locally."
  } else {
    text
  }
}

///|
fn run_spinner_frame(tick : Int) -> String {
  let frames = ["●", "●", "●", "●", "●", "●", "●", "●"]
  frames[tick % frames.length()]
}

///|
fn render_run_events(model : Model) -> @rabbita.Html {
  if active_run(model) is None {
    return @html.nothing
  }
  @html.div(style=["display: flex", "justify-content: flex-start"]) <| (@html.div(
    style=[
      "max-width: min(760px, 92%)", "padding: 16px 18px", "border-radius: 16px",
      "background: var(--surface-2)", "color: var(--text-1)", "border: 1px solid var(--border-soft)",
      "box-shadow: 0 14px 32px rgba(15, 23, 42, 0.08)", "display: flex", "flex-direction: column",
      "gap: 10px",
    ],
  ) <| [
    @html.div(
      style=mono_style() +
        [
          "font-size: 11px", "letter-spacing: 0.08em", "text-transform: uppercase",
          "opacity: 0.86", "font-weight: 700",
        ],
      "Crafting your app",
    ),
    @html.div(
      style=[
        "display: flex", "align-items: center", "gap: 12px", "padding: 14px", "border-radius: 16px",
        "background: var(--surface-3)", "border: 1px solid var(--border-soft)", "color: var(--text-2)",
      ],
      [
        @html.div(
          style=[
            "font-size: 18px", "line-height: 1", "width: 28px", "height: 28px", "border-radius: 999px",
            "display: grid", "place-items: center", "color: var(--accent)", "background: var(--accent-soft)",
            "flex-shrink: 0",
          ],
          run_spinner_frame(model.run_spinner_tick),
        ),
        @html.div(
          style=[
            "font-size: 14px", "font-weight: 700", "line-height: 1.55", "white-space: pre-wrap",
            "overflow-wrap: anywhere", "color: var(--text-1)",
          ],
          latest_run_event_text(model.run_events),
        ),
      ],
    ),
  ])
}

///|
fn render_run_banner(model : Model) -> @rabbita.Html {
  match active_run(model) {
    Some(run) =>
      @html.div(
        style=[
          "padding: 12px 14px", "border-radius: 14px", "background: var(--action-soft)",
          "border: 1px solid var(--border-soft)", "display: flex", "justify-content: space-between",
          "align-items: center", "gap: 12px",
        ],
      ) <| [
        @html.div(
          style=["font-size: 14px", "font-weight: 600", "color: var(--text-1)"],
          "Building your app...",
        ),
        status_badge(run.state),
      ]
    None => @html.nothing
  }
}

///|
fn ui_empty_to_none(value : String) -> String? {
  if value == "" {
    None
  } else {
    Some(value)
  }
}

///|
fn debug_value_row(label : String, value : String?) -> @rabbita.Html {
  match value {
    Some(text) if text != "" =>
      @html.div(
        style=[
          "display: grid", "grid-template-columns: 120px minmax(0, 1fr)", "gap: 10px",
          "font-size: 12px", "line-height: 1.5",
        ],
      ) <| [
        @html.div(
          style=mono_style() + ["color: var(--text-3)", "font-weight: 700"],
          label,
        ),
        @html.div(
          style=mono_style() +
            [
              "color: var(--text-2)", "overflow-wrap: anywhere", "white-space: pre-wrap",
            ],
          text,
        ),
      ]
    _ => @html.nothing
  }
}

///|
fn optional_int_text(value : Int?) -> String? {
  match value {
    Some(number) => Some(number.to_string())
    None => None
  }
}

///|
fn render_run_failure_debug(run : @sdk.RunStatusResponse) -> @rabbita.Html {
  match run.failure_debug {
    Some(debug) =>
      @html.div(
        style=[
          "padding: 12px", "border-radius: 10px", "background: var(--surface-3)",
          "border: 1px solid var(--border-soft)", "display: flex", "flex-direction: column",
          "gap: 8px",
        ],
      ) <| [
        debug_value_row("Stage", ui_empty_to_none(debug.stage)),
        debug_value_row("Exit Code", optional_int_text(debug.exit_code)),
        debug_value_row("Command", debug.command),
        debug_value_row("Builder Log", debug.codex_log_path),
        debug_value_row("Validation Log", debug.validation_log_path),
        debug_value_row("Final Summary", debug.final_summary_path),
      ]
    None => @html.nothing
  }
}

///|
fn render_run_failure_detail(
  summary : String,
  details : String?,
) -> @rabbita.Html {
  match details {
    Some(text) if text != "" && text != summary =>
      @html.div(style=["display: flex", "flex-direction: column", "gap: 8px"], [
        @html.div(
          style=["font-size: 12px", "font-weight: 700", "color: var(--text-2)"],
          "Failure detail",
        ),
        @html.div(
          style=mono_style() +
            [
              "padding: 12px", "border-radius: 10px", "background: var(--surface-2)",
              "border: 1px solid var(--border-soft)", "font-size: 12px", "line-height: 1.5",
              "color: var(--text-2)", "white-space: pre-wrap", "overflow-wrap: anywhere",
            ],
          text,
        ),
      ])
    _ => @html.nothing
  }
}

///|
fn render_run_failure_card(model : Model) -> @rabbita.Html {
  if model.app_mode != "development" {
    return @html.nothing
  }
  match model.run_status {
    Some(run) if run.state is Failed => {
      let summary = run_failure_summary(run).unwrap_or(
        "The run failed before the preview could be refreshed.",
      )
      @html.div(
        style=[
          "padding: 14px 16px", "border-radius: 12px", "background: var(--danger-soft)",
          "border: 1px solid var(--border-soft)", "display: flex", "flex-direction: column",
          "gap: 12px",
        ],
      ) <| [
        @html.div(
          style=["font-size: 14px", "font-weight: 700", "color: var(--text-1)"],
          "Run failed",
        ),
        @html.div(
          style=[
            "font-size: 14px", "line-height: 1.6", "color: var(--text-1)", "white-space: pre-wrap",
          ],
          summary,
        ),
        render_run_failure_debug(run),
        render_run_failure_detail(summary, run.error_message),
      ]
    }
    _ => @html.nothing
  }
}

///|
fn render_new_project_form(
  dispatch : @rabbita.Dispatch[Msg],
  model : Model,
  compact : Bool,
) -> @rabbita.Html {
  let enabled = can_create_project(model)
  let direction = if compact { "column" } else { "row" }
  let button_width = if compact { "100%" } else { "auto" }
  @html.div(
    style=[
      "display: flex",
      "flex-direction: " + direction,
      "gap: 10px",
      "align-items: stretch",
      "width: 100%",
    ],
  ) <| [
    @html.input(
      input_type=Text,
      value=model.new_project_name,
      placeholder="Project name",
      read_only=model.create_project_pending,
      on_input=fn(value) { dispatch(NewProjectNameChanged(value)) },
      style=input_style(model.create_project_pending) +
        ["min-width: 0", "flex: 1", "font-size: 14px", "padding: 11px 12px"],
      "",
    ),
    @html.button(
      type_="button",
      disabled=!enabled,
      on_click=dispatch(CreateProject),
      style=primary_button_style(enabled) +
        ["width: " + button_width, "padding: 11px 14px"],
      if model.create_project_pending {
        "Creating..."
      } else {
        "Create Project"
      },
    ),
  ]
}

///|
fn render_workspace_empty(
  dispatch : @rabbita.Dispatch[Msg],
  model : Model,
) -> @rabbita.Html {
  match model.selected_project_id {
    None =>
      @html.div(
        style=inset_panel_style() +
          [
            "padding: 24px 28px", "display: flex", "flex-direction: column", "gap: 14px",
            "min-height: 190px", "justify-content: center",
          ],
      ) <| [
        @html.div(
          style=[
            "font-size: 28px", "line-height: 1.08", "font-weight: 600", "letter-spacing: -0.03em",
          ],
          "Start with a product idea.",
        ),
        @html.div(
          style=[
            "font-size: 15px", "line-height: 1.65", "color: var(--text-2)", "max-width: 560px",
          ],
          "Name the project first, then describe the app in plain English and watch the live preview appear beside the chat.",
        ),
        render_new_project_form(dispatch, model, false),
      ]
    Some(_) =>
      @html.div(
        style=inset_panel_style() +
          [
            "padding: 22px 28px", "display: flex", "flex-direction: column", "gap: 12px",
            "justify-content: center",
          ],
      ) <| [
        @html.div(
          style=[
            "font-size: 28px", "line-height: 1.08", "font-weight: 600", "letter-spacing: -0.03em",
          ],
          "What should this app become?",
        ),
        @html.div(
          style=[
            "font-size: 15px", "line-height: 1.65", "color: var(--text-2)", "max-width: 580px",
          ],
          "Try: \"Build a simple CRM for indie founders\", \"Create a habit tracker\", or \"Make a landing page with signup\".",
        ),
      ]
  }
}

///|
fn render_project_rename_form(
  dispatch : @rabbita.Dispatch[Msg],
  model : Model,
) -> @rabbita.Html {
  match model.project_detail {
    Some(_) =>
      @html.div(
        style=[
          "display: flex", "gap: 8px", "align-items: center", "max-width: 520px",
        ],
      ) <| [
        @html.input(
          input_type=Text,
          value=model.rename_project_name,
          placeholder="Project name",
          read_only=model.rename_project_pending,
          on_input=fn(value) { dispatch(RenameProjectNameChanged(value)) },
          style=input_style(model.rename_project_pending) +
            ["min-width: 0", "flex: 1", "font-size: 13px", "padding: 9px 10px"],
          "",
        ),
        @html.button(
          type_="button",
          disabled=!can_rename_project(model),
          on_click=dispatch(SaveProjectRename),
          style=button_style(
              "var(--surface-2)",
              "var(--text-1)",
              can_rename_project(model),
            ) +
            ["padding: 9px 12px", "font-size: 13px", "white-space: nowrap"],
          if model.rename_project_pending {
            "Saving..."
          } else {
            "Rename"
          },
        ),
      ]
    None => @html.nothing
  }
}

///|
fn render_workspace_panel(
  dispatch : @rabbita.Dispatch[Msg],
  model : Model,
) -> @rabbita.Html {
  let send_enabled = can_send(model)
  let composer_placeholder = if model.selected_project_id is Some(_) {
    "Tell Mooncraft what to build or change..."
  } else {
    "Create a project first."
  }
  let messages = if model.messages.length() == 0 {
    [render_workspace_empty(dispatch, model)]
  } else {
    let rendered = model.messages.map(render_message)
    if active_run(model) is Some(_) {
      rendered.push(render_run_events(model))
    }
    rendered
  }
  @html.div(
    style=panel_style() +
      [
        "flex: 1.08 1 640px", "min-width: 420px", "display: flex", "flex-direction: column",
        "min-height: 0", "overflow: hidden",
      ],
  ) <| [
    @html.div(
      style=[
        "padding: 20px 22px 16px", "border-bottom: 1px solid var(--border-soft)",
        "display: flex", "justify-content: space-between", "align-items: flex-start",
        "gap: 12px", "flex-wrap: wrap",
      ],
      [
        @html.div(
          style=["display: flex", "flex-direction: column", "gap: 6px"],
          [
            @html.div(
              style=[
                "font-size: 30px", "line-height: 1.04", "font-weight: 600", "letter-spacing: -0.03em",
              ],
              project_headline(model),
            ),
            @html.div(
              style=[
                "font-size: 14px", "line-height: 1.55", "color: var(--text-2)",
              ],
              "Chat with the builder. The generated app stays hidden behind the live preview.",
            ),
            render_project_rename_form(dispatch, model),
          ],
        ),
        status_badge(active_project_status(model)),
      ],
    ),
    @html.div(
      style=[
        "padding: 14px 22px 0", "display: flex", "flex-direction: column", "gap: 10px",
      ],
      [
        render_notice_card(model.notice, "var(--warning-soft)"),
        render_run_banner(model),
        render_run_failure_card(model),
      ],
    ),
    @html.div(
      style=[
        "flex: 1", "min-height: 0", "padding: 14px 22px", "display: flex", "flex-direction: column",
        "gap: 14px", "overflow-y: auto",
      ],
      messages,
    ),
    if model.selected_project_id is None {
      @html.nothing
    } else {
      @html.div(
        style=[
          "padding: 16px 22px 22px", "border-top: 1px solid var(--border-soft)",
          "display: flex", "flex-direction: column", "gap: 10px",
        ],
        [
          @html.textarea(
            rows=6,
            value=model.draft,
            disabled=active_run(model) is Some(_),
            placeholder=composer_placeholder,
            on_input=fn(value) { dispatch(DraftChanged(value)) },
            style=input_style(active_run(model) is Some(_)) +
              [
                "min-height: 132px", "resize: vertical", "font-size: 16px", "box-shadow: 0 16px 40px rgba(15, 23, 42, 0.07)",
              ],
            "",
          ),
          @html.div(
            style=[
              "display: flex", "justify-content: flex-end", "align-items: center",
              "gap: 12px", "flex-wrap: wrap",
            ],
            [
              @html.button(
                type_="button",
                disabled=!send_enabled,
                on_click=dispatch(SendDraft),
                style=primary_button_style(send_enabled),
                if active_run(model) is Some(_) {
                  "Building..."
                } else {
                  "Build With Mooncraft"
                },
              ),
            ],
          ),
        ],
      )
    },
  ]
}

///|
fn preview_url_with_theme(url : String, theme_mode : ThemeMode) -> String {
  let separator = if url.contains("?") { "&" } else { "?" }
  url + separator + "theme=" + theme_mode.storage_value()
}

///|
fn ready_preview(model : Model) -> @sdk.PreviewTarget? {
  match model.project_detail {
    Some(project) =>
      match project.preview {
        Some(target) => if target.healthy { Some(target) } else { None }
        None => None
      }
    None => None
  }
}

///|
fn render_preview_panel(model : Model) -> @rabbita.Html {
  let preview = model.project_detail.bind(fn(project) { project.preview })
  let status = match preview {
    Some(target) => if target.healthy { @sdk.Succeeded } else { Failed }
    None => if active_run(model) is Some(_) { Running } else { Idle }
  }
  @html.div(
    style=panel_style() +
      [
        "flex: 0.92 1 440px", "min-width: 360px", "display: flex", "flex-direction: column",
        "min-height: 0", "overflow: hidden",
      ],
  ) <| [
    @html.div(
      style=[
        "padding: 18px 20px", "border-bottom: 1px solid var(--border-soft)", "display: flex",
        "justify-content: space-between", "align-items: flex-start", "gap: 12px",
        "flex-wrap: wrap",
      ],
      [
        @html.div(
          style=["display: flex", "flex-direction: column", "gap: 6px"],
          [
            @html.div(
              style=[
                "font-size: 28px", "line-height: 1.04", "font-weight: 600", "letter-spacing: -0.03em",
              ],
              "Live preview",
            ),
            @html.div(
              style=[
                "font-size: 13px", "line-height: 1.55", "color: var(--text-2)",
              ],
              "The generated app appears here when Mooncraft finishes a run.",
            ),
          ],
        ),
        status_badge(status),
      ],
    ),
    @html.div(
      style=[
        "flex: 1", "min-height: 0", "padding: 14px", "background: linear-gradient(180deg, var(--surface-2), var(--surface-3))",
      ],
      @html.div(
        style=[
          "height: 100%", "border-radius: 16px", "overflow: hidden", "background: var(--surface-raised)",
          "border: 1px solid var(--border-soft)", "box-shadow: 0 20px 50px rgba(15, 23, 42, 0.12)",
          "display: flex", "flex-direction: column",
        ],
        [
          preview_browser_chrome(preview),
          match preview {
            Some(target) =>
              @html.iframe(
                title="Live Preview",
                src=preview_url_with_theme(
                  target.url,
                  model.resolved_theme_mode,
                ),
                loading="eager",
                style=[
                  "flex: 1", "min-height: 0", "width: 100%", "border: none", "background: var(--preview-bg)",
                ],
              )
            None => preview_empty_state(model)
          },
        ],
      ),
    ),
  ]
}

///|
fn preview_browser_chrome(preview : @sdk.PreviewTarget?) -> @rabbita.Html {
  let url_text = match preview {
    Some(target) => target.url
    None => "Preview will open here"
  }
  @html.div(
    style=[
      "height: 46px", "display: flex", "align-items: center", "gap: 10px", "padding: 0 12px",
      "background: rgba(255, 255, 255, 0.72)", "border-bottom: 1px solid var(--border-soft)",
    ],
  ) <| [
    @html.div(style=["display: flex", "gap: 5px"], [
      browser_dot("#ef6461"),
      browser_dot("#f5bd4f"),
      browser_dot("#62c554"),
    ]),
    @html.div(
      style=mono_style() +
        [
          "flex: 1", "min-width: 0", "padding: 7px 10px", "border-radius: 999px",
          "background: rgba(248, 250, 252, 0.96)", "color: var(--text-3)", "font-size: 11px",
          "white-space: nowrap", "overflow: hidden", "text-overflow: ellipsis", "border: 1px solid var(--border-soft)",
        ],
      url_text,
    ),
  ]
}

///|
fn browser_dot(color : String) -> @rabbita.Html {
  @html.div(
    style=[
      "width: 10px",
      "height: 10px",
      "border-radius: 999px",
      "background: " + color,
    ],
  ) <| ""
}

///|
fn preview_empty_state(model : Model) -> @rabbita.Html {
  let title = if active_run(model) is Some(_) {
    "Building the first preview"
  } else if model.selected_project_id is Some(_) {
    "No preview yet"
  } else {
    "Create a project first"
  }
  let body = if active_run(model) is Some(_) {
    "Mooncraft is assembling the app. The live version will load here automatically."
  } else if model.selected_project_id is Some(_) {
    "Send the first request in chat, and the generated app will appear in this window."
  } else {
    "Create a project and describe the app you want to build."
  }
  @html.div(
    style=[
      "flex: 1", "min-height: 0", "display: grid", "place-items: center", "padding: 32px",
      "background: radial-gradient(circle at 50% 24%, var(--accent-soft), transparent 34%), var(--preview-bg)",
    ],
  ) <| (@html.div(
    style=[
      "max-width: 360px", "display: flex", "flex-direction: column", "gap: 12px",
      "text-align: center", "align-items: center",
    ],
  ) <| [
    @html.div(
      style=[
        "width: 58px", "height: 58px", "border-radius: 18px", "background: linear-gradient(135deg, var(--accent), #2563eb)",
        "box-shadow: 0 16px 34px rgba(15, 118, 110, 0.18)",
      ],
      "",
    ),
    @html.div(
      style=["font-size: 23px", "font-weight: 600", "letter-spacing: -0.025em"],
      title,
    ),
    @html.div(
      style=["font-size: 14px", "line-height: 1.7", "color: var(--text-2)"],
      body,
    ),
  ])
}
