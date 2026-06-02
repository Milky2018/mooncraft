///|
fn render_loading_screen() -> @rabbita.Html {
  @html.div(style=["display: grid", "place-items: center", "flex: 1"]) <| (@html.div(
    style=panel_style() +
      [
        "padding: 8px", "display: flex", "flex-direction: column", "gap: 4px", "min-width: 340px",
      ],
  ) <| [
    @html.div(style=title_text_style(), "Opening MoonCraft"),
  ])
}

///|
fn avatar_chip(label : String) -> @rabbita.Html {
  @html.div(
    style=value_text_style() +
      [
        "width: 28px", "height: 28px", "border-radius: 999px", "display: grid", "place-items: center",
        "background: var(--accent-strong)", "color: var(--on-action)", "text-transform: uppercase",
      ],
  ) <| label
}

///|
fn account_avatar_label(user : @sdk.UserSummary) -> String {
  let source = if user.display_name.trim() != "" {
    user.display_name.trim().to_owned()
  } else {
    user.email.trim().to_owned()
  }
  if source == "" {
    "U"
  } else {
    match source.iter().next() {
      Some(char) => char.to_string()
      None => "U"
    }
  }
}

///|
fn project_action_button_style(
  foreground : String,
  background : String,
  enabled : Bool,
) -> Array[String] {
  @shared.action_button_box_style(foreground, background, enabled)
}

///|
fn project_more_icon() -> @rabbita.Html {
  @svg.svg(
    width=16,
    height=16,
    view_box="0 0 24 24",
    style=["display: block"],
    [
      @svg.circle(cx=5, cy=12, r=2, fill="currentColor"),
      @svg.circle(cx=12, cy=12, r=2, fill="currentColor"),
      @svg.circle(cx=19, cy=12, r=2, fill="currentColor"),
    ],
  )
}

///|
fn project_save_icon() -> @rabbita.Html {
  @svg.svg(
    width=16,
    height=16,
    view_box="0 0 24 24",
    style=["display: block"],
    [
      @svg.path(
        d="M5 12.5l4 4L19 6.5",
        fill="none",
        stroke="currentColor",
        stroke_width=2,
      ),
    ],
  )
}

///|
fn project_cancel_icon() -> @rabbita.Html {
  @svg.svg(
    width=16,
    height=16,
    view_box="0 0 24 24",
    style=["display: block"],
    [
      @svg.path(
        d="M7 7l10 10",
        fill="none",
        stroke="currentColor",
        stroke_width=2,
      ),
      @svg.path(
        d="M17 7L7 17",
        fill="none",
        stroke="currentColor",
        stroke_width=2,
      ),
    ],
  )
}

///|
fn project_action_menu_style() -> Array[String] {
  @shared.menu_surface_style(
    "34px", "0", "40", "132px", "var(--radius-control)", "var(--surface-raised)",
    "", "flex",
  )
}

///|
fn project_menu_item_style(
  foreground : String,
  background : String,
  enabled : Bool,
) -> Array[String] {
  @shared.menu_item_base_style(
    value_text_style(),
    foreground,
    background,
    enabled,
    "var(--radius-control)",
    "flex",
  ) +
  ["white-space: nowrap"]
}

///|
fn account_menu_item_style(enabled : Bool) -> Array[String] {
  @shared.menu_item_base_style(
    value_text_style(),
    "var(--text-1)",
    "transparent",
    enabled,
    "var(--radius-control)",
    "inline-flex",
  ) +
  ["height: 34px", "gap: 8px"]
}

///|
fn account_caret_icon(open : Bool) -> @rabbita.Html {
  @svg.svg(
    width=16,
    height=16,
    view_box="0 0 24 24",
    style=["display: block"],
    [
      @svg.path(
        d=if open { "M6 15l6-6 6 6" } else { "M6 9l6 6 6-6" },
        fill="none",
        stroke="currentColor",
        stroke_width=2,
      ),
    ],
  )
}

///|
fn project_phase_dot(project : @sdk.ProjectSummary) -> @rabbita.Html {
  let color = if project.is_processing {
    match project.activity {
      Some(activity) =>
        match activity.phase {
          RuntimeRunning => Some("#16a34a")
          Checking => Some("#2563eb")
          NoPhase => Some("#16a34a")
        }
      None => Some("#16a34a")
    }
  } else if project.status is Failed {
    Some("var(--danger)")
  } else {
    None
  }
  match color {
    Some(value) =>
      @html.span(
        title=project_activity_label(project),
        style=[
          "width: 8px",
          "height: 8px",
          "border-radius: 999px",
          "background: \{value}",
          "display: inline-block",
          "flex: 0 0 auto",
        ],
        "",
      )
    None => @html.nothing
  }
}

