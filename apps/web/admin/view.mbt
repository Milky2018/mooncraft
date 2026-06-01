///|
fn count_badge(value : Int) -> @rabbita.Html {
  @html.strong(style=["font: inherit", "color: inherit"], value.to_string())
}

///|
fn table_wrap(table : @rabbita.Html) -> @rabbita.Html {
  @html.div(style=table_wrap_style(), [table])
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
  let foreground = if active { "var(--text-1)" } else { "var(--text-2)" }
  let stripe = if active { "var(--accent)" } else { "transparent" }
  @html.button(
    type_="button",
    on_click=dispatch(ShowView(view)),
    style=normal_style() +
      [
        "width: 100%",
        "min-height: 34px",
        "padding: 0 8px",
        "border: 0",
        "border-radius: 4px",
        "background: \{background}",
        "display: flex",
        "align-items: center",
        "justify-content: space-between",
        "text-align: left",
        "cursor: pointer",
        "color: \{foreground}",
      ],
    [
      @html.span(
        style=[
          "width: 2px",
          "height: 18px",
          "border-radius: 2px",
          "background: \{stripe}",
          "margin-right: 7px",
          "flex: 0 0 auto",
        ],
        "",
      ),
      @html.span(style=["flex: 1"], label),
      count_badge(count),
    ],
  )
}

