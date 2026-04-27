///|
fn render_message(message : @sdk.ChatMessage) -> @rabbita.Html {
  let is_user = message.role is @sdk.User
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
  @html.div(
    style=["display: flex", "justify-content: " + justify],
    @html.div(
      style=[
        "max-width: min(720px, 88%)",
        "padding: 14px 16px",
        "border-radius: 6px",
        "background: " + bubble_background,
        "color: " + bubble_foreground,
        "border: 1px solid " + bubble_border,
        "box-shadow: 0 8px 18px rgba(0, 0, 0, 0.14)",
      ],
      [
        @html.div(
          style=mono_style() +
            [
              "font-size: 11px", "letter-spacing: 0.08em", "text-transform: uppercase",
              "opacity: 0.86", "margin-bottom: 8px", "font-weight: 700",
            ],
          message.role.label(),
        ),
        @html.div(
          style=["font-size: 15px", "line-height: 1.7", "white-space: pre-wrap"],
          message.content,
        ),
      ],
    ),
  )
}

///|
fn latest_run_event_text(events : Array[@sdk.RunEvent]) -> String {
  let mut text = "Starting worker..."
  for event in events {
    if event.content != "" {
      text = event.content
    }
  }
  text
}

///|
fn run_spinner_frame(tick : Int) -> String {
  let frames = ["🕛", "🕐", "🕑", "🕒", "🕓", "🕔", "🕕", "🕖"]
  frames[tick % frames.length()]
}

///|
fn render_run_events(model : Model) -> @rabbita.Html {
  if active_run(model) is None {
    return @html.nothing
  }
  @html.div(
    style=["display: flex", "justify-content: flex-start"],
    @html.div(
      style=[
        "max-width: min(760px, 92%)", "padding: 14px 16px", "border-radius: 6px",
        "background: var(--surface-2)", "color: var(--text-1)", "border: 1px solid var(--border-soft)",
        "box-shadow: 0 8px 18px rgba(0, 0, 0, 0.14)", "display: flex", "flex-direction: column",
        "gap: 10px",
      ],
      [
        @html.div(
          style=mono_style() +
            [
              "font-size: 11px", "letter-spacing: 0.08em", "text-transform: uppercase",
              "opacity: 0.86", "font-weight: 700",
            ],
          "MoonBit Cloud is working",
        ),
        @html.div(
          style=[
            "display: flex", "align-items: center", "gap: 10px", "padding: 12px",
            "border-radius: 8px", "background: var(--surface-3)", "border: 1px solid var(--border-soft)",
            "color: var(--text-2)",
          ],
          [
            @html.div(
              style=[
                "font-size: 18px", "line-height: 1", "width: 24px", "text-align: center",
                "flex-shrink: 0",
              ],
              run_spinner_frame(model.run_spinner_tick),
            ),
            @html.div(
              style=mono_style() +
                [
                  "font-size: 13px", "line-height: 1.55", "white-space: pre-wrap",
                  "overflow-wrap: anywhere",
                ],
              latest_run_event_text(model.run_events),
            ),
          ],
        ),
      ],
    ),
  )
}

///|
fn render_run_banner(model : Model) -> @rabbita.Html {
  match active_run(model) {
    Some(run) =>
      @html.div(
        style=[
          "padding: 10px 12px", "border-radius: 6px", "background: var(--action-soft)",
          "border: 1px solid var(--border-soft)", "display: flex", "justify-content: space-between",
          "align-items: center", "gap: 12px",
        ],
        [
          @html.div(
            style=[
              "font-size: 14px", "font-weight: 700", "color: var(--text-1)",
            ],
            "Updating preview...",
          ),
          status_badge(run.state),
        ],
      )
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
        [
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
        ],
      )
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
        [
          debug_value_row("Stage", ui_empty_to_none(debug.stage)),
          debug_value_row("Exit Code", optional_int_text(debug.exit_code)),
          debug_value_row("Command", debug.command),
          debug_value_row("Codex Log", debug.codex_log_path),
          debug_value_row("Validation Log", debug.validation_log_path),
          debug_value_row("Final Summary", debug.final_summary_path),
        ],
      )
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
          style=["font-size: 12px", "font-weight: 760", "color: var(--text-2)"],
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
  match model.run_status {
    Some(run) if run.state is @sdk.Failed => {
      let summary = run_failure_summary(run).unwrap_or(
        "The run failed before the preview could be refreshed.",
      )
      @html.div(
        style=[
          "padding: 14px 16px", "border-radius: 12px", "background: var(--danger-soft)",
          "border: 1px solid var(--border-soft)", "display: flex", "flex-direction: column",
          "gap: 12px",
        ],
        [
          @html.div(
            style=[
              "font-size: 14px", "font-weight: 760", "color: var(--text-1)",
            ],
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
        ],
      )
    }
    _ => @html.nothing
  }
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
            "padding: 18px", "display: flex", "flex-direction: column", "gap: 10px",
          ],
        [
          @html.div(
            style=["font-size: 24px", "line-height: 1.12", "font-weight: 760"],
            "Create a project to start.",
          ),
          @html.div(
            style=[
              "font-size: 15px", "line-height: 1.6", "color: var(--text-2)",
            ],
            "Then describe the first change you want.",
          ),
          @html.button(
            type_="button",
            disabled=model.create_project_pending,
            on_click=dispatch(CreateProject),
            style=primary_button_style(!model.create_project_pending),
            if model.create_project_pending {
              "Creating..."
            } else {
              "Create Project"
            },
          ),
        ],
      )
    Some(_) =>
      @html.div(
        style=inset_panel_style() +
          [
            "padding: 14px", "display: flex", "flex-direction: column", "gap: 8px",
          ],
        [
          @html.div(
            style=["font-size: 18px", "font-weight: 720"],
            "No messages yet.",
          ),
          @html.div(
            style=[
              "font-size: 15px", "line-height: 1.6", "color: var(--text-2)",
            ],
            "Describe the first change you want.",
          ),
        ],
      )
  }
}

