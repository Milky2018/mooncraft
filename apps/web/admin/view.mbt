///|
fn count_badge(value : Int) -> @rabbita.Html {
  @html.strong(style=value_style(), value.to_string())
}

///|
fn nav_button(
  dispatch : @rabbita.Dispatch[AdminMsg],
  model : AdminModel,
  view : AdminView,
  label : String,
  count : Int,
) -> @rabbita.Html {
  let active = model.view == view
  let background = if active { "var(--foreground-10)" } else { "transparent" }
  let border = if active {
    "3px solid var(--accent)"
  } else {
    "3px solid transparent"
  }
  @html.button(
    type_="button",
    on_click=dispatch(ShowView(view)),
    style=normal_style() +
      [
        "width: 100%",
        "border: 0",
        "border-left: " + border,
        "border-radius: var(--radius-control)",
        "background: " + background,
        "padding: 8px",
        "display: flex",
        "align-items: center",
        "justify-content: space-between",
        "cursor: pointer",
        "color: var(--text-1)",
      ],
    [@html.span(label), count_badge(count)],
  )
}

///|
fn sidebar(
  dispatch : @rabbita.Dispatch[AdminMsg],
  model : AdminModel,
) -> @rabbita.Html {
  @html.aside(style=sidebar_style(), [
    @html.h1(style=title_style() + ["margin: 0", "padding: 2px 4px"], "Admin"),
    @html.nav(style=["display: flex", "flex-direction: column", "gap: 4px"], [
      nav_button(dispatch, model, Users, "Users", model.users.length()),
      nav_button(dispatch, model, Keys, "OpenRouter Keys", model.keys.length()),
      nav_button(dispatch, model, Runtimes, "Runtimes", model.runtimes.length()),
      nav_button(
        dispatch,
        model,
        Models,
        "Models",
        model.ai_config.allowed_models.length(),
      ),
    ]),
    @html.div(style=["flex: 1"], ""),
    @html.div(style=["display: flex", "gap: 8px"], [
      @html.button(
        type_="button",
        title="Refresh",
        on_click=dispatch(Refresh),
        style=icon_button_style(true),
        [refresh_icon()],
      ),
      @html.button(
        type_="button",
        title="Log out",
        on_click=dispatch(Logout),
        style=danger_button_style(true) +
          ["width: 28px", "height: 28px", "padding: 0"],
        [logout_icon()],
      ),
    ]),
  ])
}

///|
fn section_head(
  title : String,
  badge : String,
  action : @rabbita.Html,
) -> @rabbita.Html {
  @html.div(
    style=[
      "display: flex", "align-items: center", "justify-content: space-between", "gap: 8px",
      "padding: 12px",
    ],
    [
      @html.div(style=["display: flex", "align-items: center", "gap: 8px"], [
        @html.h2(style=title_style() + ["margin: 0"], title),
        @html.span(style=badge_style(""), badge),
      ]),
      action,
    ],
  )
}

///|
fn notice_view(model : AdminModel) -> @rabbita.Html {
  match model.notice {
    Some(text) =>
      @html.div(
        style=normal_style() +
          [
            "padding: 10px 12px", "border-radius: var(--radius-control)", "background: var(--foreground-5)",
            "color: var(--text-1)",
          ],
        text,
      )
    None =>
      if model.loading {
        @html.div(
          style=normal_style() +
            [
              "padding: 10px 12px", "border-radius: var(--radius-control)", "background: var(--foreground-5)",
              "color: var(--text-2)",
            ],
          "Loading admin data...",
        )
      } else {
        @html.nothing
      }
  }
}

///|
fn empty_row(colspan : Int, text : String) -> @rabbita.Html {
  @html.tr([
    @html.td(
      colspan~,
      style=td_style() +
        ["text-align: center", "color: var(--text-3)", "padding: 20px"],
      text,
    ),
  ])
}

///|
fn project_status_text(project : @sdk.AdminProjectSummary) -> String {
  let phase = project.project.current_run_phase.label()
  project.project.status.label() +
  (if phase == "" { "" } else { " / " + phase })
}

