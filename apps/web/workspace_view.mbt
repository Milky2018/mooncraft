///|
fn render_message(message : @sdk.ChatMessage) -> @rabbita.Html {
  let is_user = message.role is User
  let bubble_background = if is_user {
    "var(--foreground-5)"
  } else {
    "transparent"
  }
  let bubble_foreground = if is_user {
    "var(--text-1)"
  } else {
    "var(--text-1)"
  }
  let justify = if is_user { "flex-end" } else { "flex-start" }
  let bubble_border = if is_user { "transparent" } else { "transparent" }
  @html.div(style=["display: flex", "justify-content: \{justify}"]) <| (@html.div(
    style=[
      "max-width: min(720px, 82%)",
      "padding: 8px 10px",
      "border-radius: 12px",
      "background: \{bubble_background}",
      "color: \{bubble_foreground}",
      "border: 1px solid \{bubble_border}",
      "box-shadow: none",
    ],
  ) <| [
    if is_user {
      @html.div(
        style=value_text_style() +
          ["white-space: pre-wrap", "color: \{bubble_foreground}"],
        message.content,
      )
    } else {
      render_markdown_message(message.content, is_user~)
    },
  ])
}

///|
fn latest_run_event_text(events : Array[@sdk.RunEvent]) -> String {
  let mut text = "Starting"
  let mut code = None
  for event in events {
    if event.content != "" {
      text = event.content
      code = Some(event.code)
    }
  }
  @sdk.run_event_display_text(code.unwrap_or(""), text)
}

///|
fn run_spinner_cube() -> @rabbita.Html {
  @html.span(class="spinner-cube", "")
}

///|
fn run_spinner() -> @rabbita.Html {
  @html.span(
    class="spinner",
    attrs=@html.Attrs::build().role("status").aria_label("Loading"),
    [
      run_spinner_cube(),
      run_spinner_cube(),
      run_spinner_cube(),
      run_spinner_cube(),
      run_spinner_cube(),
      run_spinner_cube(),
      run_spinner_cube(),
      run_spinner_cube(),
      run_spinner_cube(),
    ],
  )
}

///|
fn render_run_events(model : Model) -> @rabbita.Html {
  if active_run(model) is None {
    return @html.nothing
  }
  @html.div(
    style=normal_text_style() +
      [
        "display: flex", "align-items: center", "gap: 8px", "padding: 4px 12px",
        "margin-bottom: -4px",
      ],
    [
      @html.div(
        style=[
          "width: 12px", "height: 12px", "display: flex", "align-items: center",
          "justify-content: center", "color: var(--accent)", "flex-shrink: 0",
        ],
        run_spinner(),
      ),
      @html.span(
        style=normal_text_style() +
          [
            "height: 20px", "display: flex", "align-items: center", "white-space: pre-wrap",
            "overflow-wrap: anywhere",
          ],
        latest_run_event_text(model.run_events),
      ),
    ],
  )
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
            "display: grid", "grid-template-columns: 120px minmax(0, 1fr)", "gap: 8px",
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
          "display: flex", "flex-direction: column", "gap: 8px",
        ],
      ) <| [
        debug_value_row("Stage", ui_empty_to_none(debug.stage)),
        debug_value_row("Exit Code", optional_int_text(debug.exit_code)),
        debug_value_row("Command", debug.command),
        debug_value_row("Builder Log", debug.runtime_log_path),
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
        @html.div(style=value_text_style(), "Details"),
        @html.div(
          style=normal_text_style() +
            [
              "padding: 8px", "border-radius: var(--radius-control)", "background: var(--surface-2)",
              "white-space: pre-wrap", "overflow-wrap: anywhere",
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
          "padding: 8px 12px", "border-radius: var(--radius-control)", "background: var(--danger-soft)",
          "display: flex", "flex-direction: column", "gap: 8px",
        ],
      ) <| [
        @html.div(style=value_text_style(), "Failed"),
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
    title=label,
    on_click=dispatch(OpenNewProjectDialog),
    style=primary_button_style(true) +
      ["width: \{width}", "min-width: 32px", "height: 32px", "padding: 0"],
    [plus_icon()],
  )
}

///|
fn runtime_display_label(item : @sdk.RuntimeSummary) -> String {
  if item.is_default {
    "\{item.name} (default)"
  } else {
    item.name
  }
}

