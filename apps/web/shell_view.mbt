///|
fn render_loading_screen() -> @rabbita.Html {
  @html.div(style=["display: grid", "place-items: center", "flex: 1"]) <| (@html.div(
    style=panel_style() +
      [
        "padding: 26px 30px", "display: flex", "flex-direction: column", "gap: 10px",
        "min-width: 340px",
      ],
  ) <| [
    @html.div(
      style=["font-size: 30px", "line-height: 1.05", "font-weight: 600"],
      "Opening Mooncraft",
    ),
    @html.div(
      style=["font-size: 14px", "line-height: 1.6", "color: var(--text-2)"],
      "Preparing your project workspace.",
    ),
  ])
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
  ) <| label
}

///|
fn sidebar_project_item(
  dispatch : @rabbita.Dispatch[Msg],
  model : Model,
  project : @sdk.ProjectSummary,
) -> @rabbita.Html {
  let selected = model.active_page is AppWorkspace &&
    model.selected_project_id == Some(project.id)
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
  let delete_enabled = !(project.status is Running || deleting)
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
  ) <| [
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
  ]
}

///|
fn account_password_input(
  value : String,
  placeholder : String,
  on_input : (String) -> Msg,
  dispatch : @rabbita.Dispatch[Msg],
) -> @rabbita.Html {
  @html.input(
    input_type=Password,
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
  ) <| label
}

///|
fn ai_key_status_text(user : @sdk.UserSummary) -> String {
  if user.ai_api_key_configured {
    "Key saved"
  } else {
    "Key missing"
  }
}

///|
fn model_option_label(option : @sdk.ModelOption) -> String {
  let prefix = if option.recommended { "Recommended - " } else { "" }
  if option.label == option.id {
    prefix + option.id
  } else {
    prefix + option.label + " (" + option.id + ")"
  }
}

///|
fn model_option_select_items(model : Model) -> Array[@rabbita.Html] {
  let items : Array[@rabbita.Html] = []
  if model.account_ai_model != "" &&
    !model_options_include(model.account_model_options, model.account_ai_model) {
    items.push(
      @html.option(
        value=model.account_ai_model,
        selected=true,
        "Current - " + model.account_ai_model,
      ),
    )
  }
  for option in model.account_model_options {
    items.push(
      @html.option(
        value=option.id,
        selected=option.id == model.account_ai_model,
        model_option_label(option),
      ),
    )
  }
  items
}

///|
fn render_model_selector(
  dispatch : @rabbita.Dispatch[Msg],
  model : Model,
) -> @rabbita.Html {
  let disabled = model.account_model_options_pending ||
    model.account_model_options.length() == 0
  let select_items = if model.account_model_options_pending {
    [
      @html.option(
        value=model.account_ai_model,
        selected=true,
        "Loading models...",
      ),
    ]
  } else {
    model_option_select_items(model)
  }
  @html.div(style=["display: flex", "flex-direction: column", "gap: 7px"]) <| [
    @html.label(
      for_="ai-model-select",
      style=["font-size: 12px", "font-weight: 700", "color: var(--text-2)"],
      "Model",
    ),
    @html.select(
      id="ai-model-select",
      disabled~,
      on_change=fn(value) { dispatch(AccountAiModelChanged(value)) },
      style=input_style(false) +
        [
          "padding: 9px 10px", "font-size: 13px", "border-color: var(--border-soft)",
          "background: var(--surface-1)",
        ],
      select_items,
    ),
    @html.div(
      style=[
        "display: flex", "align-items: center", "justify-content: space-between",
        "gap: 8px",
      ],
      [
        @html.div(
          style=["font-size: 12px", "line-height: 1.5", "color: var(--text-2)"],
          if model.account_model_options_pending {
            "Loading models from " + model.account_ai_provider + "."
          } else if model.account_model_options.length() == 0 {
            "No live model list is available. The saved model will be kept."
          } else {
            "Choose a model available for this provider."
          },
        ),
        @html.button(
          type_="button",
          disabled=model.account_model_options_pending,
          on_click=dispatch(RefreshModelOptions),
          style=button_style("var(--surface-1)", "var(--text-2)", true) +
            ["padding: 7px 9px", "font-size: 12px", "white-space: nowrap"],
          "Refresh list",
        ),
      ],
    ),
  ]
}

