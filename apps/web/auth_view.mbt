///|
fn theme_toggle_button(
  dispatch : @rabbita.Dispatch[Msg],
  model : Model,
) -> @rabbita.Html {
  @html.button(
    type_="button",
    on_click=dispatch(ToggleTheme),
    style=secondary_button_style(true),
    "Theme: " + model.theme_mode.label(),
  )
}

///|
fn render_app_header(
  dispatch : @rabbita.Dispatch[Msg],
  model : Model,
) -> @rabbita.Html {
  @html.div(
    style=panel_style() +
      [
        "padding: 12px 14px", "display: flex", "align-items: center", "justify-content: space-between",
        "gap: 12px",
      ],
    [
      @html.div(style=["display: flex", "align-items: center", "gap: 10px"], [
        brand_logo(38),
        @html.div(
          style=[
            "font-size: 22px", "font-weight: 780", "letter-spacing: -0.02em",
          ],
          "MoonBit Cloud",
        ),
      ]),
      theme_toggle_button(dispatch, model),
    ],
  )
}

///|
fn auth_mode_button(
  dispatch : @rabbita.Dispatch[Msg],
  current : AuthMode,
  value : AuthMode,
  label : String,
) -> @rabbita.Html {
  let active = current == value
  @html.button(
    type_="button",
    on_click=dispatch(AuthModeSelected(value)),
    style=button_style(
        if active {
          "linear-gradient(135deg, var(--action-strong), var(--action))"
        } else {
          "transparent"
        },
        if active {
          "var(--on-action)"
        } else {
          "var(--text-2)"
        },
        true,
      ) +
      ["flex: 1"],
    label,
  )
}

///|
fn auth_field(
  label : String,
  field_id : String,
  input_type : @html.InputType,
  value : String,
  placeholder : String,
  on_input : (String) -> Msg,
  dispatch : @rabbita.Dispatch[Msg],
) -> @rabbita.Html {
  @html.div(style=["display: flex", "flex-direction: column", "gap: 8px"], [
    @html.label(for_=field_id, style=section_label_style(), label),
    @html.input(
      input_type~,
      id=field_id,
      value~,
      placeholder~,
      on_input=fn(next) { dispatch(on_input(next)) },
      style=input_style(false),
      "",
    ),
  ])
}

///|
fn render_notice_card(notice : String?, tone : String) -> @rabbita.Html {
  match notice {
    Some(message) =>
      @html.div(
        style=[
          "padding: 12px 14px",
          "border-radius: 6px",
          "background: " + tone,
          "border: 1px solid var(--border-soft)",
          "font-size: 14px",
          "line-height: 1.6",
          "color: var(--text-1)",
        ],
        message,
      )
    None => @html.nothing
  }
}

///|
fn render_auth_screen(
  dispatch : @rabbita.Dispatch[Msg],
  model : Model,
) -> @rabbita.Html {
  let title = match model.auth_mode {
    Login => "Return to the workspace"
    Signup => "Build apps without opening the code"
    ForgotPassword => "Reset your password"
  }
  let subtitle = match model.auth_mode {
    Login => "Sign in to resume your projects and previews."
    Signup =>
      "Describe what you want, let the agent update the workspace, and watch the preview."
    ForgotPassword => "Enter your email and use the local outbox reset link."
  }
  let submit_label = if model.auth_pending {
    "Working..."
  } else {
    match model.auth_mode {
      Login => "Log In"
      Signup => "Create Account"
      ForgotPassword => "Send Reset Link"
    }
  }
  @html.div(
    style=[
      "display: flex", "flex-wrap: wrap", "gap: 10px", "align-items: stretch", "flex: 1",
    ],
    [
      @html.div(
        style=panel_style() +
          [
            "flex: 1 1 360px", "min-width: 320px", "padding: 22px", "display: flex",
            "flex-direction: column", "gap: 12px", "justify-content: center",
          ],
        [
          @html.div(
            style=[
              "font-size: 42px", "line-height: 1.02", "font-weight: 780", "max-width: 620px",
            ],
            title,
          ),
          @html.div(
            style=[
              "font-size: 17px", "line-height: 1.7", "color: var(--text-2)", "max-width: 620px",
            ],
            subtitle,
          ),
        ],
      ),
      @html.div(
        style=panel_style() +
          [
            "flex: 1 1 420px", "min-width: 320px", "max-width: 560px", "padding: 22px",
            "display: flex", "flex-direction: column", "gap: 14px",
          ],
        [
          @html.div(
            style=[
              "display: flex", "gap: 6px", "padding: 4px", "border-radius: 8px",
              "background: var(--surface-3)", "border: 1px solid var(--border-soft)",
            ],
            [
              auth_mode_button(dispatch, model.auth_mode, Signup, "Sign Up"),
              auth_mode_button(dispatch, model.auth_mode, Login, "Log In"),
            ],
          ),
          render_notice_card(model.auth_notice, "var(--danger-soft)"),
          auth_field(
            "Email",
            "auth-email",
            @html.Email,
            model.auth_email,
            "name@example.com",
            fn(value) { AuthEmailChanged(value) },
            dispatch,
          ),
          if model.auth_mode is ForgotPassword {
            @html.nothing
          } else {
            auth_field(
              "Password",
              "auth-password",
              @html.Password,
              model.auth_password,
              "At least 8 characters",
              fn(value) { AuthPasswordChanged(value) },
              dispatch,
            )
          },
          if model.auth_mode is Signup {
            auth_field(
              "Display Name",
              "auth-display-name",
              @html.Text,
              model.auth_display_name,
              "Optional operator name",
              fn(value) { AuthDisplayNameChanged(value) },
              dispatch,
            )
          } else {
            @html.nothing
          },
          if model.auth_mode is Login {
            @html.button(
              type_="button",
              on_click=dispatch(AuthModeSelected(ForgotPassword)),
              style=[
                "align-self: flex-start", "border: none", "background: transparent",
                "color: var(--text-2)", "padding: 0", "font-size: 13px", "font-weight: 700",
                "cursor: pointer",
              ],
              "Forgot password?",
            )
          } else if model.auth_mode is ForgotPassword {
            @html.button(
              type_="button",
              on_click=dispatch(AuthModeSelected(Login)),
              style=[
                "align-self: flex-start", "border: none", "background: transparent",
                "color: var(--text-2)", "padding: 0", "font-size: 13px", "font-weight: 700",
                "cursor: pointer",
              ],
              "Back to log in",
            )
          } else {
            @html.nothing
          },
          @html.button(
            type_="button",
            disabled=!can_submit_auth(model),
            on_click=dispatch(SubmitAuth),
            style=primary_button_style(can_submit_auth(model)),
            submit_label,
          ),
          if model.github_enabled && !(model.auth_mode is ForgotPassword) {
            @html.fragment([
              @html.div(
                style=[
                  "display: flex", "align-items: center", "gap: 12px", "color: var(--text-3)",
                ],
                [
                  @html.div(
                    style=[
                      "flex: 1", "height: 1px", "background: var(--border-soft)",
                    ],
                    "",
                  ),
                  @html.div(style=section_label_style(), "or"),
                  @html.div(
                    style=[
                      "flex: 1", "height: 1px", "background: var(--border-soft)",
                    ],
                    "",
                  ),
                ],
              ),
              @html.a(
                href="/auth/github/start",
                style=secondary_button_style(true) +
                  [
                    "text-decoration: none", "justify-content: center", "padding: 12px 14px",
                  ],
                "Continue with GitHub",
              ),
            ])
          } else {
            @html.nothing
          },
        ],
      ),
    ],
  )
}
