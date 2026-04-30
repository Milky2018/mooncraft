///|
fn render_loading_screen() -> @rabbita.Html {
  @html.div(
    style=["display: grid", "place-items: center", "flex: 1"],
    @html.div(
      style=panel_style() +
        [
          "padding: 26px 30px", "display: flex", "flex-direction: column", "gap: 10px",
          "min-width: 340px",
        ],
      [
        @html.div(
          style=["font-size: 30px", "line-height: 1.05", "font-weight: 600"],
          "Opening Mooncraft",
        ),
        @html.div(
          style=["font-size: 14px", "line-height: 1.6", "color: var(--text-2)"],
          "Preparing your project workspace.",
        ),
      ],
    ),
  )
}

///|
fn workspace_name(model : Model) -> String {
  user_name(model) + "'s Workspace"
}

///|
fn avatar_chip(label : String) -> @rabbita.Html {
  @html.div(
    style=[
      "width: 28px", "height: 28px", "border-radius: 999px", "display: grid", "place-items: center",
      "background: var(--accent-strong)", "color: var(--on-action)", "font-size: 13px",
      "font-weight: 700",
    ],
    label,
  )
}

///|
fn sidebar_project_item(
  dispatch : @rabbita.Dispatch[Msg],
  model : Model,
  project : @sdk.ProjectSummary,
) -> @rabbita.Html {
  let selected = model.selected_project_id == Some(project.id)
  let background = if selected {
    "linear-gradient(135deg, rgba(255, 255, 255, 0.96), rgba(241, 245, 249, 0.88))"
  } else {
    "rgba(255, 255, 255, 0.38)"
  }
  let border_color = if selected {
    "var(--border-strong)"
  } else {
    "rgba(15, 23, 42, 0.08)"
  }
  let shadow = if selected {
    "0 14px 30px rgba(26, 46, 43, 0.10)"
  } else {
    "none"
  }
  let deleting = model.delete_project_pending == Some(project.id)
  let confirming = model.delete_project_confirming == Some(project.id)
  let delete_enabled = !(project.status is @sdk.Running || deleting)
  @html.div(
    style=[
      "border: 1px solid " + border_color,
      "border-radius: 14px",
      "background: " + background,
      "box-shadow: " + shadow,
      "padding: 10px",
      "display: flex",
      "align-items: center",
      "gap: 8px",
    ],
    [
      @html.button(
        type_="button",
        on_click=dispatch(SelectProject(project.id)),
        style=[
          "flex: 1", "min-width: 0", "padding: 0", "border: none", "background: transparent",
          "color: var(--text-1)", "cursor: pointer", "display: flex", "align-items: center",
          "gap: 10px", "text-align: left",
        ],
        [
          @html.div(
            style=[
              "width: 34px", "height: 34px", "border-radius: 10px", "background: linear-gradient(135deg, var(--accent), #2563eb)",
              "box-shadow: inset 0 1px 0 rgba(255, 255, 255, 0.35)",
            ],
            "",
          ),
          @html.div(
            style=[
              "min-width: 0", "display: flex", "flex-direction: column", "gap: 3px",
            ],
            [
              @html.div(
                style=[
                  "font-size: 14px", "font-weight: 600", "white-space: nowrap", "overflow: hidden",
                  "text-overflow: ellipsis",
                ],
                project.display_name,
              ),
              @html.div(
                style=mono_style() + ["font-size: 11px", "color: var(--text-3)"],
                project.status.label(),
              ),
            ],
          ),
        ],
      ),
      if selected || deleting {
        @html.button(
          type_="button",
          disabled=!delete_enabled,
          on_click=if confirming {
            dispatch(ConfirmDeleteProject(project.id))
          } else {
            dispatch(RequestDeleteProject(project.id))
          },
          style=subtle_danger_button_style(delete_enabled) + ["flex-shrink: 0"],
          if deleting {
            "Deleting..."
          } else if confirming {
            "Confirm Delete"
          } else {
            "Delete"
          },
        )
      } else {
        @html.nothing
      },
    ],
  )
}

///|
fn account_password_input(
  value : String,
  placeholder : String,
  on_input : (String) -> Msg,
  dispatch : @rabbita.Dispatch[Msg],
) -> @rabbita.Html {
  @html.input(
    input_type=@html.Password,
    value~,
    placeholder~,
    on_input=fn(next) { dispatch(on_input(next)) },
    style=input_style(false) +
      [
        "padding: 9px 10px", "font-size: 13px", "border-color: var(--border-soft)",
      ],
    "",
  )
}