///|
fn expanded_user_projects_row(model : AdminModel) -> @rabbita.Html {
  let rows = if model.user_projects_loading {
    [empty_row(6, "Loading projects...")]
  } else if model.expanded_user_projects.length() == 0 {
    [empty_row(6, "No projects.")]
  } else {
    model.expanded_user_projects.map(fn(project) {
      @html.tr([
        @html.td(style=td_style(), [
          @html.div(style=value_style(), project.project.display_name),
          @html.div(style=normal_style(), project.project.id),
        ]),
        @html.td(style=td_style(), project.project.agent_cli),
        @html.td(style=td_style(), project.project.model),
        @html.td(style=td_style(), project_status_text(project)),
        @html.td(style=numeric_td_style(), project.run_count.to_string()),
        @html.td(style=td_style(), [
          @html.a(
            href=@sdk.admin_project_path(project.project.id),
            target=Blank,
            rel="noreferrer",
            style=button_style(true) + ["text-decoration: none"],
            "Diagnostics",
          ),
        ]),
      ])
    })
  }
  @html.tr([
    @html.td(
      colspan=5,
      style=["padding: 0", "border-bottom: 1px solid var(--border)"],
      [
        @html.div(style=["padding: 8px", "background: var(--foreground-3)"], [
          @html.table(style=table_style(), [
            @html.thead([
              @html.tr([
                @html.th(style=th_style(), "Project"),
                @html.th(style=th_style(), "Agent"),
                @html.th(style=th_style(), "Model"),
                @html.th(style=th_style(), "Status"),
                @html.th(style=th_style() + ["text-align: right"], "Runs"),
                @html.th(style=th_style(), "Actions"),
              ]),
            ]),
            @html.tbody(rows),
          ]),
        ]),
      ],
    ),
  ])
}

///|
fn user_rows(
  dispatch : @rabbita.Dispatch[AdminMsg],
  model : AdminModel,
  item : @sdk.AdminUserSummary,
) -> Array[@rabbita.Html] {
  let user = item.user
  let expanded = model.expanded_user_id == Some(user.id)
  let rows = [
    @html.tr([
      @html.td(style=td_style(), [
        @html.button(
          type_="button",
          on_click=dispatch(ToggleUser(user.id)),
          style=value_style() +
            [
              "border: 0", "background: transparent", "padding: 0", "cursor: pointer",
              "text-align: left",
            ],
          [
            @html.div(style=value_style(), user.display_name),
            @html.div(style=normal_style(), user.email),
          ],
        ),
      ]),
      @html.td(style=td_style(), @html.code(user.id)),
      @html.td(style=numeric_td_style(), item.project_count.to_string()),
      @html.td(style=numeric_td_style(), item.running_project_count.to_string()),
      @html.td(
        style=td_style() + ["color: var(--text-2)"],
        item.latest_project_updated_at.unwrap_or("-"),
      ),
    ]),
  ]
  if expanded {
    rows + [expanded_user_projects_row(model)]
  } else {
    rows
  }
}

///|
fn users_view(
  dispatch : @rabbita.Dispatch[AdminMsg],
  model : AdminModel,
) -> @rabbita.Html {
  let rows = []
  for item in model.users {
    for row in user_rows(dispatch, model, item) {
      rows.push(row)
    }
  }
  @html.section(style=card_style(), [
    section_head("Users", "\{model.users.length()} users", @html.nothing),
    @html.table(style=table_style(), [
      @html.thead([
        @html.tr([
          @html.th(style=th_style(), "User"),
          @html.th(style=th_style(), "ID"),
          @html.th(style=th_style() + ["text-align: right"], "Projects"),
          @html.th(style=th_style() + ["text-align: right"], "Running"),
          @html.th(style=th_style(), "Latest project"),
        ]),
      ]),
      @html.tbody(
        if rows.length() == 0 {
          [empty_row(5, "No users.")]
        } else {
          rows
        },
      ),
    ]),
  ])
}

///|
fn key_form_row(
  dispatch : @rabbita.Dispatch[AdminMsg],
  model : AdminModel,
) -> @rabbita.Html {
  @html.tr([
    @html.td(
      style=td_style(),
      @html.input(
        input_type=Text,
        value=model.key_label,
        placeholder="Label",
        on_input=fn(value) { dispatch(KeyLabelChanged(value)) },
        style=input_style(),
        "",
      ),
    ),
    @html.td(
      style=td_style(),
      @html.input(
        input_type=Text,
        value=model.key_secret,
        placeholder="OpenRouter API key",
        on_input=fn(value) { dispatch(KeySecretChanged(value)) },
        style=input_style(),
        "",
      ),
    ),
    @html.td(
      style=td_style(),
      @html.span(style=badge_style("success"), "active"),
    ),
    @html.td(
      style=td_style(),
      @html.input(
        input_type=Text,
        value=model.key_priority,
        placeholder="Priority",
        on_input=fn(value) { dispatch(KeyPriorityChanged(value)) },
        style=input_style() + ["max-width: 90px"],
        "",
      ),
    ),
    @html.td(style=td_style(), "-"),
    @html.td(style=td_style(), "-"),
    @html.td(style=td_style(), [
      @html.button(
        type_="button",
        on_click=dispatch(SaveCreateKey),
        style=icon_button_style(
          model.key_label.trim() != "" && model.key_secret.trim() != "",
        ),
        disabled=model.key_label.trim() == "" || model.key_secret.trim() == "",
        "+",
      ),
      @html.button(
        type_="button",
        on_click=dispatch(CancelCreateKey),
        style=icon_button_style(true) + ["margin-left: 4px"],
        "x",
      ),
    ]),
  ])
}