///|
fn project_activity_label(project : @sdk.ProjectSummary) -> String {
  if project.is_processing {
    match project.activity {
      Some(activity) =>
        match activity.message {
          Some(message) =>
            @sdk.run_event_display_text(
              activity.message_code.unwrap_or(""),
              message,
            )
          None =>
            if activity.phase is NoPhase {
              "Processing"
            } else {
              activity.phase.label()
            }
        }
      None => "Processing"
    }
  } else {
    project.status.label()
  }
}

///|
fn sidebar_project_item(
  dispatch : @rabbita.Dispatch[Msg],
  model : Model,
  project : @sdk.ProjectSummary,
) -> @rabbita.Html {
  let selected = model.selected_project_id == Some(project.id)
  let deleting = model.delete_project_pending == Some(project.id)
  let confirming = model.delete_project_confirming == Some(project.id)
  let renaming = selected && model.rename_project_editing
  let menu_open = model.project_action_menu_open == Some(project.id)
  let delete_enabled = !(project.is_processing || deleting)
  let edit_enabled = !deleting
  let delete_foreground = if confirming { "#ffffff" } else { "var(--danger)" }
  let delete_background = if confirming {
    "var(--danger)"
  } else {
    "transparent"
  }
  let item_class = if selected {
    "project-list-item is-selected"
  } else {
    "project-list-item"
  }
  let action_class = if menu_open || deleting || confirming {
    "project-action-slot is-visible"
  } else {
    "project-action-slot"
  }
  @html.div(
    class=item_class,
    style=[
      "border: 0", "border-radius: var(--radius-control)", "box-shadow: none", "padding: 5px 8px",
      "display: flex", "align-items: center", "gap: 6px", "position: relative", "overflow: visible",
    ],
  ) <| [
    if renaming {
      @html.div(
        style=[
          "flex: 1", "min-width: 0", "display: flex", "align-items: center", "gap: 4px",
        ],
      ) <| [
        @html.div(
          style=[
            "min-width: 0", "display: flex", "flex-direction: column", "gap: 4px",
          ],
        ) <| [
          @html.input(
            input_type=Text,
            value=model.rename_project_name,
            placeholder="Project name",
            read_only=model.rename_project_pending,
            on_input=fn(value) { dispatch(RenameProjectNameChanged(value)) },
            style=input_style(model.rename_project_pending) +
              [
                "height: 28px", "min-width: 0", "padding: 4px 8px", "border-radius: var(--radius-control)",
              ],
            "",
          ),
        ],
      ]
    } else {
      @html.button(
        type_="button",
        on_click=dispatch(SelectProject(project.id)),
        style=value_text_style() +
          [
            "flex: 1", "min-width: 0", "padding: 0 32px 0 0", "border: none", "background: transparent",
            "cursor: pointer", "display: flex", "align-items: center", "gap: 4px",
            "text-align: left",
          ],
        [
          project_phase_dot(project),
          @html.div(
            style=[
              "min-width: 0", "display: flex", "flex-direction: column", "gap: 4px",
            ],
            [
              @html.div(
                style=value_text_style() +
                  [
                    "white-space: nowrap", "overflow: hidden", "text-overflow: ellipsis",
                  ],
                project.display_name,
              ),
            ],
          ),
        ],
      )
    },
    if renaming {
      @html.div(style=["display: flex", "align-items: center", "gap: 4px"]) <| [
        @html.button(
          type_="button",
          title="Save project name",
          disabled=!can_rename_project(model),
          on_click=dispatch(SaveProjectRename),
          style=project_action_button_style(
            "var(--accent-strong)",
            "transparent",
            can_rename_project(model),
          ),
          [project_save_icon()],
        ),
        @html.button(
          type_="button",
          title="Cancel rename",
          disabled=model.rename_project_pending,
          on_click=dispatch(CancelProjectRename),
          style=project_action_button_style(
            "var(--text-2)",
            "transparent",
            !model.rename_project_pending,
          ),
          [project_cancel_icon()],
        ),
      ]
    } else {
      @html.div(
        class=action_class,
        style=[
          "position: absolute", "right: 8px", "top: 5px", "z-index: 10", "display: flex",
          "align-items: center", "gap: 4px",
        ],
      ) <| [
        @html.button(
          type_="button",
          title="Project actions",
          disabled=false,
          on_click=dispatch(ToggleProjectActionMenu(project.id)),
          style=project_action_button_style(
            "var(--text-1)", "var(--foreground-5)", true,
          ),
          [project_more_icon()],
        ),
        if menu_open {
          @html.div(style=project_action_menu_style()) <| [
            @html.button(
              type_="button",
              title="Project info",
              disabled=!edit_enabled,
              on_click=dispatch(OpenProjectInfo),
              style=project_menu_item_style(
                "var(--text-2)", "transparent", edit_enabled,
              ),
              "Info",
            ),
            @html.button(
              type_="button",
              title="Rename project",
              disabled=!edit_enabled,
              on_click=dispatch(StartProjectRename(project.display_name)),
              style=project_menu_item_style(
                "var(--text-2)", "transparent", edit_enabled,
              ),
              "Rename",
            ),
            @html.button(
              type_="button",
              title=if confirming {
                "Confirm delete project"
              } else {
                "Delete project"
              },
              disabled=!delete_enabled,
              on_click=if confirming {
                dispatch(ConfirmDeleteProject(project.id))
              } else {
                dispatch(RequestDeleteProject(project.id))
              },
              style=project_menu_item_style(
                delete_foreground, delete_background, delete_enabled,
              ),
              if confirming {
                "Confirm delete"
              } else {
                "Delete"
              },
            ),
          ]
        } else {
          @html.nothing
        },
      ]
    },
  ]
}