///|
fn account_text_input(
  value : String,
  placeholder : String,
  on_input : (String) -> Msg,
  dispatch : @rabbita.Dispatch[Msg],
) -> @rabbita.Html {
  @html.input(
    input_type=@html.Text,
    value~,
    placeholder~,
    on_input=fn(next) { dispatch(on_input(next)) },
    style=input_style(false) +
      [
        "padding: 9px 10px", "font-size: 13px", "border-color: var(--border-soft)",
      ],
    "",
  )
}

///|
fn ai_provider_button(
  dispatch : @rabbita.Dispatch[Msg],
  model : Model,
  provider : String,
  label : String,
) -> @rabbita.Html {
  let selected = model.account_ai_provider == provider
  @html.button(
    type_="button",
    on_click=dispatch(AccountAiProviderChanged(provider)),
    style=button_style(
        if selected {
          "var(--accent)"
        } else {
          "var(--surface-2)"
        },
        if selected {
          "#ffffff"
        } else {
          "var(--text-2)"
        },
        true,
      ) +
      ["padding: 8px 10px", "font-size: 12px", "flex: 1"],
    label,
  )
}

///|
fn render_account_panel(
  dispatch : @rabbita.Dispatch[Msg],
  model : Model,
) -> @rabbita.Html {
  match model.current_user {
    Some(user) => {
      let verification_text = if user.email_verified {
        "Verified"
      } else {
        "Verification pending"
      }
      let resend_enabled = !user.email_verified && !model.account_pending
      @html.div(
        style=panel_style() +
          [
            "position: absolute", "right: 0", "top: calc(100% + 10px)", "width: min(380px, calc(100vw - 32px))",
            "padding: 14px", "display: flex", "flex-direction: column", "gap: 12px",
            "z-index: 10", "max-height: calc(100vh - 90px)", "overflow-y: auto",
          ],
        [
          @html.div(
            style=[
              "display: flex", "align-items: center", "justify-content: space-between",
              "gap: 10px",
            ],
            [
              @html.div(
                style=[
                  "display: flex", "flex-direction: column", "gap: 3px", "min-width: 0",
                ],
                [
                  @html.div(style=section_label_style(), "Account"),
                  @html.div(
                    style=[
                      "font-size: 14px", "font-weight: 600", "color: var(--text-1)",
                      "white-space: nowrap", "overflow: hidden", "text-overflow: ellipsis",
                    ],
                    user.display_name,
                  ),
                  @html.div(
                    style=mono_style() +
                      [
                        "font-size: 11px", "color: var(--text-3)", "white-space: nowrap",
                        "overflow: hidden", "text-overflow: ellipsis",
                      ],
                    user.email,
                  ),
                ],
              ),
              @html.div(
                style=mono_style() +
                  [
                    "font-size: 11px", "color: var(--text-2)", "padding: 5px 8px",
                    "border: 1px solid var(--border-soft)", "border-radius: 999px",
                    "background: var(--surface-2)", "white-space: nowrap",
                  ],
                verification_text,
              ),
            ],
          ),
          render_notice_card(model.account_notice, "var(--warning-soft)"),
          if user.email_verified {
            @html.nothing
          } else {
            @html.button(
              type_="button",
              disabled=!resend_enabled,
              on_click=dispatch(ResendEmailVerification),
              style=secondary_button_style(resend_enabled) +
                ["padding: 9px 10px", "font-size: 12px"],
              if model.account_pending {
                "Queueing..."
              } else {
                "Resend Verification"
              },
            )
          },
          @html.div(
            style=[
              "display: flex", "align-items: center", "justify-content: space-between",
              "gap: 10px", "padding-top: 8px", "border-top: 1px solid var(--border-soft)",
            ],
            [
              @html.div(
                style=["display: flex", "flex-direction: column", "gap: 3px"],
                [@html.div(style=section_label_style(), "Appearance")],
              ),
              theme_toggle_button(dispatch, model),
            ],
          ),
          @html.div(
            style=[
              "display: flex", "flex-direction: column", "gap: 8px", "padding: 10px",
              "border: 1px solid var(--border-soft)", "border-radius: 6px", "background: var(--surface-2)",
            ],
            [
              @html.div(
                style=[
                  "display: flex", "align-items: center", "justify-content: space-between",
                  "gap: 8px",
                ],
                [
                  @html.div(style=section_label_style(), "AI Provider"),
                  @html.div(
                    style=mono_style() +
                      ["font-size: 10px", "color: var(--text-3)"],
                    if user.ai_api_key_configured {
                      "Key saved"
                    } else {
                      "Key missing"
                    },
                  ),
                ],
              ),
              @html.div(style=["display: flex", "gap: 8px"], [
                ai_provider_button(dispatch, model, "openai", "OpenAI"),
                ai_provider_button(dispatch, model, "openrouter", "OpenRouter"),
              ]),
              account_text_input(
                model.account_ai_model,
                if model.account_ai_provider == "openrouter" {
                  "openai/gpt-5.5"
                } else {
                  "gpt-5.5"
                },
                fn(value) { AccountAiModelChanged(value) },
                dispatch,
              ),
              account_password_input(
                model.account_ai_api_key,
                if user.ai_api_key_configured {
                  "Leave blank to keep saved API key"
                } else {
                  "API key"
                },
                fn(value) { AccountAiApiKeyChanged(value) },
                dispatch,
              ),
              @html.button(
                type_="button",
                disabled=!can_save_ai_settings(model),
                on_click=dispatch(SaveAiSettings),
                style=primary_button_style(can_save_ai_settings(model)) +
                  ["padding: 9px 10px", "font-size: 12px"],
                if model.account_pending {
                  "Saving..."
                } else {
                  "Save AI Settings"
                },
              ),
            ],
          ),
          @html.button(
            type_="button",
            on_click=dispatch(TogglePasswordPanel),
            style=secondary_button_style(true) +
              ["justify-content: space-between"],
            if model.password_panel_open {
              "Hide Password Form"
            } else {
              "Change Password"
            },
          ),
          if model.password_panel_open {
            @html.div(
              style=[
                "display: flex", "flex-direction: column", "gap: 8px", "padding: 10px",
                "border: 1px solid var(--border-soft)", "border-radius: 6px", "background: var(--surface-2)",
              ],
              [
                account_password_input(
                  model.account_current_password,
                  "Current password",
                  fn(value) { AccountCurrentPasswordChanged(value) },
                  dispatch,
                ),
                account_password_input(
                  model.account_new_password,
                  "New password",
                  fn(value) { AccountNewPasswordChanged(value) },
                  dispatch,
                ),
                @html.button(
                  type_="button",
                  disabled=!can_change_password(model),
                  on_click=dispatch(ChangePassword),
                  style=primary_button_style(can_change_password(model)) +
                    ["padding: 9px 10px", "font-size: 12px"],
                  if model.account_pending {
                    "Updating..."
                  } else {
                    "Save Password"
                  },
                ),
              ],
            )
          } else {
            @html.nothing
          },
          @html.button(
            type_="button",
            disabled=model.logout_pending,
            on_click=dispatch(Logout),
            style=button_style(
                "var(--surface-2)",
                "var(--text-2)",
                !model.logout_pending,
              ) +
              ["width: 100%", "justify-content: flex-start"],
            if model.logout_pending {
              "Logging out..."
            } else {
              "Log Out"
            },
          ),
        ],
      )
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
        style=panel_style() +
          [
            "position: relative", "padding: 12px 16px", "display: flex", "align-items: center",
            "justify-content: space-between", "gap: 10px", "flex-wrap: wrap", "flex-shrink: 0",
            "overflow: visible", "z-index: 20",
          ],
        [
          @html.div(
            style=["display: flex", "flex-direction: column", "gap: 2px"],
            [
              @html.div(style=section_label_style(), "Workspace"),
              @html.div(
                style=[
                  "font-size: 15px", "font-weight: 600", "color: var(--text-1)",
                ],
                workspace_name(model),
              ),
            ],
          ),
          @html.div(
            style=[
              "display: flex", "align-items: center", "justify-content: flex-end",
              "gap: 8px", "flex-wrap: wrap", "position: relative",
            ],
            [
              @html.button(
                type_="button",
                on_click=dispatch(ToggleAccountPanel),
                style=secondary_button_style(true) +
                  [
                    "padding: 8px 10px", "justify-content: flex-start", "min-width: 190px",
                  ],
                [
                  avatar_chip("U"),
                  @html.div(
                    style=[
                      "display: flex", "flex-direction: column", "gap: 1px", "min-width: 0",
                      "align-items: flex-start",
                    ],
                    [
                      @html.div(
                        style=[
                          "font-size: 13px", "font-weight: 600", "color: var(--text-1)",
                          "white-space: nowrap", "overflow: hidden", "text-overflow: ellipsis",
                          "max-width: 110px",
                        ],
                        user.display_name,
                      ),
                      @html.div(
                        style=mono_style() +
                          ["font-size: 10px", "color: var(--text-3)"],
                        "Account",
                      ),
                    ],
                  ),
                  @html.div(
                    style=[
                      "margin-left: auto", "font-size: 12px", "color: var(--text-3)",
                    ],
                    if model.account_panel_open {
                      "^"
                    } else {
                      "v"
                    },
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
        ],
      )
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
      "width: 320px", "height: 100vh", "min-height: 0", "padding: 18px 14px", "display: flex",
      "flex-direction: column", "gap: 16px", "background: var(--sidebar-bg)", "border-right: 1px solid rgba(15, 23, 42, 0.08)",
      "box-sizing: border-box", "flex-shrink: 0", "overflow: hidden", "backdrop-filter: blur(24px)",
    ],
    [
      @html.div(style=["display: flex", "align-items: center", "gap: 10px"], [
        brand_logo(38),
        @html.div(
          style=[
            "min-width: 0", "display: flex", "flex-direction: column", "gap: 2px",
          ],
          [
            @html.div(
              style=[
                "font-size: 18px", "font-weight: 600", "letter-spacing: -0.02em",
              ],
              "Mooncraft",
            ),
            @html.div(
              style=[
                "font-size: 12px", "color: var(--text-3)", "white-space: nowrap",
                "overflow: hidden", "text-overflow: ellipsis",
              ],
              workspace_name(model),
            ),
          ],
        ),
      ]),
      @html.button(
        type_="button",
        disabled=model.create_project_pending,
        on_click=dispatch(CreateProject),
        style=primary_button_style(!model.create_project_pending) +
          ["width: 100%", "padding: 12px 14px"],
        if model.create_project_pending {
          "Creating..."
        } else {
          "+ New Project"
        },
      ),
      @html.div(
        style=[
          "display: flex", "justify-content: space-between", "align-items: center",
          "color: var(--text-2)", "font-size: 13px", "font-weight: 700",
        ],
        [
          @html.div("Projects"),
          @html.div(style=mono_style(), model.projects.length().to_string()),
        ],
      ),
      @html.div(
        style=[
          "display: flex", "flex-direction: column", "gap: 8px", "min-height: 0",
          "overflow-y: auto", "overscroll-behavior: contain", "flex: 1",
        ],
        if project_items.length() == 0 {
          [
            @html.div(
              style=[
                "padding: 16px", "border: 1px dashed var(--border-soft)", "border-radius: 14px",
                "color: var(--text-3)", "font-size: 13px", "line-height: 1.55", "background: rgba(255, 255, 255, 0.36)",
              ],
              "Create your first project. The preview will appear on the right.",
            ),
          ]
        } else {
          project_items
        },
      ),
    ],
  )
}

///|
fn render_workspace_shell(
  dispatch : @rabbita.Dispatch[Msg],
  model : Model,
) -> @rabbita.Html {
  @html.div(
    style=[
      "height: 100vh", "min-height: 0", "display: flex", "align-items: stretch",
      "background: transparent", "overflow: hidden",
    ],
    [
      render_project_sidebar(dispatch, model),
      @html.div(
        style=[
          "flex: 1", "min-width: 0", "padding: 16px", "display: flex", "flex-direction: column",
          "gap: 16px", "box-sizing: border-box", "min-height: 0", "overflow: hidden",
        ],
        [
          render_account_toolbar(dispatch, model),
          @html.div(
            style=[
              "flex: 1", "min-width: 0", "min-height: 0", "display: flex", "gap: 16px",
              "align-items: stretch", "overflow: hidden",
            ],
            [
              render_workspace_panel(dispatch, model),
              render_preview_panel(model),
            ],
          ),
        ],
      ),
    ],
  )
}

///|
fn view(dispatch : @rabbita.Dispatch[Msg], model : Model) -> @rabbita.Html {
  if model.session_ready && model.current_user is Some(_) {
    @html.div(
      style=app_root_style(model.resolved_theme_mode),
      render_workspace_shell(dispatch, model),
    )
  } else {
    let body = if !model.session_ready {
      render_loading_screen()
    } else {
      render_auth_screen(dispatch, model)
    }
    @html.div(
      style=app_root_style(model.resolved_theme_mode),
      @html.div(style=app_stack_style(), [
        render_app_header(dispatch, model),
        body,
      ]),
    )
  }
}