///|
fn key_status_options(selected : String) -> Array[@rabbita.Html] {
  ["active", "disabled"].map(fn(status) {
    @html.option(value=status, selected=status == selected, status)
  })
}

///|
fn key_row(
  dispatch : @rabbita.Dispatch[AdminMsg],
  model : AdminModel,
  key : @sdk.AdminAiKeySummary,
) -> @rabbita.Html {
  let editing = model.editing_key_id == Some(key.id)
  if editing {
    return @html.tr([
      @html.td(
        style=td_style(),
        @html.input(
          input_type=Text,
          value=model.editing_key_label,
          on_input=fn(value) { dispatch(EditKeyLabelChanged(value)) },
          style=input_style(),
          "",
        ),
      ),
      @html.td(
        style=td_style(),
        @html.input(
          input_type=Text,
          value=model.editing_key_secret,
          placeholder="Leave blank to keep saved key",
          on_input=fn(value) { dispatch(EditKeySecretChanged(value)) },
          style=input_style(),
          "",
        ),
      ),
      @html.td(
        style=td_style(),
        @html.select(
          on_change=fn(value) { dispatch(EditKeyStatusChanged(value)) },
          style=input_style(),
          key_status_options(model.editing_key_status),
        ),
      ),
      @html.td(
        style=td_style(),
        @html.input(
          input_type=Text,
          value=model.editing_key_priority,
          on_input=fn(value) { dispatch(EditKeyPriorityChanged(value)) },
          style=input_style() + ["max-width: 90px"],
          "",
        ),
      ),
      @html.td(style=td_style(), key.last_used_at.unwrap_or("-")),
      @html.td(style=td_style(), key.last_error.unwrap_or("-")),
      @html.td(style=td_style(), [
        @html.button(
          type_="button",
          on_click=dispatch(SaveEditKey(key.id)),
          style=icon_button_style(true),
          "+",
        ),
        @html.button(
          type_="button",
          on_click=dispatch(CancelEditKey),
          style=icon_button_style(true) + ["margin-left: 4px"],
          "x",
        ),
      ]),
    ])
  }
  let confirming = model.confirming_key_delete_id == Some(key.id)
  @html.tr([
    @html.td(style=td_style(), [
      @html.div(style=value_style(), key.label),
      @html.div(style=normal_style(), key.provider),
    ]),
    @html.td(style=td_style(), @html.code(key.key_hint)),
    @html.td(
      style=td_style(),
      @html.span(
        style=badge_style(if key.status == "active" { "success" } else { "" }),
        key.status,
      ),
    ),
    @html.td(style=numeric_td_style(), key.priority.to_string()),
    @html.td(style=td_style(), key.last_used_at.unwrap_or("-")),
    @html.td(style=td_style(), key.last_error.unwrap_or("-")),
    @html.td(style=td_style(), [
      @html.button(
        type_="button",
        on_click=dispatch(StartEditKey(key.id)),
        style=button_style(true),
        "Edit",
      ),
      @html.button(
        type_="button",
        on_click=dispatch(RequestDeleteKey(key.id)),
        style=danger_button_style(true) + ["margin-left: 4px"],
        if confirming {
          "Confirm"
        } else {
          "Delete"
        },
      ),
    ]),
  ])
}