///|
fn render_workspace_panel(
  dispatch : @rabbita.Dispatch[Msg],
  model : Model,
) -> @rabbita.Html {
  let send_enabled = can_send(model)
  let composer_placeholder = if model.selected_project_id is Some(_) {
    "Describe the change you want."
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
        "flex: 1 1 620px", "min-width: 360px", "display: flex", "flex-direction: column",
        "min-height: 0", "overflow: hidden",
      ],
    [
      @html.div(
        style=[
          "padding: 16px 18px", "border-bottom: 1px solid var(--border-soft)", "display: flex",
          "justify-content: space-between", "align-items: flex-start", "gap: 12px",
          "flex-wrap: wrap",
        ],
        [
          @html.div(
            style=["display: flex", "flex-direction: column", "gap: 6px"],
            [
              @html.div(
                style=[
                  "font-size: 38px", "line-height: 1.02", "font-weight: 780",
                ],
                project_headline(model),
              ),
            ],
          ),
          status_badge(active_project_status(model)),
        ],
      ),
      @html.div(
        style=[
          "padding: 12px 18px 0", "display: flex", "flex-direction: column", "gap: 8px",
        ],
        [
          render_notice_card(model.notice, "var(--warning-soft)"),
          render_run_banner(model),
          render_run_failure_card(model),
        ],
      ),
      @html.div(
        style=[
          "flex: 1", "min-height: 0", "padding: 12px 18px", "display: flex", "flex-direction: column",
          "gap: 10px", "overflow-y: auto",
        ],
        messages,
      ),
      @html.div(
        style=[
          "padding: 14px 18px 18px", "border-top: 1px solid var(--border-soft)",
          "display: flex", "flex-direction: column", "gap: 10px",
        ],
        [
          @html.textarea(
            rows=6,
            value=model.draft,
            disabled=model.selected_project_id is None ||
              active_run(model) is Some(_),
            placeholder=composer_placeholder,
            on_input=fn(value) { dispatch(DraftChanged(value)) },
            style=input_style(
                model.selected_project_id is None ||
                active_run(model) is Some(_),
              ) +
              ["min-height: 164px", "resize: vertical"],
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
                  "Working..."
                } else {
                  "Send Request"
                },
              ),
            ],
          ),
        ],
      ),
    ],
  )
}

///|
fn preview_url_with_theme(url : String, theme_mode : ThemeMode) -> String {
  let separator = if url.contains("?") { "&" } else { "?" }
  url + separator + "theme=" + theme_mode.storage_value()
}

///|
fn render_preview_panel(model : Model) -> @rabbita.Html {
  let preview = model.project_detail.bind(fn(project) { project.preview })
  match preview {
    Some(target) => {
      let status = if target.healthy { @sdk.Succeeded } else { @sdk.Failed }
      @html.div(
        style=panel_style() +
          [
            "flex: 1 1 420px", "min-width: 320px", "display: flex", "flex-direction: column",
            "min-height: 0", "overflow: hidden",
          ],
        [
          @html.div(
            style=[
              "padding: 16px 18px", "border-bottom: 1px solid var(--border-soft)",
              "display: flex", "justify-content: space-between", "align-items: flex-start",
              "gap: 12px", "flex-wrap: wrap",
            ],
            [
              @html.div(
                style=["display: flex", "flex-direction: column", "gap: 6px"],
                [
                  @html.div(
                    style=[
                      "font-size: 38px", "line-height: 1.02", "font-weight: 780",
                    ],
                    "Preview",
                  ),
                ],
              ),
              status_badge(status),
            ],
          ),
          @html.div(
            style=[
              "flex: 1", "min-height: 0", "background: linear-gradient(180deg, var(--surface-2), var(--surface-3))",
              "overflow: hidden",
            ],
            @html.div(
              style=["height: 100%"],
              @html.iframe(
                title="Live Preview",
                src=preview_url_with_theme(
                  target.url,
                  model.resolved_theme_mode,
                ),
                loading="eager",
                style=[
                  "height: 100%", "width: 100%", "border: none", "background: var(--preview-bg)",
                ],
              ),
            ),
          ),
        ],
      )
    }
    None => @html.nothing
  }
}