///|
fn render_account_panel(
  dispatch : @rabbita.Dispatch[Msg],
  model : Model,
) -> @rabbita.Html {
  match model.current_user {
    Some(user) => {
      let email_text = if user.email != "" {
        user.email
      } else {
        user.display_name
      }
      let avatar_label = account_avatar_label(user)
      let theme_label = model.theme_mode.storage_value()
      @html.div(
        style=[
          "position: absolute", "right: 0", "top: calc(100% + 6px)", "width: min(280px, calc(100vw - 24px))",
          "padding: 6px", "display: flex", "flex-direction: column", "gap: 4px",
          "z-index: 100", "max-height: calc(100vh - 90px)", "overflow-y: auto", "background: var(--surface-raised)",
          "background-color: var(--surface-raised)", "background-image: none", "border: 1px solid var(--border-soft)",
          "border-radius: var(--radius-panel)", "box-shadow: var(--shadow)", "backdrop-filter: none",
          "isolation: isolate",
        ],
      ) <| [
        @html.div(
          style=[
            "display: flex", "align-items: center", "gap: 8px", "padding: 4px",
          ],
          [
            avatar_chip(avatar_label),
            @html.div(
              style=[
                "display: flex", "flex-direction: column", "gap: 4px", "min-width: 0",
              ],
              [
                @html.div(
                  style=value_text_style() +
                    [
                      "white-space: nowrap", "overflow: hidden", "text-overflow: ellipsis",
                    ],
                  user.display_name,
                ),
                @html.div(
                  style=normal_text_style() +
                    [
                      "white-space: nowrap", "overflow: hidden", "text-overflow: ellipsis",
                    ],
                  email_text,
                ),
              ],
            ),
          ],
        ),
        render_notice_card(model.account_notice, "var(--warning-soft)"),
        @html.div(
          style=[
            "height: 1px", "background: var(--border-soft)", "margin: 2px 0",
          ],
          "",
        ),
        @html.button(
          type_="button",
          title="Theme: \{theme_label}",
          on_click=dispatch(ToggleTheme),
          style=account_menu_item_style(true),
          [
            theme_icon(model.theme_mode),
            @html.span(style=["flex: 1"], "Theme"),
            @html.span(
              style=normal_text_style() + ["color: var(--text-2)"],
              theme_label,
            ),
          ],
        ),
        @html.button(
          type_="button",
          disabled=model.logout_pending,
          title=if model.logout_pending { "Logging out" } else { "Log out" },
          on_click=dispatch(Logout),
          style=account_menu_item_style(!model.logout_pending),
          [
            logout_icon(),
            @html.span(
              if model.logout_pending {
                "Logging out"
              } else {
                "Log out"
              },
            ),
          ],
        ),
      ]
    }
    None => @html.nothing
  }
}