///|
fn keys_view(
  dispatch : @rabbita.Dispatch[AdminMsg],
  model : AdminModel,
) -> @rabbita.Html {
  let rows = model.keys.map(fn(key) { key_row(dispatch, model, key) })
  let body_rows = if model.creating_key {
    [key_form_row(dispatch, model)] + rows
  } else if rows.length() == 0 {
    [empty_row(7, "No keys.")]
  } else {
    rows
  }
  @html.section(style=card_style(), [
    section_head(
      "OpenRouter Keys",
      "\{model.keys.length()} keys",
      @html.button(
        type_="button",
        title="Add key",
        on_click=dispatch(OpenCreateKey),
        style=icon_button_style(true),
        "+",
      ),
    ),
    @html.table(style=table_style(), [
      @html.thead([
        @html.tr([
          @html.th(style=th_style(), "Label"),
          @html.th(style=th_style(), "Key hint"),
          @html.th(style=th_style(), "Status"),
          @html.th(style=th_style() + ["text-align: right"], "Priority"),
          @html.th(style=th_style(), "Last used"),
          @html.th(style=th_style(), "Last error"),
          @html.th(style=th_style(), "Actions"),
        ]),
      ]),
      @html.tbody(body_rows),
    ]),
  ])
}

///|
fn runtime_status_label(runtime : @sdk.RuntimeDetail) -> String {
  (if runtime.enabled { "enabled" } else { "disabled" }) +
  (if runtime.is_default { " / default" } else { "" })
}

///|
fn runtime_row(
  dispatch : @rabbita.Dispatch[AdminMsg],
  model : AdminModel,
  runtime : @sdk.RuntimeDetail,
) -> @rabbita.Html {
  if model.editing_runtime_id == Some(runtime.id) {
    @html.tr([
      @html.td(style=td_style(), [
        @html.input(
          input_type=Text,
          value=model.editing_runtime_name,
          on_input=fn(value) { dispatch(RuntimeNameChanged(value)) },
          style=input_style(),
          "",
        ),
      ]),
      @html.td(style=td_style(), @html.code(runtime.id)),
      @html.td(style=td_style(), [
        @html.select(
          on_change=fn(value) { dispatch(RuntimeEnabledChanged(value)) },
          style=input_style(),
          [
            @html.option(
              value="true",
              selected=model.editing_runtime_enabled == "true",
              "enabled",
            ),
            @html.option(
              value="false",
              selected=model.editing_runtime_enabled == "false",
              "disabled",
            ),
          ],
        ),
        @html.select(
          on_change=fn(value) { dispatch(RuntimeDefaultChanged(value)) },
          style=input_style() + ["margin-top: 6px"],
          [
            @html.option(
              value="false",
              selected=model.editing_runtime_default == "false",
              "not default",
            ),
            @html.option(
              value="true",
              selected=model.editing_runtime_default == "true",
              "default",
            ),
          ],
        ),
      ]),
      @html.td(style=td_style(), [
        @html.textarea(
          rows=8,
          value=model.editing_runtime_spec_json,
          on_input=fn(value) { dispatch(RuntimeSpecChanged(value)) },
          style=input_style() +
            ["font-family: ui-monospace, SFMono-Regular, Menlo, monospace"],
          "",
        ),
      ]),
      @html.td(style=td_style(), [
        @html.button(
          type_="button",
          on_click=dispatch(SaveRuntime(runtime.id)),
          style=button_style(true),
          "Save",
        ),
        @html.button(
          type_="button",
          on_click=dispatch(CancelEditRuntime),
          style=button_style(true) + ["margin-left: 4px"],
          "Cancel",
        ),
      ]),
    ])
  } else {
    @html.tr([
      @html.td(style=td_style(), @html.strong(runtime.name)),
      @html.td(style=td_style(), @html.code(runtime.id)),
      @html.td(style=td_style(), runtime_status_label(runtime)),
      @html.td(style=td_style(), [
        @html.div(style=normal_style(), runtime.spec.agent),
        @html.code(runtime.spec.model),
      ]),
      @html.td(style=td_style(), [
        @html.button(
          type_="button",
          on_click=dispatch(StartEditRuntime(runtime.id)),
          style=button_style(true),
          "Edit",
        ),
      ]),
    ])
  }
}

///|
fn runtimes_view(
  dispatch : @rabbita.Dispatch[AdminMsg],
  model : AdminModel,
) -> @rabbita.Html {
  let rows = if model.runtimes.length() == 0 {
    [empty_row(5, "No Runtimes.")]
  } else {
    model.runtimes.map(fn(runtime) { runtime_row(dispatch, model, runtime) })
  }
  @html.section(style=card_style(), [
    section_head(
      "Runtimes",
      "\{model.runtimes.length()} configured",
      @html.nothing,
    ),
    @html.table(style=table_style(), [
      @html.thead([
        @html.tr([
          @html.th(style=th_style(), "Name"),
          @html.th(style=th_style(), "ID"),
          @html.th(style=th_style(), "Status"),
          @html.th(style=th_style(), "Agent / model"),
          @html.th(style=th_style(), "Actions"),
        ]),
      ]),
      @html.tbody(rows),
    ]),
  ])
}