///|
fn render_ai_settings_form(
  dispatch : @rabbita.Dispatch[Msg],
  model : Model,
  user : @sdk.UserSummary,
  compact : Bool,
) -> @rabbita.Html {
  let padding = if compact { "10px" } else { "18px" }
  let radius = if compact { "10px" } else { "18px" }
  let key_placeholder = if user.ai_api_key_configured {
    "Leave blank to keep saved API key"
  } else {
    "API key"
  }
  @html.div(
    style=[
      "display: flex",
      "flex-direction: column",
      "gap: 12px",
      "padding: " + padding,
      "border: 1px solid var(--border-soft)",
      "border-radius: " + radius,
      "background: var(--surface-2)",
    ],
  ) <| [
    @html.div(
      style=[
        "display: flex", "align-items: center", "justify-content: space-between",
        "gap: 10px",
      ],
      [
        @html.div(style=section_label_style(), "Provider & Key"),
        @html.div(
          style=mono_style() +
            [
              "font-size: 11px", "color: var(--text-2)", "padding: 5px 8px", "border: 1px solid var(--border-soft)",
              "border-radius: 999px", "background: var(--surface-3)", "white-space: nowrap",
            ],
          ai_key_status_text(user),
        ),
      ],
    ),
    @html.div(
      style=["font-size: 13px", "line-height: 1.6", "color: var(--text-2)"],
      "Mooncraft uses this provider only when running your project agent. API keys are stored on your account and are never shown again.",
    ),
    render_notice_card(model.account_notice, "var(--warning-soft)"),
    @html.div(style=["display: flex", "gap: 8px"], [
      ai_provider_button(dispatch, model, "openai", "OpenAI"),
      ai_provider_button(dispatch, model, "openrouter", "OpenRouter"),
    ]),
    render_model_selector(dispatch, model),
    account_password_input(
      model.account_ai_api_key,
      key_placeholder,
      fn(value) { AccountAiApiKeyChanged(value) },
      dispatch,
    ),
    @html.button(
      type_="button",
      disabled=!can_save_ai_settings(model),
      on_click=dispatch(SaveAiSettings),
      style=primary_button_style(can_save_ai_settings(model)) +
        ["padding: 10px 12px", "font-size: 13px"],
      if model.account_pending {
        "Saving..."
      } else {
        "Save LLM Config"
      },
    ),
  ]
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
            "background: var(--surface-raised)", "backdrop-filter: none",
          ],
      ) <| [
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
            "border: 1px solid var(--border-soft)", "border-radius: 10px", "background: var(--surface-2)",
          ],
          [
            @html.div(
              style=[
                "display: flex", "align-items: center", "justify-content: space-between",
                "gap: 8px",
              ],
              [
                @html.div(style=section_label_style(), "LLM Config"),
                @html.div(
                  style=mono_style() +
                    ["font-size: 10px", "color: var(--text-3)"],
                  ai_key_status_text(user),
                ),
              ],
            ),
            @html.button(
              type_="button",
              on_click=dispatch(OpenLlmConfig),
              style=secondary_button_style(true) +
                ["padding: 9px 10px", "font-size: 12px"],
              "Open LLM Config",
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
        style=panel_style() +
          [
            "position: relative", "padding: 12px 16px", "display: flex", "align-items: center",
            "justify-content: space-between", "gap: 10px", "flex-wrap: wrap", "flex-shrink: 0",
            "overflow: visible", "z-index: 20",
          ],
      ) <| [
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
      ]
    None => @html.nothing
  }
}

///|
fn sidebar_llm_config_button(
  dispatch : @rabbita.Dispatch[Msg],
  model : Model,
  user : @sdk.UserSummary,
) -> @rabbita.Html {
  let selected = model.active_page is LlmConfig
  let background = if selected {
    "linear-gradient(135deg, rgba(15, 118, 110, 0.13), rgba(37, 99, 235, 0.09))"
  } else {
    "rgba(255, 255, 255, 0.34)"
  }
  let border_color = if selected {
    "var(--border-strong)"
  } else {
    "rgba(15, 23, 42, 0.08)"
  }
  @html.button(
    type_="button",
    on_click=dispatch(OpenLlmConfig),
    style=[
      "width: 100%",
      "padding: 12px",
      "border: 1px solid " + border_color,
      "border-radius: 14px",
      "background: " + background,
      "color: var(--text-1)",
      "cursor: pointer",
      "display: flex",
      "align-items: center",
      "justify-content: space-between",
      "gap: 10px",
      "text-align: left",
    ],
  ) <| [
    @html.div(
      style=[
        "display: flex", "flex-direction: column", "gap: 4px", "min-width: 0",
      ],
      [
        @html.div(style=["font-size: 14px", "font-weight: 700"], "LLM Config"),
        @html.div(
          style=mono_style() + ["font-size: 11px", "color: var(--text-3)"],
          user.ai_provider + " / " + user.ai_model,
        ),
      ],
    ),
    @html.div(
      style=mono_style() +
        [
          "font-size: 10px", "color: var(--text-2)", "padding: 5px 8px", "border: 1px solid var(--border-soft)",
          "border-radius: 999px", "background: var(--surface-2)", "white-space: nowrap",
        ],
      ai_key_status_text(user),
    ),
  ]
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
  ) <| [
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
              "font-size: 12px", "color: var(--text-3)", "white-space: nowrap", "overflow: hidden",
              "text-overflow: ellipsis",
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
    match model.current_user {
      Some(user) => sidebar_llm_config_button(dispatch, model, user)
      None => @html.nothing
    },
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
        "display: flex", "flex-direction: column", "gap: 8px", "min-height: 0", "overflow-y: auto",
        "overscroll-behavior: contain", "flex: 1",
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
  ]
}

