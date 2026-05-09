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
      "padding: 10px 12px",
      "border-radius: var(--radius-control)",
      "background: " + bubble_background,
      "color: " + bubble_foreground,
      "border: 1px solid " + bubble_border,
      "box-shadow: 0 14px 32px rgba(15, 23, 42, 0.08)",
    ],
  ) <| [
    @html.div(
      style=normal_text_style() + ["opacity: 0.86", "margin-bottom: 8px"],
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
      "max-width: min(760px, 92%)", "padding: 10px 12px", "border-radius: var(--radius-control)",
      "background: var(--surface-2)", "border: 1px solid var(--border-soft)", "box-shadow: 0 14px 32px rgba(15, 23, 42, 0.08)",
      "display: flex", "flex-direction: column", "gap: 6px",
    ],
  ) <| [
    @html.div(
      style=normal_text_style() + ["opacity: 0.86"],
      "Crafting your app",
    ),
    @html.div(
      style=[
        "display: flex", "align-items: center", "gap: 6px", "padding: 8px", "border-radius: var(--radius-control)",
        "background: var(--surface-3)", "border: 1px solid var(--border-soft)",
      ],
      [
        @html.div(
          style=title_text_style() +
            [
              "width: 28px", "height: 28px", "border-radius: 999px", "display: grid",
              "place-items: center", "color: var(--accent)", "background: var(--accent-soft)",
              "flex-shrink: 0",
            ],
          run_spinner_frame(model.run_spinner_tick),
        ),
        @html.div(
          style=value_text_style() +
            ["white-space: pre-wrap", "overflow-wrap: anywhere"],
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
          "padding: 8px 10px", "border-radius: var(--radius-control)", "background: var(--action-soft)",
          "border: 1px solid var(--border-soft)", "display: flex", "justify-content: space-between",
          "align-items: center", "gap: 6px",
        ],
      ) <| [
        @html.div(style=value_text_style(), "Building your app..."),
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
        style=normal_text_style() +
          [
            "display: grid", "grid-template-columns: 120px minmax(0, 1fr)", "gap: 6px",
          ],
      ) <| [
        @html.div(style=normal_text_style(), label),
        @html.div(
          style=normal_text_style() +
            ["overflow-wrap: anywhere", "white-space: pre-wrap"],
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
          "padding: 8px", "border-radius: var(--radius-control)", "background: var(--surface-3)",
          "border: 1px solid var(--border-soft)", "display: flex", "flex-direction: column",
          "gap: 6px",
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
      @html.div(style=["display: flex", "flex-direction: column", "gap: 6px"], [
        @html.div(style=value_text_style(), "Failure detail"),
        @html.div(
          style=normal_text_style() +
            [
              "padding: 8px", "border-radius: var(--radius-control)", "background: var(--surface-2)",
              "border: 1px solid var(--border-soft)", "white-space: pre-wrap", "overflow-wrap: anywhere",
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
          "padding: 10px 12px", "border-radius: var(--radius-control)", "background: var(--danger-soft)",
          "border: 1px solid var(--border-soft)", "display: flex", "flex-direction: column",
          "gap: 6px",
        ],
      ) <| [
        @html.div(style=value_text_style(), "Run failed"),
        @html.div(style=value_text_style() + ["white-space: pre-wrap"], summary),
        render_run_failure_debug(run),
        render_run_failure_detail(summary, run.error_message),
      ]
    }
    _ => @html.nothing
  }
}

///|
fn render_open_project_button(
  dispatch : @rabbita.Dispatch[Msg],
  label : String,
  full_width : Bool,
) -> @rabbita.Html {
  let width = if full_width { "100%" } else { "auto" }
  @html.button(
    type_="button",
    disabled=false,
    on_click=dispatch(OpenNewProjectDialog),
    style=primary_button_style(true) + ["width: " + width],
    label,
  )
}

///|
fn model_display_label(
  item : @sdk.AiModelSummary,
  default_model : String,
) -> String {
  let name = if item.name.trim() == "" { item.id } else { item.name }
  let label = if name == item.id { item.id } else { name + " - " + item.id }
  if item.id == default_model {
    label + " (default)"
  } else {
    label
  }
}

///|
fn agent_cli_label(agent_cli : String) -> String {
  match agent_cli {
    "claude_code" => "Claude Code"
    "kimi_code" => "Kimi Code"
    _ => "Codex"
  }
}

///|
fn render_agent_select_options(model : Model) -> Array[@rabbita.Html] {
  let items : Array[@rabbita.Html] = []
  for agent_cli in ["codex", "claude_code", "kimi_code"] {
    items.push(
      @html.option(
        value=agent_cli,
        selected=agent_cli == model.new_project_agent_cli,
        agent_cli_label(agent_cli),
      ),
    )
  }
  items
}

///|
fn model_list_contains(
  items : Array[@sdk.AiModelSummary],
  model_id : String,
) -> Bool {
  for item in items {
    if item.id == model_id {
      return true
    }
  }
  false
}

///|
fn render_disclosure_icon(open : Bool) -> @rabbita.Html {
  @svg.svg(
    width=15,
    height=15,
    view_box="0 0 24 24",
    style=["display: block"],
    [
      @svg.path(
        d=if open { "M6 9l6 6 6-6" } else { "M9 6l6 6-6 6" },
        fill="none",
        stroke="currentColor",
        stroke_width=2,
      ),
    ],
  )
}

///|
fn render_model_select_options(model : Model) -> Array[@rabbita.Html] {
  let selected_model = model.new_project_model
  let items : Array[@rabbita.Html] = []
  if model.ai_models_loading && model.ai_models.length() == 0 {
    items.push(
      @html.option(value="", selected=true, "Loading OpenRouter models..."),
    )
  } else {
    if selected_model != "" &&
      !model_list_contains(model.ai_models, selected_model) {
      items.push(
        @html.option(value=selected_model, selected=true, selected_model),
      )
    }
    for item in model.ai_models {
      if model_id_compatible_with_agent(model.new_project_agent_cli, item.id) {
        items.push(
          @html.option(
            value=item.id,
            selected=item.id == selected_model,
            model_display_label(item, model.ai_models_default_model),
          ),
        )
      }
    }
    if items.length() == 0 {
      items.push(@html.option(value="", selected=true, "Use admin default"))
    }
  }
  items
}

///|
fn render_new_project_more(
  dispatch : @rabbita.Dispatch[Msg],
  model : Model,
) -> @rabbita.Html {
  @html.div(
    style=[
      "border: 1px solid var(--border-soft)", "border-radius: var(--radius-control)",
      "background: var(--surface-2)", "overflow: hidden",
    ],
  ) <| [
    @html.button(
      type_="button",
      disabled=model.create_project_pending,
      on_click=dispatch(ToggleNewProjectMore),
      style=value_text_style() +
        [
          "width: 100%", "border: 0", "background: transparent", "padding: 8px 10px",
          "display: flex", "align-items: center", "justify-content: space-between",
          "gap: 6px", "cursor: pointer",
        ],
    ) <| [
      @html.span("More options"),
      render_disclosure_icon(model.new_project_more_open),
    ],
    if model.new_project_more_open {
      @html.div(
        style=[
          "border-top: 1px solid var(--border-soft)", "padding: 8px", "display: flex",
          "flex-direction: column", "gap: 6px",
        ],
      ) <| [
        @html.div(style=section_label_style(), "Agent"),
        @html.select(
          disabled=model.create_project_pending,
          on_change=fn(value) { dispatch(NewProjectAgentChanged(value)) },
          style=input_style(model.create_project_pending),
          render_agent_select_options(model),
        ),
        @html.div(style=section_label_style(), "Model"),
        @html.select(
          disabled=model.create_project_pending ||
            (model.ai_models_loading && model.ai_models.length() == 0),
          on_change=fn(value) { dispatch(NewProjectModelChanged(value)) },
          style=input_style(
            model.create_project_pending ||
            (model.ai_models_loading && model.ai_models.length() == 0),
          ),
          render_model_select_options(model),
        ),
      ]
    } else {
      @html.nothing
    },
  ]
}

///|
fn render_new_project_dialog(
  dispatch : @rabbita.Dispatch[Msg],
  model : Model,
) -> @rabbita.Html {
  if !model.new_project_modal_open {
    @html.nothing
  } else {
    let enabled = can_create_project(model)
    @html.div(
      style=[
        "position: fixed", "inset: 0", "z-index: 100", "display: flex", "align-items: center",
        "justify-content: center", "padding: 12px", "background: rgba(15, 23, 42, 0.28)",
        "backdrop-filter: blur(10px)",
      ],
    ) <| [
      @html.div(
        style=[
          "width: min(460px, 100%)", "background: var(--surface-raised)", "border: 1px solid var(--border-soft)",
          "border-radius: var(--radius-control)", "box-shadow: 0 28px 80px rgba(15, 23, 42, 0.22)",
          "padding: 8px", "display: flex", "flex-direction: column", "gap: 6px",
        ],
      ) <| [
        @html.div(
          style=[
            "display: flex", "align-items: flex-start", "justify-content: space-between",
            "gap: 6px",
          ],
        ) <| [
          @html.div(
            style=["display: flex", "flex-direction: column", "gap: 6px"],
          ) <| [
            @html.div(style=section_label_style(), "New project"),
            @html.div(style=title_text_style(), "Name the workspace"),
          ],
          @html.button(
            type_="button",
            disabled=model.create_project_pending,
            on_click=dispatch(CloseNewProjectDialog),
            style=secondary_button_style(!model.create_project_pending) +
              [
                "width: 38px", "height: 38px", "padding: 0", "border-radius: 999px",
              ],
            "x",
          ),
        ],
        @html.input(
          input_type=Text,
          value=model.new_project_name,
          placeholder="Snake game, Team CRM, Launch page...",
          read_only=model.create_project_pending,
          on_input=fn(value) { dispatch(NewProjectNameChanged(value)) },
          style=input_style(model.create_project_pending) +
            ["padding: 9px 10px"],
          "",
        ),
        render_new_project_more(dispatch, model),
        @html.div(
          style=[
            "display: flex", "justify-content: flex-end", "gap: 6px", "padding-top: 4px",
          ],
        ) <| [
          @html.button(
            type_="button",
            disabled=model.create_project_pending,
            on_click=dispatch(CloseNewProjectDialog),
            style=secondary_button_style(!model.create_project_pending),
            "Cancel",
          ),
          @html.button(
            type_="button",
            disabled=!enabled,
            on_click=dispatch(CreateProject),
            style=primary_button_style(enabled),
            if model.create_project_pending {
              "Creating..."
            } else {
              "Create Project"
            },
          ),
        ],
      ],
    ]
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
            "padding: 8px", "display: flex", "align-items: center", "min-height: 120px",
          ],
      ) <| [
        @html.div(
          style=["display: flex", "align-items: center", "padding-top: 4px"],
        ) <| [
          render_open_project_button(dispatch, "Create Project", false),
        ],
      ]
    Some(_) => @html.nothing
  }
}

///|
fn render_project_title(model : Model) -> @rabbita.Html {
  match model.project_detail {
    Some(project) =>
      @html.div(
        style=title_text_style() +
          [
            "min-width: 0", "overflow: hidden", "text-overflow: ellipsis", "white-space: nowrap",
          ],
        project.display_name,
      )
    None => @html.div(style=title_text_style(), project_headline(model))
  }
}

///|
fn render_workspace_panel(
  dispatch : @rabbita.Dispatch[Msg],
  model : Model,
) -> @rabbita.Html {
  let send_enabled = can_send(model)
  let composer_placeholder = if model.selected_project_id is Some(_) {
    "Tell MoonCraft what to build or change..."
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
        "padding: 8px", "border-bottom: 1px solid var(--border-soft)", "display: flex",
        "justify-content: space-between", "align-items: flex-start", "gap: 6px",
        "flex-wrap: wrap",
      ],
      [
        @html.div(
          style=[
            "display: flex", "flex-direction: column", "gap: 6px", "min-width: 0",
          ],
          [render_project_title(model)],
        ),
        status_badge(active_project_status(model)),
      ],
    ),
    @html.div(
      style=[
        "padding: 8px 12px 0", "display: flex", "flex-direction: column", "gap: 6px",
      ],
      [
        render_notice_card(model.notice, "var(--warning-soft)"),
        render_run_banner(model),
        render_run_failure_card(model),
      ],
    ),
    @html.div(
      style=[
        "flex: 1", "min-height: 0", "padding: 8px 12px", "display: flex", "flex-direction: column",
        "gap: 6px", "overflow-y: auto",
      ],
      messages,
    ),
    if model.selected_project_id is None {
      @html.nothing
    } else {
      @html.div(
        style=[
          "padding: 10px 12px", "border-top: 1px solid var(--border-soft)", "display: flex",
          "flex-direction: column", "gap: 6px",
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
                "min-height: 132px", "resize: vertical", "box-shadow: 0 16px 40px rgba(15, 23, 42, 0.07)",
              ],
            "",
          ),
          @html.div(
            style=[
              "display: flex", "justify-content: flex-end", "align-items: center",
              "gap: 6px", "flex-wrap: wrap",
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
                  "Build With MoonCraft"
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
        "padding: 10px 12px", "border-bottom: 1px solid var(--border-soft)", "display: flex",
        "justify-content: space-between", "align-items: flex-start", "gap: 6px",
        "flex-wrap: wrap",
      ],
      [
        @html.div(
          style=["display: flex", "flex-direction: column", "gap: 6px"],
          [@html.div(style=title_text_style(), "Live preview")],
        ),
        status_badge(status),
      ],
    ),
    @html.div(
      style=[
        "flex: 1", "min-height: 0", "padding: 8px", "background: linear-gradient(180deg, var(--surface-2), var(--surface-3))",
      ],
      @html.div(
        style=[
          "height: 100%", "border-radius: var(--radius-control)", "overflow: hidden",
          "background: var(--surface-raised)", "border: 1px solid var(--border-soft)",
          "box-shadow: 0 20px 50px rgba(15, 23, 42, 0.12)", "display: flex", "flex-direction: column",
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
    None => "No preview"
  }
  @html.div(
    style=[
      "height: 46px", "display: flex", "align-items: center", "gap: 6px", "padding: 0 12px",
      "background: rgba(255, 255, 255, 0.72)", "border-bottom: 1px solid var(--border-soft)",
    ],
  ) <| [
    @html.div(style=["display: flex", "gap: 5px"], [
      browser_dot("#ef6461"),
      browser_dot("#f5bd4f"),
      browser_dot("#62c554"),
    ]),
    @html.div(
      style=normal_text_style() +
        [
          "flex: 1", "min-width: 0", "padding: 7px 10px", "border-radius: 999px",
          "background: rgba(248, 250, 252, 0.96)", "white-space: nowrap", "overflow: hidden",
          "text-overflow: ellipsis", "border: 1px solid var(--border-soft)",
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
  @html.div(
    style=[
      "flex: 1", "min-height: 0", "display: grid", "place-items: center", "padding: 14px",
      "background: radial-gradient(circle at 50% 24%, var(--accent-soft), transparent 34%), var(--preview-bg)",
    ],
  ) <| (@html.div(
    style=[
      "max-width: 360px", "display: flex", "flex-direction: column", "gap: 6px",
      "text-align: center", "align-items: center",
    ],
  ) <| [
    @html.div(
      style=[
        "width: 58px", "height: 58px", "border-radius: var(--radius-control)", "background: linear-gradient(135deg, var(--accent), #2563eb)",
        "box-shadow: 0 16px 34px rgba(15, 118, 110, 0.18)",
      ],
      "",
    ),
    @html.div(style=title_text_style(), title),
  ])
}