///|
fn format_context(value : Int) -> String {
  if value >= 1000000 {
    "\{value / 1000000}M"
  } else if value >= 1000 {
    "\{value / 1000}K"
  } else if value > 0 {
    value.to_string()
  } else {
    "-"
  }
}

///|
fn token_price(value : String) -> String {
  js_format_token_price(value)
}

///|
extern "js" fn js_format_token_price(value : String) -> String =
  #| (value) => {
  #|   const number = Number(value || 0);
  #|   if (!Number.isFinite(number) || number <= 0) return "-";
  #|   const perMillion = number * 1000000;
  #|   const amount = perMillion >= 1 ? perMillion.toFixed(2) : perMillion.toFixed(4);
  #|   return `$${amount.replace(/\\.00$/, "")} / 1M`;
  #| }

///|
fn allowed_model_row(
  dispatch : @rabbita.Dispatch[AdminMsg],
  model : AdminModel,
  id : String,
) -> @rabbita.Html {
  let item = model_by_id(model.catalog, id)
  let is_default = id == model.ai_config.default_model
  let confirming = model.confirming_model_remove_id == Some(id)
  @html.tr([
    @html.td(style=td_style(), @html.strong(model_label(model.catalog, id))),
    @html.td(style=td_style(), @html.code(id)),
    @html.td(
      style=td_style(),
      if is_default {
        @html.span(style=badge_style("success"), "default")
      } else {
        @html.span(style=normal_style(), "-")
      },
    ),
    @html.td(
      style=numeric_td_style(),
      match item {
        Some(value) => format_context(value.context_length)
        None => "-"
      },
    ),
    @html.td(
      style=numeric_td_style(),
      match item {
        Some(value) => token_price(value.prompt_price)
        None => "-"
      },
    ),
    @html.td(
      style=numeric_td_style(),
      match item {
        Some(value) => token_price(value.completion_price)
        None => "-"
      },
    ),
    @html.td(style=td_style(), [
      if is_default {
        @html.nothing
      } else {
        @html.button(
          type_="button",
          on_click=dispatch(SetDefaultModel(id)),
          style=button_style(true),
          "Default",
        )
      },
      @html.button(
        type_="button",
        on_click=dispatch(RequestRemoveModel(id)),
        style=danger_button_style(true) + ["margin-left: 4px"],
        if confirming {
          "Confirm"
        } else {
          "Remove"
        },
      ),
    ]),
  ])
}

///|
fn catalog_picker_rows(
  dispatch : @rabbita.Dispatch[AdminMsg],
  model : AdminModel,
) -> Array[@rabbita.Html] {
  let rows = []
  let items = filtered_catalog(model)
  let mut current_provider = ""
  for item in items {
    let provider = model_provider(item.id)
    if provider != current_provider {
      current_provider = provider
      rows.push(
        @html.tr([
          @html.td(
            colspan=7,
            style=td_style() +
              ["background: var(--foreground-5)", "color: var(--text-2)"],
            provider_label(provider),
          ),
        ]),
      )
    }
    rows.push(
      @html.tr([
        @html.td(style=td_style(), [
          @html.div(
            style=["display: flex", "gap: 6px", "align-items: center"],
            [
              @html.strong(item.name),
              if recommended_model(item) {
                @html.span(style=badge_style("success"), "recommended")
              } else {
                @html.nothing
              },
            ],
          ),
          @html.code(style=normal_style(), item.id),
        ]),
        @html.td(style=td_style(), provider_label(provider)),
        @html.td(style=td_style(), "-"),
        @html.td(style=numeric_td_style(), format_context(item.context_length)),
        @html.td(style=numeric_td_style(), token_price(item.prompt_price)),
        @html.td(style=numeric_td_style(), token_price(item.completion_price)),
        @html.td(
          style=td_style(),
          @html.button(
            type_="button",
            on_click=dispatch(AddModel(item.id)),
            style=icon_button_style(true),
            "+",
          ),
        ),
      ]),
    )
  }
  if rows.length() == 0 {
    rows.push(empty_row(7, "No matching models."))
  }
  rows
}