///|
fn render_runtime_select_options(model : Model) -> Array[@rabbita.Html] {
  let items : Array[@rabbita.Html] = []
  if model.runtimes_loading && model.runtimes.length() == 0 {
    items.push(@html.option(value="", selected=true, "Loading Runtimes..."))
  } else {
    for item in model.runtimes {
      items.push(
        @html.option(
          value=item.id,
          selected=item.id == model.new_project_runtime_id,
          runtime_display_label(item),
        ),
      )
    }
    if items.length() == 0 {
      items.push(@html.option(value="", selected=true, "No Runtimes available"))
    }
  }
  items
}

///|
fn selected_new_project_runtime(model : Model) -> @sdk.RuntimeSummary? {
  for item in model.runtimes {
    if item.id == model.new_project_runtime_id {
      return Some(item)
    }
  }
  None
}

///|
fn render_new_project_runtime_value(
  item : @sdk.RuntimeSummary,
) -> @rabbita.Html {
  @html.div(
    style=value_text_style() +
      [
        "min-height: 34px", "display: flex", "align-items: center", "padding: 0 10px",
        "border-radius: var(--radius-control)", "border: 1px solid var(--border-soft)",
        "background: var(--background)",
      ],
    runtime_display_label(item),
  )
}

///|
fn render_new_project_runtime_select(
  dispatch : @rabbita.Dispatch[Msg],
  model : Model,
) -> @rabbita.Html {
  let disabled = model.create_project_pending ||
    (model.runtimes_loading && model.runtimes.length() == 0)
  @html.select(
    disabled~,
    on_change=fn(value) { dispatch(NewProjectRuntimeChanged(value)) },
    style=input_style(disabled),
    render_runtime_select_options(model),
  )
}

///|
fn render_new_project_runtime_field(
  dispatch : @rabbita.Dispatch[Msg],
  model : Model,
) -> @rabbita.Html {
  @html.div(
    style=[
      "border-radius: var(--radius-control)", "background: var(--foreground-3)",
      "padding: 8px", "display: flex", "flex-direction: column", "gap: 8px",
    ],
  ) <| [
    @html.div(style=section_label_style(), "Runtime"),
    if model.runtimes.length() == 1 {
      match selected_new_project_runtime(model) {
        Some(item) => render_new_project_runtime_value(item)
        None => render_new_project_runtime_select(dispatch, model)
      }
    } else {
      render_new_project_runtime_select(dispatch, model)
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
          "border-radius: var(--radius-panel)", "box-shadow: var(--shadow)", "padding: 10px",
          "display: flex", "flex-direction: column", "gap: 8px",
        ],
      ) <| [
        @html.div(
          style=[
            "display: flex", "align-items: flex-start", "justify-content: space-between",
            "gap: 8px",
          ],
        ) <| [
          @html.div(
            style=["display: flex", "flex-direction: column", "gap: 8px"],
          ) <| [
            @html.div(style=title_text_style(), "New project"),
          ],
          @html.button(
            type_="button",
            title="Close",
            disabled=model.create_project_pending,
            on_click=dispatch(CloseNewProjectDialog),
            style=secondary_button_style(!model.create_project_pending) +
              ["width: 30px", "height: 30px", "padding: 0"],
            [project_cancel_icon()],
          ),
        ],
        @html.input(
          input_type=Text,
          value=model.new_project_name,
          placeholder="Project name",
          read_only=model.create_project_pending,
          on_input=fn(value) { dispatch(NewProjectNameChanged(value)) },
          style=input_style(model.create_project_pending) +
            ["padding: 8px 12px"],
          "",
        ),
        render_new_project_runtime_field(dispatch, model),
        @html.div(
          style=[
            "display: flex", "justify-content: flex-end", "gap: 8px", "padding-top: 4px",
          ],
        ) <| [
          @html.button(
            type_="button",
            title=if model.create_project_pending {
              "Creating"
            } else {
              "Create"
            },
            disabled=!enabled,
            on_click=dispatch(CreateProject),
            style=primary_button_style(enabled) +
              ["width: 32px", "height: 32px", "padding: 0"],
            [plus_icon()],
          ),
        ],
      ],
    ]
  }
}