///|
fn sidebar(
  dispatch : @rabbita.Dispatch[AdminMsg],
  model : AdminModel,
) -> @rabbita.Html {
  @html.aside(style=sidebar_style(), [
    @html.h1(
      style=title_style() + ["margin: 0", "padding: 2px 4px 10px"],
      "Admin",
    ),
    @html.nav(style=["display: flex", "flex-direction: column", "gap: 4px"], [
      nav_button(dispatch, model, Users, "Users", model.users.items.length()),
      nav_button(
        dispatch,
        model,
        Secrets,
        "Secrets",
        model.secrets.items.length(),
      ),
      nav_button(
        dispatch,
        model,
        Runtimes,
        "Runtimes",
        model.runtimes.items.length(),
      ),
    ]),
    @html.div(
      style=[
        "margin-top: auto", "padding: 10px 0 0", "border-top: 1px solid var(--border)",
        "display: flex", "align-items: center", "justify-content: space-between",
        "gap: 6px",
      ],
      [
        @html.button(
          type_="button",
          title="Refresh",
          on_click=dispatch(Refresh),
          style=icon_button_style(true) +
            [
              "background: oklch(from var(--success) l c h / 0.12)", "color: var(--success)",
            ],
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
      ],
    ),
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
fn action_menu_key(kind : String, id : String) -> String {
  "\{kind}:\{id}"
}

///|
fn action_menu_button(
  dispatch : @rabbita.Dispatch[AdminMsg],
  model : AdminModel,
  key : String,
  title : String,
) -> @rabbita.Html {
  @html.button(
    type_="button",
    title~,
    on_click=dispatch(ToggleActionMenu(key)),
    style=dots_button_style(model.active_action_menu == Some(key)),
    [more_icon()],
  )
}

///|
fn action_menu_item(
  dispatch : @rabbita.Dispatch[AdminMsg],
  msg : AdminMsg,
  title : String,
  label : String,
  danger : Bool,
  confirming : Bool,
) -> @rabbita.Html {
  @html.button(
    type_="button",
    title~,
    on_click=dispatch(msg),
    style=menu_item_style(danger, confirming),
    label,
  )
}

///|
fn action_menu(
  model : AdminModel,
  key : String,
  items : Array[@rabbita.Html],
) -> @rabbita.Html {
  @html.div(
    style=action_menu_style(model.active_action_menu == Some(key)),
    items,
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
  match project.project.activity {
    Some(activity) =>
      match activity.message {
        Some(message) => {
          let text = @sdk.run_event_display_text(
            activity.message_code.unwrap_or(""),
            message,
          )
          "Processing / \{text}"
        }
        None => {
          let suffix = if activity.phase is NoPhase {
            ""
          } else {
            " / \{activity.phase.label()}"
          }
          "Processing\{suffix}"
        }
      }
    None => project.project.status.label()
  }
}

///|
fn expanded_user_projects_row(model : AdminModel) -> @rabbita.Html {
  let rows = if model.users.projects_loading {
    [empty_row(5, "Loading projects...")]
  } else if model.users.expanded_projects.length() == 0 {
    [empty_row(5, "No projects.")]
  } else {
    model.users.expanded_projects.map(fn(project) {
      @html.tr([
        @html.td(style=td_style(), [
          @html.div(style=value_style(), project.project.display_name),
          @html.div(style=normal_style(), project.project.id),
        ]),
        @html.td(style=td_style(), [
          @html.div(style=value_style(), project.project.runtime_name),
          @html.div(style=normal_style(), project.project.runtime_id),
        ]),
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
          table_wrap(
            @html.table(style=table_style(), [
              @html.thead([
                @html.tr([
                  @html.th(style=th_style(), "Project"),
                  @html.th(style=th_style(), "Runtime"),
                  @html.th(style=th_style(), "Status"),
                  @html.th(style=th_style() + ["text-align: right"], "Runs"),
                  @html.th(style=th_style(), "Actions"),
                ]),
              ]),
              @html.tbody(rows),
            ]),
          ),
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
  let expanded = model.users.expanded_user_id == Some(user.id)
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
  for item in model.users.items {
    for row in user_rows(dispatch, model, item) {
      rows.push(row)
    }
  }
  @html.section(style=card_style(), [
    section_head("Users", "\{model.users.items.length()} users", @html.nothing),
    table_wrap(
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
    ),
  ])
}

///|
fn secret_form_row(
  dispatch : @rabbita.Dispatch[AdminMsg],
  model : AdminModel,
) -> @rabbita.Html {
  let create = model.secrets.create.unwrap_or({ name: "", value: "" })
  @html.tr([
    @html.td(
      style=td_style(),
      @html.input(
        input_type=Text,
        value=create.name,
        placeholder="Secret name",
        on_input=fn(value) { dispatch(SecretNameChanged(value)) },
        style=input_style(),
        "",
      ),
    ),
    @html.td(
      style=td_style(),
      @html.textarea(
        rows=4,
        value=create.value,
        placeholder="Paste secret value",
        on_input=fn(value) { dispatch(SecretValueChanged(value)) },
        style=input_style() +
          ["font-family: ui-monospace, SFMono-Regular, Menlo, monospace"],
        "",
      ),
    ),
    @html.td(style=td_style(), "-"),
    @html.td(style=actions_td_style(), [
      @html.button(
        type_="button",
        on_click=dispatch(SaveCreateSecret),
        style=icon_button_style(
          create.name.trim() != "" && create.value.trim() != "",
        ),
        disabled=create.name.trim() == "" || create.value.trim() == "",
        [check_icon()],
      ),
      @html.button(
        type_="button",
        on_click=dispatch(CancelCreateSecret),
        style=icon_button_style(true) + ["margin-left: 4px"],
        [x_icon()],
      ),
    ]),
  ])
}

///|
fn secret_row(
  dispatch : @rabbita.Dispatch[AdminMsg],
  model : AdminModel,
  secret : @sdk.AdminSecretSummary,
) -> @rabbita.Html {
  if model.secrets.edit.map(fn(edit) { edit.id }) == Some(secret.id) {
    let edit = model.secrets.edit.unwrap_or({
      id: secret.id,
      name: secret.name,
      value: "",
    })
    return @html.tr([
      @html.td(
        style=td_style(),
        @html.input(
          input_type=Text,
          value=edit.name,
          on_input=fn(value) { dispatch(EditSecretNameChanged(value)) },
          style=input_style(),
          "",
        ),
      ),
      @html.td(
        style=td_style(),
        @html.textarea(
          rows=4,
          value=edit.value,
          placeholder="Leave blank to keep saved value",
          on_input=fn(value) { dispatch(EditSecretValueChanged(value)) },
          style=input_style() +
            ["font-family: ui-monospace, SFMono-Regular, Menlo, monospace"],
          "",
        ),
      ),
      @html.td(style=td_style(), secret.updated_at),
      @html.td(style=actions_td_style(), [
        @html.button(
          type_="button",
          on_click=dispatch(SaveEditSecret(secret.id)),
          style=icon_button_style(true),
          [check_icon()],
        ),
        @html.button(
          type_="button",
          on_click=dispatch(CancelEditSecret),
          style=icon_button_style(true) + ["margin-left: 4px"],
          [x_icon()],
        ),
      ]),
    ])
  }
  let confirming = model.secrets.confirming_delete_id == Some(secret.id)
  let menu_key = action_menu_key("secret", secret.id)
  @html.tr([
    @html.td(style=td_style(), [
      @html.div(style=value_style(), secret.name),
      @html.code(secret.id),
    ]),
    @html.td(style=td_style(), @html.code(secret.value_hint)),
    @html.td(style=td_style(), secret.updated_at),
    @html.td(style=actions_td_style(), [
      action_menu_button(dispatch, model, menu_key, "Secret actions"),
      action_menu(model, menu_key, [
        action_menu_item(
          dispatch,
          StartEditSecret(secret.id),
          "Edit secret",
          "Edit",
          false,
          false,
        ),
        action_menu_item(
          dispatch,
          RequestDeleteSecret(secret.id),
          if confirming {
            "Confirm delete secret"
          } else {
            "Delete secret"
          },
          if confirming {
            "Confirm delete"
          } else {
            "Delete"
          },
          true,
          confirming,
        ),
      ]),
    ]),
  ])
}

///|
fn secrets_view(
  dispatch : @rabbita.Dispatch[AdminMsg],
  model : AdminModel,
) -> @rabbita.Html {
  let rows = model.secrets.items.map(fn(secret) {
    secret_row(dispatch, model, secret)
  })
  let body_rows = if model.secrets.create is Some(_) {
    [secret_form_row(dispatch, model)] + rows
  } else if rows.length() == 0 {
    [empty_row(4, "No secrets.")]
  } else {
    rows
  }
  @html.section(style=card_style(), [
    section_head(
      "Secrets",
      "\{model.secrets.items.length()} saved",
      @html.button(
        type_="button",
        title="Add secret",
        on_click=dispatch(OpenCreateSecret),
        style=icon_button_style(true),
        [plus_icon()],
      ),
    ),
    table_wrap(
      @html.table(style=table_style(), [
        @html.thead([
          @html.tr([
            @html.th(style=th_style(), "Name"),
            @html.th(style=th_style(), "Value"),
            @html.th(style=th_style(), "Updated"),
            @html.th(style=th_style(), "Actions"),
          ]),
        ]),
        @html.tbody(body_rows),
      ]),
    ),
  ])
}

///|
fn runtime_status_label(runtime : @sdk.RuntimeDetail) -> String {
  let status = if runtime.enabled { "enabled" } else { "disabled" }
  if runtime.is_default {
    "\{status} / default"
  } else {
    status
  }
}

///|
fn runtime_editor_or_empty(model : AdminModel) -> AdminRuntimeEditor {
  model.runtimes.editor.unwrap_or({
    id: None,
    name: "",
    config_json: "",
    enabled: "true",
    is_default: "false",
  })
}

///|
fn runtime_create_dialog(
  dispatch : @rabbita.Dispatch[AdminMsg],
  model : AdminModel,
) -> @rabbita.Html {
  let editor = runtime_editor_or_empty(model)
  let can_save = editor.name.trim() != "" && editor.config_json.trim() != ""
  @html.div(
    style=[
      "position: fixed", "inset: 0", "z-index: 100", "display: flex", "align-items: center",
      "justify-content: center", "padding: 16px", "background: oklch(from var(--foreground) l c h / 0.22)",
    ],
    [
      @html.div(
        style=card_style() +
          [
            "width: min(760px, 100%)", "max-height: calc(100vh - 32px)", "overflow: auto",
            "gap: 12px",
          ],
        [
          @html.div(
            style=[
              "display: flex", "align-items: flex-start", "justify-content: space-between",
              "gap: 12px",
            ],
            [
              @html.div(
                style=["display: flex", "flex-direction: column", "gap: 4px"],
                [
                  @html.h3(
                    style=title_style() + ["margin: 0"],
                    "Add Runtime Config",
                  ),
                  @html.a(
                    href="/control-plane-assets/admin/runtime-guide.html",
                    target=Blank,
                    rel="noreferrer",
                    style=normal_style() +
                      ["color: var(--accent)", "text-decoration: none"],
                    "Runtime setup guide",
                  ),
                ],
              ),
              @html.button(
                type_="button",
                on_click=dispatch(CancelEditRuntime),
                style=icon_button_style(true),
                [x_icon()],
              ),
            ],
          ),
          @html.div(
            style=["display: flex", "flex-direction: column", "gap: 6px"],
            [
              @html.div(style=value_style(), "Name"),
              @html.input(
                input_type=Text,
                value=editor.name,
                placeholder="Runtime name",
                on_input=fn(value) { dispatch(RuntimeNameChanged(value)) },
                style=input_style(),
                "",
              ),
            ],
          ),
          @html.div(
            style=[
              "display: grid", "grid-template-columns: repeat(2, minmax(0, 1fr))",
              "gap: 8px",
            ],
            [
              @html.div(
                style=["display: flex", "flex-direction: column", "gap: 6px"],
                [
                  @html.div(style=value_style(), "Status"),
                  @html.select(
                    on_change=fn(value) {
                      dispatch(RuntimeEnabledChanged(value))
                    },
                    style=input_style(),
                    [
                      @html.option(
                        value="true",
                        selected=editor.enabled == "true",
                        "enabled",
                      ),
                      @html.option(
                        value="false",
                        selected=editor.enabled == "false",
                        "disabled",
                      ),
                    ],
                  ),
                ],
              ),
              @html.div(
                style=["display: flex", "flex-direction: column", "gap: 6px"],
                [
                  @html.div(style=value_style(), "Default"),
                  @html.select(
                    on_change=fn(value) {
                      dispatch(RuntimeDefaultChanged(value))
                    },
                    style=input_style(),
                    [
                      @html.option(
                        value="false",
                        selected=editor.is_default == "false",
                        "not default",
                      ),
                      @html.option(
                        value="true",
                        selected=editor.is_default == "true",
                        "default",
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
          @html.div(
            style=["display: flex", "flex-direction: column", "gap: 6px"],
            [
              @html.div(style=value_style(), "Runtime Config JSON"),
              @html.textarea(
                rows=12,
                value=editor.config_json,
                on_input=fn(value) { dispatch(RuntimeConfigChanged(value)) },
                style=input_style() +
                  [
                    "font-family: ui-monospace, SFMono-Regular, Menlo, monospace",
                  ],
                "",
              ),
            ],
          ),
          @html.div(
            style=[
              "display: flex", "justify-content: flex-end", "align-items: center",
              "gap: 6px",
            ],
            [
              @html.button(
                type_="button",
                on_click=dispatch(CancelEditRuntime),
                style=button_style(true),
                "Cancel",
              ),
              @html.button(
                type_="button",
                on_click=dispatch(SaveCreateRuntime),
                style=button_style(can_save),
                disabled=!can_save,
                "Create",
              ),
            ],
          ),
        ],
      ),
    ],
  )
}

///|
fn runtime_row(
  dispatch : @rabbita.Dispatch[AdminMsg],
  model : AdminModel,
  runtime : @sdk.RuntimeDetail,
) -> @rabbita.Html {
  if model.runtimes.editor.bind(fn(editor) { editor.id }) == Some(runtime.id) {
    let editor = runtime_editor_or_empty(model)
    @html.tr([
      @html.td(style=td_style(), [
        @html.input(
          input_type=Text,
          value=editor.name,
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
              selected=editor.enabled == "true",
              "enabled",
            ),
            @html.option(
              value="false",
              selected=editor.enabled == "false",
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
              selected=editor.is_default == "false",
              "not default",
            ),
            @html.option(
              value="true",
              selected=editor.is_default == "true",
              "default",
            ),
          ],
        ),
      ]),
      @html.td(colspan=3, style=td_style(), [
        @html.textarea(
          rows=8,
          value=editor.config_json,
          on_input=fn(value) { dispatch(RuntimeConfigChanged(value)) },
          style=input_style() +
            ["font-family: ui-monospace, SFMono-Regular, Menlo, monospace"],
          "",
        ),
      ]),
      @html.td(style=actions_td_style(), [
        @html.button(
          type_="button",
          on_click=dispatch(SaveRuntime(runtime.id)),
          style=icon_button_style(true),
          [check_icon()],
        ),
        @html.button(
          type_="button",
          on_click=dispatch(CancelEditRuntime),
          style=icon_button_style(true) + ["margin-left: 4px"],
          [x_icon()],
        ),
      ]),
    ])
  } else {
    let menu_key = action_menu_key("runtime", runtime.id)
    @html.tr([
      @html.td(style=td_style(), @html.strong(runtime.name)),
      @html.td(style=td_style(), @html.code(runtime.id)),
      @html.td(style=td_style(), runtime_status_label(runtime)),
      @html.td(style=td_style(), [@html.code(runtime.config.launcher.image)]),
      @html.td(
        style=numeric_td_style(),
        runtime.config.env.length().to_string(),
      ),
      @html.td(
        style=numeric_td_style(),
        runtime.config.secrets.length().to_string(),
      ),
      @html.td(style=actions_td_style(), [
        action_menu_button(dispatch, model, menu_key, "Runtime Config actions"),
        action_menu(model, menu_key, [
          action_menu_item(
            dispatch,
            StartEditRuntime(runtime.id),
            "Edit Runtime Config",
            "Edit",
            false,
            false,
          ),
        ]),
      ]),
    ])
  }
}

///|
fn runtimes_view(
  dispatch : @rabbita.Dispatch[AdminMsg],
  model : AdminModel,
) -> @rabbita.Html {
  let runtime_rows = model.runtimes.items.map(fn(runtime) {
    runtime_row(dispatch, model, runtime)
  })
  let rows = if model.runtimes.items.length() == 0 {
    [empty_row(7, "No Runtime Configs.")]
  } else {
    runtime_rows
  }
  @html.section(style=card_style(), [
    section_head(
      "Runtime Configs",
      "\{model.runtimes.items.length()} configured",
      @html.button(
        type_="button",
        title="Add Runtime Config",
        on_click=dispatch(OpenCreateRuntime),
        style=icon_button_style(model.runtimes.editor is None),
        disabled=model.runtimes.editor is Some(_),
        [plus_icon()],
      ),
    ),
    table_wrap(
      @html.table(style=table_style(), [
        @html.thead([
          @html.tr([
            @html.th(style=th_style(), "Name"),
            @html.th(style=th_style(), "ID"),
            @html.th(style=th_style(), "Status"),
            @html.th(style=th_style(), "Image"),
            @html.th(style=th_style() + ["text-align: right"], "Env"),
            @html.th(style=th_style() + ["text-align: right"], "Secrets"),
            @html.th(style=th_style(), "Actions"),
          ]),
        ]),
        @html.tbody(rows),
      ]),
    ),
    if model.runtimes.editor.bind(fn(editor) { editor.id }) is None &&
      model.runtimes.editor is Some(_) {
      runtime_create_dialog(dispatch, model)
    } else {
      @html.nothing
    },
  ])
}

///|
fn active_view(
  dispatch : @rabbita.Dispatch[AdminMsg],
  model : AdminModel,
) -> @rabbita.Html {
  match model.view {
    Users => users_view(dispatch, model)
    Secrets => secrets_view(dispatch, model)
    Runtimes => runtimes_view(dispatch, model)
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
