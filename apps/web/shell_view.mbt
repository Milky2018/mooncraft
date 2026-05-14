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
        "background: var(--accent-strong)", "color: var(--on-action)",
      ],
  ) <| label
}

///|
fn project_action_button_style(
  foreground : String,
  background : String,
  enabled : Bool,
) -> Array[String] {
  let cursor = if enabled { "pointer" } else { "not-allowed" }
  let opacity = if enabled { "1" } else { "0.45" }
  [
    "width: 28px",
    "height: 28px",
    "padding: 0",
    "border: 0",
    "border-radius: var(--radius-control)",
    "background: " + background,
    "color: " + foreground,
    "display: inline-flex",
    "align-items: center",
    "justify-content: center",
    "cursor: " + cursor,
    "opacity: " + opacity,
    "flex-shrink: 0",
  ]
}

///|
fn project_edit_icon() -> @rabbita.Html {
  @svg.svg(
    width=16,
    height=16,
    view_box="0 0 24 24",
    style=["display: block"],
    [
      @svg.path(
        d="M4 20h4L18.5 9.5a2.1 2.1 0 0 0-3-3L5 17v3z",
        fill="none",
        stroke="currentColor",
        stroke_width=2,
      ),
      @svg.path(
        d="M13.5 8.5l2 2",
        fill="none",
        stroke="currentColor",
        stroke_width=2,
      ),
    ],
  )
}

///|
fn project_delete_icon() -> @rabbita.Html {
  @svg.svg(
    width=16,
    height=16,
    view_box="0 0 24 24",
    style=["display: block"],
    [
      @svg.path(d="M4 7h16", fill="none", stroke="currentColor", stroke_width=2),
      @svg.path(
        d="M9 7V4h6v3",
        fill="none",
        stroke="currentColor",
        stroke_width=2,
      ),
      @svg.path(
        d="M6 7l1 14h10l1-14",
        fill="none",
        stroke="currentColor",
        stroke_width=2,
      ),
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
  let color = match project.current_run_phase {
    AgentRunning => Some("#16a34a")
    Checking => Some("#2563eb")
    NoPhase =>
      if project.status is Running {
        Some("#16a34a")
      } else if project.status is Failed {
        Some("var(--danger)")
      } else {
        None
      }
  }
  match color {
    Some(value) =>
      @html.span(
        title=if project.current_run_phase is NoPhase {
          project.status.label()
        } else {
          project.current_run_phase.label()
        },
        style=[
          "width: 8px",
          "height: 8px",
          "border-radius: 999px",
          "background: " + value,
          "display: inline-block",
          "flex: 0 0 auto",
        ],
        "",
      )
    None => @html.nothing
  }
}

///|
fn sidebar_project_item(
  dispatch : @rabbita.Dispatch[Msg],
  model : Model,
  project : @sdk.ProjectSummary,
) -> @rabbita.Html {
  let selected = model.selected_project_id == Some(project.id)
  let background = if selected { "var(--foreground-5)" } else { "transparent" }
  let deleting = model.delete_project_pending == Some(project.id)
  let confirming = model.delete_project_confirming == Some(project.id)
  let renaming = selected && model.rename_project_editing
  let delete_enabled = !(project.status is Running || deleting)
  let edit_enabled = !deleting
  let delete_foreground = if confirming { "#ffffff" } else { "var(--danger)" }
  let delete_background = if confirming {
    "var(--danger)"
  } else {
    "transparent"
  }
  @html.div(
    style=[
      "border: 0",
      "border-radius: var(--radius-control)",
      "background: " + background,
      "box-shadow: none",
      "padding: 5px 8px",
      "display: flex",
      "align-items: center",
      "gap: 6px",
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
            "flex: 1", "min-width: 0", "padding: 0", "border: none", "background: transparent",
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
    } else if selected || deleting {
      @html.div(style=["display: flex", "align-items: center", "gap: 4px"]) <| [
        @html.button(
          type_="button",
          title="Rename project",
          disabled=!edit_enabled,
          on_click=dispatch(StartProjectRename(project.display_name)),
          style=project_action_button_style(
            "var(--text-2)", "transparent", edit_enabled,
          ),
          [project_edit_icon()],
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
          style=project_action_button_style(
            delete_foreground, delete_background, delete_enabled,
          ),
          [project_delete_icon()],
        ),
      ]
    } else {
      @html.nothing
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
        @html.div(style=["display: flex", "align-items: center", "gap: 8px"], [
          avatar_chip("U"),
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
        ]),
        render_notice_card(model.account_notice, "var(--warning-soft)"),
        @html.div(
          style=[
            "display: flex", "align-items: center", "justify-content: space-between",
            "gap: 8px", "padding-top: 4px",
          ],
          [theme_toggle_button(dispatch, model)],
        ),
        @html.button(
          type_="button",
          disabled=model.logout_pending,
          on_click=dispatch(Logout),
          style=button_style(
              "var(--surface-2)",
              "var(--text-2)",
              !model.logout_pending,
            ) +
            ["width: 100%", "justify-content: flex-start", "height: 30px"],
          if model.logout_pending {
            "Logging out..."
          } else {
            "Log Out"
          },
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
    Some(user) =>
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
                avatar_chip("U"),
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
      "flex-direction: column", "gap: 6px", "background: var(--sidebar-bg)", "border-right: 1px solid var(--border-soft)",
      "box-sizing: border-box", "flex-shrink: 0", "overflow: hidden", "backdrop-filter: none",
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
          on_click=dispatch(OpenNewProjectDialog),
          style=primary_button_style(true) + ["height: 28px", "padding: 0 10px"],
          "+ New",
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
  let workspace_body = match ready_preview(model) {
    Some(_) =>
      match model.preview_panel_mode {
        PreviewHidden => [render_workspace_panel(dispatch, model)]
        PreviewExpanded =>
          [render_preview_panel(dispatch, model, expanded=true)]
        PreviewSplit =>
          [
            render_workspace_panel(dispatch, model),
            render_preview_panel(dispatch, model, expanded=false),
          ]
      }
    None => [render_workspace_panel(dispatch, model)]
  }
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