///|
fn model_create_row(
  dispatch : @rabbita.Dispatch[AdminMsg],
  model : AdminModel,
) -> @rabbita.Html {
  let visible = filtered_catalog(model).length()
  let total = available_model_count(model)
  @html.tr([
    @html.td(
      colspan=7,
      style=["padding: 0", "border-bottom: 1px solid var(--border)"],
      [
        @html.div(
          style=[
            "display: flex", "gap: 8px", "align-items: center", "justify-content: space-between",
            "padding: 10px", "background: var(--foreground-3)", "border-bottom: 1px solid var(--border)",
          ],
          [
            @html.input(
              input_type=Text,
              value=model.model_search,
              placeholder="Search models",
              on_input=fn(value) { dispatch(ModelSearchChanged(value)) },
              style=input_style() + ["max-width: 420px"],
              "",
            ),
            @html.div(
              style=["display: flex", "gap: 8px", "align-items: center"],
              [
                @html.button(
                  type_="button",
                  on_click=dispatch(SetModelCatalogMode(Recommended)),
                  style=button_style(true) +
                    [
                      if model.model_catalog_mode is Recommended {
                        "background: var(--foreground-10)"
                      } else {
                        "background: var(--background)"
                      },
                    ],
                  "Recommended",
                ),
                @html.button(
                  type_="button",
                  on_click=dispatch(SetModelCatalogMode(All)),
                  style=button_style(true) +
                    [
                      if model.model_catalog_mode is All {
                        "background: var(--foreground-10)"
                      } else {
                        "background: var(--background)"
                      },
                    ],
                  "All",
                ),
                @html.span(style=badge_style(""), "\{visible} / \{total}"),
                @html.button(
                  type_="button",
                  on_click=dispatch(CancelCreateModel),
                  style=icon_button_style(true),
                  "x",
                ),
              ],
            ),
          ],
        ),
        @html.table(
          style=table_style(),
          @html.tbody(catalog_picker_rows(dispatch, model)),
        ),
      ],
    ),
  ])
}

///|
fn models_view(
  dispatch : @rabbita.Dispatch[AdminMsg],
  model : AdminModel,
) -> @rabbita.Html {
  let rows = model.ai_config.allowed_models.map(fn(id) {
    allowed_model_row(dispatch, model, id)
  })
  let body_rows = if model.creating_model {
    [model_create_row(dispatch, model)] + rows
  } else if rows.length() == 0 {
    [empty_row(7, "No models.")]
  } else {
    rows
  }
  @html.section(style=card_style(), [
    section_head(
      "Models",
      "\{model.ai_config.allowed_models.length()} models",
      @html.button(
        type_="button",
        title="Add model",
        on_click=dispatch(OpenCreateModel),
        style=icon_button_style(true),
        "+",
      ),
    ),
    match model.models_error {
      Some(error) =>
        @html.div(
          style=normal_style() +
            [
              "margin: 0 12px 10px", "padding: 10px", "border-radius: var(--radius-control)",
              "background: oklch(from var(--destructive) l c h / 0.10)", "color: var(--destructive)",
            ],
          error,
        )
      None => @html.nothing
    },
    @html.table(style=table_style(), [
      @html.thead([
        @html.tr([
          @html.th(style=th_style(), "Model"),
          @html.th(style=th_style(), "ID"),
          @html.th(style=th_style(), "Default"),
          @html.th(style=th_style() + ["text-align: right"], "Context"),
          @html.th(style=th_style() + ["text-align: right"], "Input"),
          @html.th(style=th_style() + ["text-align: right"], "Output"),
          @html.th(style=th_style(), "Actions"),
        ]),
      ]),
      @html.tbody(body_rows),
    ]),
  ])
}

///|
fn active_view(
  dispatch : @rabbita.Dispatch[AdminMsg],
  model : AdminModel,
) -> @rabbita.Html {
  match model.view {
    Users => users_view(dispatch, model)
    Keys => keys_view(dispatch, model)
    Runtimes => runtimes_view(dispatch, model)
    Models => models_view(dispatch, model)
  }
}

///|
fn view(
  dispatch : @rabbita.Dispatch[AdminMsg],
  model : AdminModel,
) -> @rabbita.Html {
  @html.div(style=root_style(), [
    @html.div(style=shell_style(), [
      sidebar(dispatch, model),
      @html.main_(style=content_style(), [
        notice_view(model),
        active_view(dispatch, model),
      ]),
    ]),
  ])
}