///|
fn render_project_info_row(label : String, value : String) -> @rabbita.Html {
  @html.div(
    style=[
      "display: grid", "grid-template-columns: 88px minmax(0, 1fr)", "gap: 8px",
      "align-items: center",
    ],
  ) <| [
    @html.div(style=normal_text_style(), label),
    @html.div(
      style=value_text_style() +
        [
          "min-width: 0", "padding: 8px 10px", "border-radius: var(--radius-control)",
          "background: var(--foreground-3)", "overflow-wrap: anywhere",
        ],
      value,
    ),
  ]
}

///|
fn render_project_info_dialog(
  dispatch : @rabbita.Dispatch[Msg],
  model : Model,
) -> @rabbita.Html {
  if !model.project_info_open {
    @html.nothing
  } else {
    match selected_project_detail(model) {
      Some(project) =>
        @html.div(
          style=[
            "position: fixed", "inset: 0", "z-index: 100", "display: flex", "align-items: center",
            "justify-content: center", "padding: 12px", "background: rgba(15, 23, 42, 0.28)",
            "backdrop-filter: blur(10px)",
          ],
        ) <| [
          @html.div(
            style=[
              "width: min(500px, 100%)", "background: var(--surface-raised)", "border: 1px solid var(--border-soft)",
              "border-radius: var(--radius-panel)", "box-shadow: var(--shadow)",
              "padding: 10px", "display: flex", "flex-direction: column", "gap: 8px",
            ],
          ) <| [
            @html.div(
              style=[
                "display: flex", "align-items: flex-start", "justify-content: space-between",
                "gap: 8px",
              ],
            ) <| [
              @html.div(style=title_text_style(), "Project info"),
              @html.button(
                type_="button",
                title="Close",
                disabled=model.project_info_pending,
                on_click=dispatch(CloseProjectInfo),
                style=secondary_button_style(!model.project_info_pending) +
                  ["width: 30px", "height: 30px", "padding: 0"],
                [project_cancel_icon()],
              ),
            ],
            render_project_info_row("Project ID", project.id),
            render_project_info_row("Runtime", project.runtime_name),
            render_project_info_row("Runtime ID", project.runtime_id),
            render_project_info_row(
              "Image",
              match project.runtime_config {
                Some(config) => config.launcher.image
                None => "-"
              },
            ),
          ],
        ]
      None => @html.nothing
    }
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
        style=[
          "flex: 1", "min-height: 0", "display: grid", "place-items: center", "padding: 24px",
        ],
      ) <| [
        @html.div(
          style=[
            "display: flex", "flex-direction: column", "align-items: center", "gap: 10px",
            "width: min(360px, 100%)", "padding: 16px", "border-radius: var(--radius-panel)",
            "background: var(--foreground-3)", "box-shadow: var(--shadow)", "text-align: center",
          ],
        ) <| [
          @html.div(style=title_text_style(), "No project selected"),
          render_open_project_button(dispatch, "New project", false),
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
fn send_arrow_icon() -> @rabbita.Html {
  @svg.svg(
    width=18,
    height=18,
    view_box="0 0 24 24",
    style=["display: block"],
    [
      @svg.path(
        d="M12 19V5",
        fill="none",
        stroke="currentColor",
        stroke_width=2,
      ),
      @svg.path(
        d="M5 12l7-7 7 7",
        fill="none",
        stroke="currentColor",
        stroke_width=2,
      ),
    ],
  )
}

///|
fn stop_square_icon() -> @rabbita.Html {
  @svg.svg(
    width=18,
    height=18,
    view_box="0 0 24 24",
    style=["display: block"],
    [
      @svg.path(
        d="M8 8h8v8H8z",
        fill="currentColor",
        stroke="currentColor",
        stroke_width=2,
      ),
    ],
  )
}

///|
fn composer_keydown_attrs(
  dispatch : @rabbita.Dispatch[Msg],
  send_enabled : Bool,
) -> @html.Attrs {
  @html.Attrs::build().on_keydown(fn(event) {
    if send_enabled &&
      event.key() == "Enter" &&
      !event.shift_key() &&
      !event.is_composing() &&
      !event.repeat() {
      event.prevent_default()
      dispatch(SendDraft)
    } else {
      @rabbita.none
    }
  })
}

///|
fn preview_open_target(model : Model) -> @sdk.PreviewTarget? {
  match model.project_detail {
    Some(project) =>
      match project.preview {
        Some(preview) if preview.healthy => Some(preview)
        _ => None
      }
    None => None
  }
}

///|
fn render_preview_button(model : Model) -> @rabbita.Html {
  match preview_open_target(model) {
    Some(preview) =>
      @html.a(
        href=preview.url,
        target=Blank,
        rel="noopener noreferrer",
        title="Open preview in a new tab",
        style=secondary_button_style(true) +
          [
            "text-decoration: none", "height: 28px", "padding: 0 8px", "gap: 4px",
          ],
        [external_link_icon(), @html.span("Preview")],
      )
    None =>
      @html.button(
        type_="button",
        title="Preview is not available yet",
        disabled=true,
        style=secondary_button_style(false) +
          ["height: 28px", "padding: 0 8px", "gap: 4px"],
        [external_link_icon(), @html.span("Preview")],
      )
  }
}

///|
fn render_workspace_panel(
  dispatch : @rabbita.Dispatch[Msg],
  model : Model,
) -> @rabbita.Html {
  let send_enabled = can_send(model)
  let running_run = active_run(model)
  let stopping = match running_run {
    Some(run) => model.stopping_run_id == Some(run.run_id)
    None => false
  }
  let action_enabled = match running_run {
    Some(_) => !stopping
    None => send_enabled
  }
  let action_style = match running_run {
    Some(_) =>
      button_style("var(--danger)", "var(--on-action)", action_enabled) +
      ["width: 36px", "height: 36px", "padding: 0", "color: var(--on-action)"]
    None =>
      primary_button_style(send_enabled) +
      ["width: 36px", "height: 36px", "padding: 0", "color: var(--on-action)"]
  }
  let action_title = match running_run {
    Some(_) => "Stop"
    None => "Send"
  }
  let action_click = match running_run {
    Some(run) => dispatch(StopRun(run.project_id, run.run_id))
    None => dispatch(SendDraft)
  }
  let action_icon = match running_run {
    Some(_) => stop_square_icon()
    None => send_arrow_icon()
  }
  let composer_placeholder = if model.selected_project_id is Some(_) {
    "What would you like to build?"
  } else {
    "Select a project"
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
        "height: 50px", "padding: 0 12px", "border-bottom: 1px solid var(--border-soft)",
        "display: flex", "justify-content: space-between", "align-items: center",
        "gap: 8px", "flex-wrap: wrap",
      ],
      [
        @html.div(
          style=[
            "display: flex", "flex-direction: column", "gap: 8px", "min-width: 0",
          ],
          [render_project_title(model)],
        ),
        @html.div(
          style=[
            "display: flex", "align-items: center", "gap: 8px", "flex-wrap: wrap",
            "justify-content: flex-end",
          ],
          [
            render_preview_button(model),
            maybe_status_badge(active_project_status(model)),
          ],
        ),
      ],
    ),
    @html.div(
      style=[
        "padding: 8px 12px 0", "display: flex", "flex-direction: column", "gap: 6px",
      ],
      [
        render_notice_card(model.notice, "var(--warning-soft)"),
        render_run_failure_card(model),
      ],
    ),
    @html.div(
      style=[
        "flex: 1", "min-height: 0", "padding: 8px 12px", "display: flex", "flex-direction: column",
        "gap: 8px", "overflow-y: auto",
      ],
      messages,
    ),
    if model.selected_project_id is None {
      @html.nothing
    } else {
      @html.div(
        style=[
          "padding: 8px 12px 12px", "border-top: 0", "display: flex", "flex-direction: column",
          "gap: 8px",
        ],
        [
          @html.textarea(
            rows=6,
            value=model.draft,
            disabled=active_run(model) is Some(_),
            placeholder=composer_placeholder,
            on_input=fn(value) { dispatch(DraftChanged(value)) },
            attrs=composer_keydown_attrs(dispatch, send_enabled),
            style=input_style(active_run(model) is Some(_)) +
              [
                "min-height: 112px", "resize: vertical", "box-shadow: var(--shadow)",
                "border-radius: 12px",
              ],
            "",
          ),
          @html.div(
            style=[
              "display: flex", "justify-content: flex-end", "align-items: center",
              "gap: 8px", "flex-wrap: wrap",
            ],
            [
              @html.button(
                type_="button",
                title=action_title,
                disabled=!action_enabled,
                on_click=action_click,
                style=action_style,
                [action_icon],
              ),
            ],
          ),
        ],
      )
    },
  ]
}