///|
fn render_llm_config_page(
  dispatch : @rabbita.Dispatch[Msg],
  model : Model,
) -> @rabbita.Html {
  match model.current_user {
    Some(user) =>
      @html.div(
        style=["flex: 1", "min-width: 0", "min-height: 0", "overflow: auto"],
      ) <| (@html.div(
        style=panel_style() +
          [
            "min-height: 100%", "padding: 28px", "display: flex", "flex-direction: column",
            "gap: 24px", "box-sizing: border-box",
          ],
      ) <| [
        @html.div(
          style=[
            "display: flex", "align-items: flex-start", "justify-content: space-between",
            "gap: 24px",
          ],
          [
            @html.div(
              style=[
                "display: flex", "flex-direction: column", "gap: 8px", "max-width: 620px",
              ],
              [
                @html.div(style=section_label_style(), "Account Settings"),
                @html.div(
                  style=[
                    "font-size: 34px", "line-height: 1.05", "font-weight: 700", "letter-spacing: -0.04em",
                  ],
                  "LLM Config",
                ),
                @html.div(
                  style=[
                    "font-size: 15px", "line-height: 1.7", "color: var(--text-2)",
                  ],
                  "Choose the provider, model, and API key Mooncraft should use when a project asks the agent to build or update software.",
                ),
              ],
            ),
            @html.div(
              style=mono_style() +
                [
                  "font-size: 12px", "color: var(--text-2)", "padding: 8px 10px",
                  "border: 1px solid var(--border-soft)", "border-radius: 999px",
                  "background: var(--surface-2)", "white-space: nowrap",
                ],
              ai_key_status_text(user),
            ),
          ],
        ),
        @html.div(
          style=[
            "display: grid", "grid-template-columns: minmax(420px, 620px) minmax(280px, 1fr)",
            "gap: 18px", "align-items: start",
          ],
          [
            render_ai_settings_form(dispatch, model, user, false),
            @html.div(
              style=inset_panel_style() +
                [
                  "padding: 18px", "display: flex", "flex-direction: column", "gap: 14px",
                  "background: var(--surface-2)",
                ],
              [
                @html.div(style=section_label_style(), "Provider Notes"),
                @html.div(
                  style=[
                    "display: flex", "flex-direction: column", "gap: 12px", "font-size: 13px",
                    "line-height: 1.6", "color: var(--text-2)",
                  ],
                  [
                    @html.div(
                      "OpenAI model IDs can be entered directly, for example gpt-5.5.",
                    ),
                    @html.div(
                      "OpenRouter model IDs should include the provider prefix, for example openai/gpt-5.5.",
                    ),
                    @html.div(
                      "Leave the API key field blank when a key is already saved and you only want to change the model.",
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ])
    None => @html.nothing
  }
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
  ) <| [
    render_project_sidebar(dispatch, model),
    @html.div(
      style=[
        "flex: 1", "min-width: 0", "padding: 16px", "display: flex", "flex-direction: column",
        "gap: 16px", "box-sizing: border-box", "min-height: 0", "overflow: hidden",
      ],
      [
        render_account_toolbar(dispatch, model),
        if model.active_page is LlmConfig {
          render_llm_config_page(dispatch, model)
        } else {
          @html.div(
            style=[
              "flex: 1", "min-width: 0", "min-height: 0", "display: flex", "gap: 16px",
              "align-items: stretch", "overflow: hidden",
            ],
            [
              render_workspace_panel(dispatch, model),
              render_preview_panel(model),
            ],
          )
        },
      ],
    ),
  ]
}

///|
fn view(dispatch : @rabbita.Dispatch[Msg], model : Model) -> @rabbita.Html {
  if model.session_ready && model.current_user is Some(_) {
    @html.div(style=app_root_style(model.resolved_theme_mode)) <| render_workspace_shell(
      dispatch, model,
    )
  } else {
    let body = if !model.session_ready {
      render_loading_screen()
    } else {
      render_auth_screen(dispatch, model)
    }
    @html.div(style=app_root_style(model.resolved_theme_mode)) <| (@html.div(
      style=app_stack_style(),
    ) <| [
      render_app_header(dispatch, model),
      body,
    ])
  }
}
