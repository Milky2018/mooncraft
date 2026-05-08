///|
fn theme_toggle_button(
  dispatch : @rabbita.Dispatch[Msg],
  model : Model,
) -> @rabbita.Html {
  let label = "Theme: " + model.theme_mode.label()
  @html.button(
    type_="button",
    on_click=dispatch(ToggleTheme),
    style=secondary_button_style(true),
  ) <| label
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
  ) <| [
    @html.div(style=["display: flex", "align-items: center", "gap: 10px"], [
      brand_logo(38),
      @html.div(
        style=["font-size: 22px", "font-weight: 600", "letter-spacing: -0.02em"],
        "Mooncraft",
      ),
    ]),
    theme_toggle_button(dispatch, model),
  ]
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
      ) <| message
    None => @html.nothing
  }
}

///|
fn render_auth_screen(
  dispatch : @rabbita.Dispatch[Msg],
  model : Model,
) -> @rabbita.Html {
  let _ = dispatch
  @html.div(
    style=[
      "display: flex", "flex-wrap: wrap", "gap: 12px", "align-items: stretch", "flex: 1",
    ],
  ) <| [
    @html.div(
      style=panel_style() +
        [
          "flex: 1 1 360px", "min-width: 320px", "padding: 28px", "display: flex",
          "flex-direction: column", "gap: 18px", "justify-content: center",
        ],
    ) <| [
      @html.div(
        style=[
          "font-size: 40px", "line-height: 1.04", "font-weight: 600", "letter-spacing: -0.03em",
          "max-width: 620px",
        ],
      ) <| "Build apps without opening the code",
      @html.div(
        style=[
          "font-size: 16px", "line-height: 1.65", "color: var(--text-2)", "max-width: 620px",
        ],
      ) <| "Sign in with GitHub, describe what you want, let the agent update the workspace, and watch the preview.",
      @html.div(
        style=[
          "display: grid", "grid-template-columns: repeat(3, minmax(0, 1fr))", "gap: 10px",
          "padding-top: 18px", "max-width: 640px",
        ],
      ) <| [
        auth_story_card("1", "Describe", "Tell Mooncraft what you want."),
        auth_story_card("2", "Build", "The agent edits the workspace."),
        auth_story_card("3", "Preview", "Watch the app run live."),
      ],
    ],
    @html.div(
      style=panel_style() +
        [
          "flex: 1 1 420px", "min-width: 320px", "max-width: 560px", "padding: 22px",
          "display: flex", "flex-direction: column", "gap: 14px",
        ],
    ) <| [
      @html.div(style=["display: flex", "align-items: center", "gap: 10px"]) <| [
        brand_logo(42),
        @html.div(
          style=["display: flex", "flex-direction: column", "gap: 4px"],
          [
            @html.div(
              style=[
                "font-size: 18px", "font-weight: 700", "color: var(--text-1)",
              ],
              "Sign in to Mooncraft",
            ),
            @html.div(
              style=[
                "font-size: 13px", "line-height: 1.55", "color: var(--text-2)",
              ],
              "GitHub is the only supported account provider.",
            ),
          ],
        ),
      ],
      render_notice_card(model.auth_notice, "var(--danger-soft)"),
      if model.github_enabled {
        @html.a(
          href=@sdk.github_login_path(),
          style=primary_button_style(true) +
            [
              "text-decoration: none", "justify-content: center", "padding: 13px 16px",
              "font-size: 15px",
            ],
        ) <| "Continue with GitHub"
      } else {
        @html.div(
          style=[
            "padding: 14px", "border-radius: 12px", "background: var(--warning-soft)",
            "border: 1px solid var(--border-soft)", "font-size: 14px", "line-height: 1.6",
            "color: var(--text-1)",
          ],
        ) <| "Sign-in is temporarily unavailable. Please try again later."
      },
      @html.div(
        style=["font-size: 12px", "line-height: 1.55", "color: var(--text-3)"],
        "Mooncraft uses your verified GitHub email to create or link your account.",
      ),
    ],
  ]
}

///|
fn auth_story_card(
  step : String,
  title : String,
  body : String,
) -> @rabbita.Html {
  @html.div(
    style=[
      "padding: 14px", "border-radius: 14px", "background: var(--surface-2)", "border: 1px solid var(--border-soft)",
      "display: flex", "flex-direction: column", "gap: 8px", "min-height: 104px",
    ],
  ) <| [
    @html.div(
      style=mono_style() +
        [
          "width: 24px", "height: 24px", "border-radius: 999px", "display: grid",
          "place-items: center", "background: var(--accent-soft)", "color: var(--accent-strong)",
          "font-size: 11px", "font-weight: 700",
        ],
    ) <| step,
    @html.div(
      style=["font-size: 15px", "font-weight: 600", "color: var(--text-1)"],
    ) <| title,
    @html.div(
      style=["font-size: 12px", "line-height: 1.55", "color: var(--text-2)"],
    ) <| body,
  ]
}