///|
fn render_account_toolbar(
  dispatch : @rabbita.Dispatch[Msg],
  model : Model,
) -> @rabbita.Html {
  match model.current_user {
    Some(user) => {
      let avatar_label = account_avatar_label(user)
      @html.div(
        style=[
          "position: relative", "padding: 0", "display: flex", "align-items: center",
          "justify-content: flex-end", "gap: 6px", "flex-wrap: wrap", "flex-shrink: 0",
          "overflow: visible", "z-index: 20",
        ],
      ) <| [
        @html.div(
          style=[
            "display: flex", "align-items: center", "justify-content: flex-end",
            "gap: 6px", "flex-wrap: wrap", "position: relative",
          ],
          [
            tun_poc_link(),
            @html.button(
              type_="button",
              on_click=dispatch(ToggleAccountPanel),
              style=secondary_button_style(true) +
                [
                  "height: 28px", "padding: 0 7px", "justify-content: flex-start",
                  "min-width: 0",
                ],
              [
                avatar_chip(avatar_label),
                @html.div(
                  style=value_text_style() +
                    [
                      "white-space: nowrap", "overflow: hidden", "text-overflow: ellipsis",
                      "max-width: 140px",
                    ],
                  user.display_name,
                ),
                @html.div(
                  style=normal_text_style() +
                    ["margin-left: auto", "color: var(--text-2)"],
                  [account_caret_icon(model.account_panel_open)],
                ),
              ],
            ),
            if model.account_panel_open {
              render_account_panel(dispatch, model)
            } else {
              @html.nothing
            },
          ],
        ),
      ]
    }
    None => @html.nothing
  }
}

///|
fn render_project_sidebar(
  dispatch : @rabbita.Dispatch[Msg],
  model : Model,
) -> @rabbita.Html {
  let project_items = model.projects.map(fn(project) {
    sidebar_project_item(dispatch, model, project)
  })
  @html.div(
    style=[
      "width: 284px", "height: 100vh", "min-height: 0", "padding: 6px", "display: flex",
      "flex-direction: column", "gap: 6px", "background: var(--sidebar-bg)", "box-sizing: border-box",
      "flex-shrink: 0", "overflow: hidden", "backdrop-filter: none",
    ],
  ) <| [
    @html.div(style=["display: flex", "align-items: center", "gap: 8px"], [
      brand_logo(28),
      @html.div(
        style=[
          "min-width: 0", "display: flex", "flex-direction: column", "gap: 4px",
        ],
        [@html.div(style=title_text_style(), "MoonCraft")],
      ),
    ]),
    @html.div(
      style=value_text_style() +
        [
          "display: flex", "justify-content: space-between", "align-items: center",
        ],
      [
        @html.div("Projects"),
        @html.button(
          type_="button",
          disabled=false,
          title="New project",
          on_click=dispatch(OpenNewProjectDialog),
          style=primary_button_style(true) +
            ["width: 28px", "height: 28px", "padding: 0"],
          [plus_icon()],
        ),
      ],
    ),
    @html.div(
      style=[
        "display: flex", "flex-direction: column", "gap: 2px", "min-height: 0", "overflow-y: auto",
        "overscroll-behavior: contain", "flex: 1",
      ],
      project_items,
    ),
  ]
}

///|
fn render_workspace_shell(
  dispatch : @rabbita.Dispatch[Msg],
  model : Model,
) -> @rabbita.Html {
  let workspace_body = [render_workspace_panel(dispatch, model)]
  @html.div(
    style=[
      "height: 100vh", "min-height: 0", "display: flex", "align-items: stretch",
      "background: transparent", "overflow: hidden",
    ],
  ) <| [
    render_project_sidebar(dispatch, model),
    @html.div(
      style=[
        "flex: 1", "min-width: 0", "padding: 6px", "display: flex", "flex-direction: column",
        "gap: 6px", "box-sizing: border-box", "min-height: 0", "overflow: hidden",
      ],
      [
        render_account_toolbar(dispatch, model),
        @html.div(
          style=[
            "flex: 1", "min-width: 0", "min-height: 0", "display: flex", "gap: 6px",
            "align-items: stretch", "overflow: hidden",
          ],
          workspace_body,
        ),
      ],
    ),
    render_new_project_dialog(dispatch, model),
    render_project_info_dialog(dispatch, model),
  ]
}

///|
fn view(dispatch : @rabbita.Dispatch[Msg], model : Model) -> @rabbita.Html {
  if model.session_ready && model.current_user is Some(_) {
    @html.div(style=app_root_style(model.resolved_theme_mode)) <| render_workspace_shell(
      dispatch, model,
    )
  } else if model.session_ready {
    @html.div(style=app_root_style(model.resolved_theme_mode)) <| render_auth_screen(
      dispatch, model,
    )
  } else {
    @html.div(style=app_root_style(model.resolved_theme_mode)) <| (@html.div(
      style=app_stack_style(),
    ) <| [
      render_app_header(dispatch, model),
      render_loading_screen(),
    ])
  }
}
